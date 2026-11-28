// macOS brightness implementation.
//
// Backend selection (priority order):
//   1. DisplayServices (private framework) — Apple native displays:
//      built-in MacBook/iMac panel, Apple Studio Display, Pro Display XDR.
//   2. DDC/CI via IOAVService (private IOKit API) — third-party external
//      monitors connected via USB-C / Thunderbolt / DisplayPort Alt-Mode on
//      Apple Silicon Macs.  Based on the open-source m1ddc project
//      (https://github.com/waydabber/m1ddc, MIT licence).
//
// ⚠  DDC backend limitations:
//   • Built-in HDMI port on M1 and entry-level M2 Macs: NOT supported.
//   • Intel Macs: IOI2C path not implemented; only Apple displays work.
//   • Displays through USB hubs that block DDC signals: NOT supported.
//   • App Sandbox (Mac App Store) builds: IOKit private API is blocked.

#import "device_screen_brightness_native.h"
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <stdlib.h>

// ── Private type alias ───────────────────────────────────────────────────────

typedef CFTypeRef IOAVServiceRef;

// ── Function pointer types ───────────────────────────────────────────────────

// DisplayServices
typedef int  (*DS_GetBrFn)(CGDirectDisplayID, float *);
typedef int  (*DS_SetBrFn)(CGDirectDisplayID, float);
typedef bool (*DS_CanChFn)(CGDirectDisplayID);

// IOAVService  (private symbols inside IOKit.framework)
typedef IOAVServiceRef (*IOAVSvc_CreateFn)       (CFAllocatorRef);
typedef IOAVServiceRef (*IOAVSvc_CreateWithSvcFn) (CFAllocatorRef, io_service_t);
typedef IOReturn       (*IOAVSvc_WriteI2CFn)      (IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);
typedef IOReturn       (*IOAVSvc_ReadI2CFn)       (IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);

// CoreDisplay  (private framework)
typedef CFDictionaryRef (*CD_DisplayInfoFn)(CGDirectDisplayID);

// ── DDC/CI constants ─────────────────────────────────────────────────────────

#define DDC_VCP_LUMINANCE  0x10u   // VCP code for brightness
#define DDC_INPUT_ADDR     0x51u   // DDC command address (host → monitor)
#define DDC_CHIP_ADDR      0x37u   // I²C 7-bit address (0x6E >> 1)
#define DDC_WAIT_US        10000u  // µs wait between I²C operations
#define DDC_ITERATIONS     2       // write repetitions for reliability
#define DDC_REPLY_BYTES    12      // bytes requested in a VCP feature reply

// ── Helpers ──────────────────────────────────────────────────────────────────

static DeviceScreenBrightnessResult dsb_ok(int32_t value) {
  DeviceScreenBrightnessResult r = {value, 0, 100, 0, DSB_OK};
  return r;
}

static DeviceScreenBrightnessResult dsb_error(int32_t code) {
  DeviceScreenBrightnessResult r = {0, 0, 0, 0, code};
  return r;
}

// ── Backend state ─────────────────────────────────────────────────────────────

typedef enum { BK_NONE = 0, BK_DISPLAY_SERVICES, BK_DDC } dsb_bk_t;

static dsb_bk_t           s_bk       = BK_NONE;
static bool               s_probed   = false;

// BK_DISPLAY_SERVICES
static DS_GetBrFn         s_ds_get   = NULL;
static DS_SetBrFn         s_ds_set   = NULL;

// BK_DDC
static IOAVServiceRef     s_av       = NULL;
static IOAVSvc_WriteI2CFn s_av_write = NULL;
static IOAVSvc_ReadI2CFn  s_av_read  = NULL;

// ── DDC helpers ──────────────────────────────────────────────────────────────

// Number of significant (non-zero trailing) bytes in a zero-padded buffer.
static int ddc_sig_bytes(const uint8_t *buf, int max) {
  int n = 0;
  for (int i = 0; i < max; i++) if (buf[i]) n = i + 1;
  return n;
}

// Send DDC VCP set-feature command for luminance (VCP 0x10, value 0-100).
static bool ddc_write_luminance(uint16_t value) {
  uint8_t pkt[16] = {0};
  pkt[0] = 0x84;
  pkt[1] = 0x03;
  pkt[2] = DDC_VCP_LUMINANCE;
  pkt[3] = (uint8_t)((value >> 8) & 0xFF);
  pkt[4] = (uint8_t)(value & 0xFF);
  pkt[5] = (uint8_t)(0x6E ^ DDC_INPUT_ADDR ^ pkt[0] ^ pkt[1] ^ pkt[2] ^ pkt[3] ^ pkt[4]);

  int len = ddc_sig_bytes(pkt, 16);
  for (int i = 0; i < DDC_ITERATIONS; i++) {
    usleep(DDC_WAIT_US);
    if (s_av_write(s_av, DDC_CHIP_ADDR, DDC_INPUT_ADDR, pkt, (uint32_t)len)
        != kIOReturnSuccess) return false;
  }
  return true;
}

// Send DDC VCP get-feature request for luminance, read and parse the reply.
// Returns current luminance (0-100), or -1 on failure.
//
// I²C reply layout (12 bytes from IOAVServiceReadI2C):
//   [0] src-addr 0x6E  [1] length  [2] cmd 0x02  [3] result
//   [4] VCP code        [5] VCP type
//   [6] max MSB         [7] max LSB
//   [8] cur MSB         [9] cur LSB
//   [10] checksum
static int32_t ddc_read_luminance(void) {
  // Build get-VCP-feature request packet (same as m1ddc prepareDDCRead).
  uint8_t req[16] = {0};
  req[0] = 0x82;
  req[1] = 0x01;
  req[2] = DDC_VCP_LUMINANCE;
  req[3] = (uint8_t)(0x6E ^ req[0] ^ req[1] ^ req[2]);
  int req_len = ddc_sig_bytes(req, 16);

  for (int i = 0; i < DDC_ITERATIONS; i++) {
    usleep(DDC_WAIT_US);
    if (s_av_write(s_av, DDC_CHIP_ADDR, DDC_INPUT_ADDR, req, (uint32_t)req_len)
        != kIOReturnSuccess) return -1;
  }

  uint8_t resp[DDC_REPLY_BYTES] = {0};
  usleep(DDC_WAIT_US);
  if (s_av_read(s_av, DDC_CHIP_ADDR, DDC_INPUT_ADDR, resp, DDC_REPLY_BYTES)
      != kIOReturnSuccess) return -1;

  // Parse current luminance from bytes 8-9 (big-endian uint16).
  uint16_t cur = ((uint16_t)resp[8] << 8) | resp[9];
  return (int32_t)cur;
}

// ── IORegistry: find IOAVService for the given CGDirectDisplayID ──────────────

static IOAVServiceRef dsb_find_av_for_display(
    CGDirectDisplayID        display_id,
    CD_DisplayInfoFn         cd_info_fn,
    IOAVSvc_CreateWithSvcFn  create_fn)
{
  CFDictionaryRef info = cd_info_fn(display_id);
  if (!info) return NULL;

  NSString *ioPath = (NSString *)CFDictionaryGetValue(info, CFSTR("IODisplayLocation"));
  CFRelease(info);
  if (!ioPath || ioPath.length == 0) return NULL;

  mach_port_t main_port = kIOMasterPortDefault;
  if (@available(macOS 12.0, *)) main_port = kIOMainPortDefault;
  io_registry_entry_t root = IORegistryGetRootEntry(main_port);
  io_iterator_t iter = IO_OBJECT_NULL;
  kern_return_t kr = IORegistryEntryCreateIterator(
      root, kIOServicePlane, kIORegistryIterateRecursively, &iter);
  IOObjectRelease(root);
  if (kr != KERN_SUCCESS) return NULL;

  IOAVServiceRef result = NULL;
  io_service_t   svc;
  bool found_target = false;

  // Phase 1: advance the iterator until we reach the display's IORegistry node.
  while (!found_target && (svc = IOIteratorNext(iter)) != MACH_PORT_NULL) {
    io_string_t path;
    IORegistryEntryGetPath(svc, kIOServicePlane, path);
    if (strcmp(path, ioPath.UTF8String) == 0) found_target = true;
    IOObjectRelease(svc);
  }

  // Phase 2: iterate descendants of the matched node looking for DCPAVServiceProxy.
  if (found_target) {
    while ((svc = IOIteratorNext(iter)) != MACH_PORT_NULL) {
      io_name_t name;
      IORegistryEntryGetName(svc, name);
      if (strcmp(name, "DCPAVServiceProxy") == 0) {
        IOAVServiceRef av = create_fn(kCFAllocatorDefault, svc);
        if (av) {
          // Exclude virtual displays (Sidecar, AirPlay) whose Location != "External".
          CFStringRef loc = (CFStringRef)IORegistryEntrySearchCFProperty(
              svc, kIOServicePlane, CFSTR("Location"),
              kCFAllocatorDefault, kIORegistryIterateRecursively);
          if (loc && CFStringCompare(loc, CFSTR("External"), 0) == 0) {
            result = av;
          } else {
            CFRelease(av);
          }
          if (loc) CFRelease(loc);
        }
      }
      IOObjectRelease(svc);
      if (result) break;
    }
  }

  IOObjectRelease(iter);
  return result;
}

// ── Probe (runs once on first API call) ──────────────────────────────────────

static void dsb_probe(void) {
  if (s_probed) return;
  s_probed = true;

  CGDirectDisplayID main_disp = CGMainDisplayID();

  // ── 1. DisplayServices — Apple native displays ───────────────────────────
  void *ds = dlopen(
      "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
      RTLD_LAZY);
  if (ds) {
    DS_GetBrFn ds_get = (DS_GetBrFn)dlsym(ds, "DisplayServicesGetBrightness");
    DS_SetBrFn ds_set = (DS_SetBrFn)dlsym(ds, "DisplayServicesSetBrightness");
    DS_CanChFn ds_can = (DS_CanChFn)dlsym(ds, "DisplayServicesCanChangeBrightness");
    if (ds_get && ds_set && ds_can && ds_can(main_disp)) {
      s_ds_get = ds_get;
      s_ds_set = ds_set;
      s_bk = BK_DISPLAY_SERVICES;
      return;
    }
  }

  // ── 2. DDC/CI via IOAVService — third-party external, Apple Silicon ──────
  //
  // IOAVServiceWriteI2C / ReadI2C are private symbols inside IOKit.framework.
  // We resolve them at runtime via RTLD_DEFAULT (IOKit is always loaded by the
  // Flutter engine on macOS).
  IOAVSvc_WriteI2CFn av_write =
      (IOAVSvc_WriteI2CFn)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
  IOAVSvc_ReadI2CFn av_read =
      (IOAVSvc_ReadI2CFn)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
  if (!av_write || !av_read) return;

  IOAVSvc_CreateFn av_create =
      (IOAVSvc_CreateFn)dlsym(RTLD_DEFAULT, "IOAVServiceCreate");
  IOAVSvc_CreateWithSvcFn av_create_ws =
      (IOAVSvc_CreateWithSvcFn)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");

  IOAVServiceRef av = NULL;

  // Try per-display matching so multi-monitor setups pick the right service.
  void *cd = dlopen(
      "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
      RTLD_LAZY);
  if (cd && av_create_ws) {
    CD_DisplayInfoFn cd_info =
        (CD_DisplayInfoFn)dlsym(cd, "CoreDisplay_DisplayCreateInfoDictionary");
    if (cd_info) {
      av = dsb_find_av_for_display(main_disp, cd_info, av_create_ws);
    }
  }

  // Fall back to the default (first) external AV service.
  if (!av && av_create) {
    av = av_create(kCFAllocatorDefault);
  }

  if (!av) return;

  s_av       = av;
  s_av_write = av_write;
  s_av_read  = av_read;
  s_bk       = BK_DDC;
}

// ── Public API ───────────────────────────────────────────────────────────────

DeviceScreenBrightnessResult device_screen_brightness_get(void) {
  dsb_probe();
  switch (s_bk) {
    case BK_DISPLAY_SERVICES: {
      float v = 0;
      if (s_ds_get(CGMainDisplayID(), &v) != 0) return dsb_error(DSB_NATIVE_FAILURE);
      return dsb_ok((int32_t)(v * 100.0f + 0.5f));
    }
    case BK_DDC: {
      int32_t v = ddc_read_luminance();
      if (v < 0) return dsb_error(DSB_NATIVE_FAILURE);
      if (v > 100) v = 100;
      return dsb_ok(v);
    }
    default:
      return dsb_error(DSB_BACKEND_NOT_AVAILABLE);
  }
}

DeviceScreenBrightnessResult device_screen_brightness_set(int32_t value) {
  if (value < 0 || value > 100) return dsb_error(DSB_INVALID_VALUE);
  dsb_probe();
  switch (s_bk) {
    case BK_DISPLAY_SERVICES: {
      if (s_ds_set(CGMainDisplayID(), value / 100.0f) != 0)
        return dsb_error(DSB_NATIVE_FAILURE);
      usleep(100000);
      DeviceScreenBrightnessResult applied = device_screen_brightness_get();
      if (applied.error_code != DSB_OK || abs(applied.value - value) > 5)
        return dsb_error(DSB_NATIVE_FAILURE);
      return applied;
    }
    case BK_DDC: {
      if (!ddc_write_luminance((uint16_t)value)) return dsb_error(DSB_NATIVE_FAILURE);
      usleep(100000);
      DeviceScreenBrightnessResult applied = device_screen_brightness_get();
      if (applied.error_code != DSB_OK || abs(applied.value - value) > 5)
        return dsb_error(DSB_NATIVE_FAILURE);
      return applied;
    }
    default:
      return dsb_error(DSB_BACKEND_NOT_AVAILABLE);
  }
}

DeviceScreenBrightnessResult device_screen_brightness_increment(void) {
  DeviceScreenBrightnessResult cur = device_screen_brightness_get();
  if (cur.error_code != DSB_OK) return cur;
  int32_t next = cur.value + 5;
  if (next > 100) next = 100;
  return device_screen_brightness_set(next);
}

DeviceScreenBrightnessResult device_screen_brightness_decrement(void) {
  DeviceScreenBrightnessResult cur = device_screen_brightness_get();
  if (cur.error_code != DSB_OK) return cur;
  int32_t next = cur.value - 5;
  if (next < 0) next = 0;
  return device_screen_brightness_set(next);
}
