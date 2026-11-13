#include "hdr_video_host.h"

#ifdef NIVIO_LINUX_HDR
// libEGL directly, not epoxy: epoxy can't resolve EGL 1.5 entry points
// (eglGetPlatformDisplay) on a thread without a current display, and aborts.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <gdk/gdkwayland.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <future>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "color-management-v1-client-protocol.h"
#include "viewporter-client-protocol.h"
#endif

struct HdrVideoHost::State {
  GtkWindow* window = nullptr;
  FlView* view = nullptr;
  FlMethodChannel* channel = nullptr;
  gulong unmap_handler = 0;
  gulong window_allocate_handler = 0;
  gulong view_allocate_handler = 0;

#ifdef NIVIO_LINUX_HDR
  // Wayland objects live on Nivio's own event queue: GDK only dispatches its
  // own, and must never see events for objects it didn't create.
  wl_display* display = nullptr;
  wl_event_queue* queue = nullptr;
  wl_registry* registry = nullptr;
  wl_compositor* compositor = nullptr;
  wl_subcompositor* subcompositor = nullptr;
  wl_shm* shm = nullptr;
  wp_viewporter* viewporter = nullptr;
  wp_color_manager_v1* color_manager = nullptr;
  // What the compositor's colour management supports, as bit masks of the
  // protocol's enum values.
  uint32_t cm_features = 0;
  uint32_t cm_tfs = 0;
  uint32_t cm_primaries = 0;
  uint32_t cm_intents = 0;
  guint dispatch_source = 0;

  // Watches the preferred colour space of the app window's surface: it
  // changes when HDR is switched on / off or the window moves to another
  // screen.
  wl_surface* feedback_surface = nullptr;
  wp_color_management_surface_feedback_v1* feedback = nullptr;

  // Video: a black backdrop under the whole Flutter view (so nothing the
  // see-through window leaves unpainted shows the desktop), and mpv's surface
  // inside it at the video rect. Both are subsurfaces below the window's.
  bool attached = false;
  bool transparent = false;
  GtkCssProvider* css = nullptr;
  wl_surface* backdrop = nullptr;
  wl_subsurface* backdrop_sub = nullptr;
  wp_viewport* backdrop_viewport = nullptr;
  wl_buffer* backdrop_buffer = nullptr;
  wl_surface* video = nullptr;
  wl_subsurface* video_sub = nullptr;
  wp_viewport* video_viewport = nullptr;
  wp_color_management_surface_v1* video_cm = nullptr;
  // Video rect in physical pixels, relative to the Flutter view.
  int rect_x = 0, rect_y = 0, rect_w = 0, rect_h = 0;

  // Render thread: owns the EGL context and mpv's render context.
  mpv_handle* mpv = nullptr;
  std::thread thread;
  std::mutex mutex;
  std::condition_variable cv;
  bool stop = false;
  bool update = false;  // mpv has a new frame
  bool redraw = false;  // draw again (resized)
  bool size_dirty = false;
  int buffer_w = 0, buffer_h = 0;  // physical
  int dest_w = 0, dest_h = 0;      // logical (surface) size
  std::atomic<int64_t> frames{0};
  std::string error;
#endif
};

#ifdef NIVIO_LINUX_HDR
namespace {

using State = HdrVideoHost::State;

constexpr uint32_t Bit(uint32_t value) {
  return value < 32 ? (1u << value) : 0;
}

// --- Registry ---------------------------------------------------------------

void OnCmIntent(void* data, wp_color_manager_v1*, uint32_t intent) {
  static_cast<State*>(data)->cm_intents |= Bit(intent);
}
void OnCmFeature(void* data, wp_color_manager_v1*, uint32_t feature) {
  static_cast<State*>(data)->cm_features |= Bit(feature);
}
void OnCmTf(void* data, wp_color_manager_v1*, uint32_t tf) {
  static_cast<State*>(data)->cm_tfs |= Bit(tf);
}
void OnCmPrimaries(void* data, wp_color_manager_v1*, uint32_t primaries) {
  static_cast<State*>(data)->cm_primaries |= Bit(primaries);
}
void OnCmDone(void*, wp_color_manager_v1*) {}

const wp_color_manager_v1_listener kColorManagerListener = {
    OnCmIntent, OnCmFeature, OnCmTf, OnCmPrimaries, OnCmDone,
};

void OnGlobal(void* data,
              wl_registry* registry,
              uint32_t name,
              const char* interface,
              uint32_t version) {
  auto* s = static_cast<State*>(data);
  if (strcmp(interface, wl_compositor_interface.name) == 0) {
    s->compositor = static_cast<wl_compositor*>(wl_registry_bind(
        registry, name, &wl_compositor_interface, std::min(version, 4u)));
  } else if (strcmp(interface, wl_subcompositor_interface.name) == 0) {
    s->subcompositor = static_cast<wl_subcompositor*>(
        wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
  } else if (strcmp(interface, wl_shm_interface.name) == 0) {
    s->shm = static_cast<wl_shm*>(
        wl_registry_bind(registry, name, &wl_shm_interface, 1));
  } else if (strcmp(interface, wp_viewporter_interface.name) == 0) {
    s->viewporter = static_cast<wp_viewporter*>(
        wl_registry_bind(registry, name, &wp_viewporter_interface, 1));
  } else if (strcmp(interface, wp_color_manager_v1_interface.name) == 0) {
    // Version 1 is all this needs, and every compositor with the protocol
    // has it.
    s->color_manager = static_cast<wp_color_manager_v1*>(
        wl_registry_bind(registry, name, &wp_color_manager_v1_interface, 1));
    wp_color_manager_v1_add_listener(s->color_manager, &kColorManagerListener,
                                     s);
  }
}

void OnGlobalRemove(void*, wl_registry*, uint32_t) {}

const wl_registry_listener kRegistryListener = {OnGlobal, OnGlobalRemove};

// Everything an HDR video surface needs from the compositor.
bool HdrUsable(const State* s) {
  return s->compositor && s->subcompositor && s->shm && s->viewporter &&
         s->color_manager &&
         (s->cm_features & Bit(WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC)) &&
         (s->cm_tfs & Bit(WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ)) &&
         (s->cm_primaries & Bit(WP_COLOR_MANAGER_V1_PRIMARIES_BT2020)) &&
         (s->cm_intents & Bit(WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL));
}

// The app window's wl_surface; null while it isn't mapped. GDK creates a new
// one each time the window is shown, so never keep it.
wl_surface* WindowSurface(State* s) {
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(s->window));
  return window ? gdk_wayland_window_get_wl_surface(window) : nullptr;
}

void Roundtrip(State* s) {
  wl_display_roundtrip_queue(s->display, s->queue);
}

// --- Display info -----------------------------------------------------------

// An image description and, once asked, its parameters.
struct Description {
  int state = 0;  // 1 ready, -1 failed
  bool info_done = false;
  uint32_t tf = 0;
  bool has_luminances = false;
  double min_lum = 0, max_lum = 0, reference_lum = 0;
  bool has_target = false;
  double target_min = 0, target_max = 0;
};

void OnDescFailed(void* data, wp_image_description_v1*, uint32_t, const char*) {
  static_cast<Description*>(data)->state = -1;
}
void OnDescReady(void* data, wp_image_description_v1*, uint32_t) {
  static_cast<Description*>(data)->state = 1;
}
void OnDescReady2(void* data, wp_image_description_v1*, uint32_t, uint32_t) {
  static_cast<Description*>(data)->state = 1;
}
const wp_image_description_v1_listener kDescriptionListener = {
    OnDescFailed, OnDescReady, OnDescReady2,
};

// |data| is null for an info object given up on (see QueryPreferred).
void OnInfoDone(void* data, wp_image_description_info_v1* info) {
  if (data) static_cast<Description*>(data)->info_done = true;
  wl_proxy_destroy(reinterpret_cast<wl_proxy*>(info));
}
void OnInfoIcc(void*, wp_image_description_info_v1*, int32_t fd, uint32_t) {
  close(fd);
}
void OnInfoPrimaries(void*, wp_image_description_info_v1*, int32_t, int32_t,
                     int32_t, int32_t, int32_t, int32_t, int32_t, int32_t) {}
void OnInfoPrimariesNamed(void*, wp_image_description_info_v1*, uint32_t) {}
void OnInfoTfPower(void*, wp_image_description_info_v1*, uint32_t) {}
void OnInfoTfNamed(void* data, wp_image_description_info_v1*, uint32_t tf) {
  if (data) static_cast<Description*>(data)->tf = tf;
}
void OnInfoLuminances(void* data, wp_image_description_info_v1*,
                      uint32_t min_lum, uint32_t max_lum,
                      uint32_t reference_lum) {
  auto* d = static_cast<Description*>(data);
  if (!d) return;
  d->has_luminances = true;
  d->min_lum = min_lum / 10000.0;
  d->max_lum = max_lum;
  d->reference_lum = reference_lum;
}
void OnInfoTargetPrimaries(void*, wp_image_description_info_v1*, int32_t,
                           int32_t, int32_t, int32_t, int32_t, int32_t,
                           int32_t, int32_t) {}
void OnInfoTargetLuminance(void* data, wp_image_description_info_v1*,
                           uint32_t min_lum, uint32_t max_lum) {
  auto* d = static_cast<Description*>(data);
  if (!d) return;
  d->has_target = true;
  d->target_min = min_lum / 10000.0;
  d->target_max = max_lum;
}
void OnInfoMaxCll(void*, wp_image_description_info_v1*, uint32_t) {}
void OnInfoMaxFall(void*, wp_image_description_info_v1*, uint32_t) {}
const wp_image_description_info_v1_listener kInfoListener = {
    OnInfoDone,         OnInfoIcc,          OnInfoPrimaries,
    OnInfoPrimariesNamed, OnInfoTfPower,    OnInfoTfNamed,
    OnInfoLuminances,   OnInfoTargetPrimaries, OnInfoTargetLuminance,
    OnInfoMaxCll,       OnInfoMaxFall,
};

// The colour space the compositor prefers for the app window right now,
// which follows the screen it's on. False if it can't be had.
bool QueryPreferred(State* s, Description* out) {
  wl_surface* surface = WindowSurface(s);
  if (!s->color_manager || !surface) return false;
  auto* feedback =
      wp_color_manager_v1_get_surface_feedback(s->color_manager, surface);
  auto* description =
      wp_color_management_surface_feedback_v1_get_preferred(feedback);
  wp_image_description_v1_add_listener(description, &kDescriptionListener, out);
  for (int i = 0; i < 10 && out->state == 0; ++i) Roundtrip(s);
  if (out->state == 1) {
    auto* info = wp_image_description_v1_get_information(description);
    wp_image_description_info_v1_add_listener(info, &kInfoListener, out);
    for (int i = 0; i < 10 && !out->info_done; ++i) Roundtrip(s);
    // The proxy is freed on "done" (a destructor event); if that never came,
    // its late events must not reach |out|, which is on the stack.
    if (!out->info_done) wl_proxy_set_user_data(reinterpret_cast<wl_proxy*>(info), nullptr);
  }
  wp_image_description_v1_destroy(description);
  wp_color_management_surface_feedback_v1_destroy(feedback);
  return out->state == 1 && out->info_done;
}

FlValue* DisplayInfo(State* s) {
  FlValue* info = fl_value_new_map();
  const bool usable = s->display && HdrUsable(s);
  fl_value_set_string_take(info, "backend", fl_value_new_string("wayland"));
  if (!usable) {
    // X11, or a compositor without HDR support.
    fl_value_set_string_take(info, "isHdr", fl_value_new_bool(false));
    fl_value_set_string_take(info, "hdrSupported", fl_value_new_bool(false));
    return info;
  }
  Description d;
  bool is_hdr = false;
  double peak = 0;
  if (QueryPreferred(s, &d)) {
    peak = d.has_target ? d.target_max : 0;
    const bool hdr_tf =
        d.tf == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ ||
        d.tf == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG;
    if (peak <= 0 && d.has_luminances && !hdr_tf) peak = d.max_lum;
    // HDR mode: a PQ / HLG screen (GNOME, Hyprland), or one whose headroom
    // reaches well above SDR white (KDE's gamma 2.2 with extended range).
    is_hdr = hdr_tf || (d.has_luminances && d.reference_lum > 0 &&
                        peak > d.reference_lum * 1.5);
    // An SDR screen's peak means nothing for HDR video.
    if (is_hdr && peak > 0) {
      fl_value_set_string_take(info, "maxLuminance", fl_value_new_float(peak));
    }
    if (d.has_luminances) {
      fl_value_set_string_take(info, "referenceLuminance",
                               fl_value_new_float(d.reference_lum));
    }
    if (d.has_target) {
      fl_value_set_string_take(info, "minLuminance",
                               fl_value_new_float(d.target_min));
    }
  }
  const char* force = getenv("NIVIO_FORCE_HDR");
  if (force && strcmp(force, "1") == 0) is_hdr = true;
  fl_value_set_string_take(info, "isHdr", fl_value_new_bool(is_hdr));
  return info;
}

void NotifyDart(State* s, const char* method) {
  if (s->channel) {
    fl_method_channel_invoke_method(s->channel, method, nullptr, nullptr,
                                    nullptr, nullptr);
  }
}

void OnPreferredChanged(void* data,
                        wp_color_management_surface_feedback_v1*,
                        uint32_t) {
  NotifyDart(static_cast<State*>(data), "displayChanged");
}
void OnPreferredChanged2(void* data,
                         wp_color_management_surface_feedback_v1*,
                         uint32_t,
                         uint32_t) {
  NotifyDart(static_cast<State*>(data), "displayChanged");
}
const wp_color_management_surface_feedback_v1_listener kFeedbackListener = {
    OnPreferredChanged, OnPreferredChanged2,
};

void DropFeedback(State* s) {
  if (s->feedback) wp_color_management_surface_feedback_v1_destroy(s->feedback);
  s->feedback = nullptr;
  s->feedback_surface = nullptr;
}

// Keeps a feedback object on the window's current surface.
void WatchWindowSurface(State* s) {
  if (!s->color_manager) return;
  wl_surface* surface = WindowSurface(s);
  if (surface == s->feedback_surface) return;
  DropFeedback(s);
  if (!surface) return;
  s->feedback =
      wp_color_manager_v1_get_surface_feedback(s->color_manager, surface);
  s->feedback_surface = surface;
  wp_color_management_surface_feedback_v1_add_listener(
      s->feedback, &kFeedbackListener, s);
}

gboolean DispatchQueue(gpointer data) {
  auto* s = static_cast<State*>(data);
  // GDK reads the socket for every queue; this runs what landed on ours.
  wl_display_dispatch_queue_pending(s->display, s->queue);
  WatchWindowSurface(s);
  return G_SOURCE_CONTINUE;
}

// --- Video surfaces -----------------------------------------------------------

void SetEmptyInputRegion(State* s, wl_surface* surface) {
  // Input goes to the app window above; these surfaces never take any.
  wl_region* region = wl_compositor_create_region(s->compositor);
  wl_surface_set_input_region(surface, region);
  wl_region_destroy(region);
}

wl_buffer* BlackPixel(State* s) {
  int fd = memfd_create("nivio-hdr-backdrop", MFD_CLOEXEC);
  if (fd < 0) return nullptr;
  wl_buffer* buffer = nullptr;
  if (ftruncate(fd, 4) == 0) {
    void* data = mmap(nullptr, 4, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data != MAP_FAILED) {
      *static_cast<uint32_t*>(data) = 0xFF000000;
      munmap(data, 4);
      wl_shm_pool* pool = wl_shm_create_pool(s->shm, fd, 4);
      buffer = wl_shm_pool_create_buffer(pool, 0, 1, 1, 4,
                                         WL_SHM_FORMAT_XRGB8888);
      wl_shm_pool_destroy(pool);
    }
  }
  close(fd);
  return buffer;
}

// HDR10: PQ transfer, BT.2020 primaries. |peak| is the screen's peak
// brightness (what mpv tone-maps to), sent as the content's max light level.
bool TagHdr10(State* s, double peak) {
  auto* creator =
      wp_color_manager_v1_create_parametric_creator(s->color_manager);
  wp_image_description_creator_params_v1_set_tf_named(
      creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
  wp_image_description_creator_params_v1_set_primaries_named(
      creator, WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
  if (peak >= 1 && peak <= 10000) {
    wp_image_description_creator_params_v1_set_max_cll(
        creator, static_cast<uint32_t>(std::lround(peak)));
  }
  auto* description =
      wp_image_description_creator_params_v1_create(creator);  // frees creator
  Description d;
  wp_image_description_v1_add_listener(description, &kDescriptionListener, &d);
  for (int i = 0; i < 10 && d.state == 0; ++i) Roundtrip(s);
  if (d.state == 1) {
    wp_color_management_surface_v1_set_image_description(
        s->video_cm, description,
        WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
  }
  wp_image_description_v1_destroy(description);
  return d.state == 1;
}

void SetOpaqueRegion(State* s) {
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(s->window));
  if (window && s->transparent) gdk_window_set_opaque_region(window, nullptr);
}

// See-through app window: alpha 0 pixels show the video below.
void SetTransparent(State* s, bool transparent) {
  if (transparent == s->transparent) return;
  s->transparent = transparent;
  GtkStyleContext* style = gtk_widget_get_style_context(GTK_WIDGET(s->window));
  if (!s->css) {
    // Above window_manager's "window { background-color }" (application
    // priority).
    s->css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(
        s->css,
        "window.nivio-hdr-video { background-color: transparent; "
        "background-image: none; }",
        -1, nullptr);
    gtk_style_context_add_provider(style, GTK_STYLE_PROVIDER(s->css),
                                   GTK_STYLE_PROVIDER_PRIORITY_USER);
  }
  GdkRGBA background = {0, 0, 0, transparent ? 0.0 : 1.0};
  fl_view_set_background_color(s->view, &background);
  if (transparent) {
    gtk_style_context_add_class(style, "nivio-hdr-video");
  } else {
    gtk_style_context_remove_class(style, "nivio-hdr-video");
  }
  // GTK marks an opaque window's surface as opaque, and the compositor then
  // skips whatever is below it (the video).
  SetOpaqueRegion(s);
  gtk_widget_queue_resize(GTK_WIDGET(s->window));
  gtk_widget_queue_draw(GTK_WIDGET(s->window));
}

// Places the backdrop under the Flutter view and mpv's surface at the video
// rect. Subsurface positions apply with the window's next commit, so the
// window is redrawn too.
void UpdatePositions(State* s) {
  if (!s->video) return;
  int view_x = 0, view_y = 0;
  if (!gtk_widget_translate_coordinates(GTK_WIDGET(s->view),
                                        GTK_WIDGET(s->window), 0, 0, &view_x,
                                        &view_y)) {
    return;
  }
  const int scale = std::max(1, gtk_widget_get_scale_factor(GTK_WIDGET(s->view)));
  const int view_w = std::max(1, gtk_widget_get_allocated_width(GTK_WIDGET(s->view)));
  const int view_h = std::max(1, gtk_widget_get_allocated_height(GTK_WIDGET(s->view)));
  wl_subsurface_set_position(s->backdrop_sub, view_x, view_y);
  wp_viewport_set_destination(s->backdrop_viewport, view_w, view_h);
  wl_surface_commit(s->backdrop);

  if (s->rect_w > 0 && s->rect_h > 0) {
    const int x = static_cast<int>(std::lround(s->rect_x / double(scale)));
    const int y = static_cast<int>(std::lround(s->rect_y / double(scale)));
    wl_subsurface_set_position(s->video_sub, view_x + x, view_y + y);
    {
      std::lock_guard<std::mutex> lock(s->mutex);
      s->buffer_w = s->rect_w;
      s->buffer_h = s->rect_h;
      s->dest_w = std::max(1, int(std::lround(s->rect_w / double(scale))));
      s->dest_h = std::max(1, int(std::lround(s->rect_h / double(scale))));
      s->size_dirty = true;
      s->redraw = true;
    }
    s->cv.notify_one();
  }
  gtk_widget_queue_draw(GTK_WIDGET(s->window));
}

// --- Render thread ------------------------------------------------------------

EGLConfig TenBitConfig(EGLDisplay display, EGLint renderable) {
  const EGLint attributes[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, renderable,
      EGL_RED_SIZE,     10,             EGL_GREEN_SIZE,      10,
      EGL_BLUE_SIZE,    10,             EGL_NONE,
  };
  EGLint count = 0;
  if (!eglChooseConfig(display, attributes, nullptr, 0, &count) || count <= 0) {
    return nullptr;
  }
  std::vector<EGLConfig> configs(count);
  eglChooseConfig(display, attributes, configs.data(), count, &count);
  EGLConfig with_alpha = nullptr;
  for (EGLint i = 0; i < count; ++i) {
    EGLint r = 0, g = 0, b = 0, a = 0;
    eglGetConfigAttrib(display, configs[i], EGL_RED_SIZE, &r);
    eglGetConfigAttrib(display, configs[i], EGL_GREEN_SIZE, &g);
    eglGetConfigAttrib(display, configs[i], EGL_BLUE_SIZE, &b);
    eglGetConfigAttrib(display, configs[i], EGL_ALPHA_SIZE, &a);
    if (r != 10 || g != 10 || b != 10) continue;  // not 16-bit float
    if (a == 0) return configs[i];                 // XRGB2101010
    if (a == 2 && !with_alpha) with_alpha = configs[i];
  }
  return with_alpha;
}

void OnMpvUpdate(void* data) {
  auto* s = static_cast<State*>(data);
  {
    std::lock_guard<std::mutex> lock(s->mutex);
    s->update = true;
  }
  s->cv.notify_one();
}

void RenderThread(State* s, std::promise<bool> started) {
  bool ok = false;
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface surface = EGL_NO_SURFACE;
  wl_egl_window* egl_window = nullptr;
  mpv_render_context* render = nullptr;
  int width = 0, height = 0;
  {
    std::lock_guard<std::mutex> lock(s->mutex);
    width = std::max(1, s->buffer_w);
    height = std::max(1, s->buffer_h);
  }

  [&] {
    // The same EGLDisplay GDK uses; never eglTerminate it.
    display = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, s->display,
                                    nullptr);
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr)) {
      s->error = "EGL is not available";
      return;
    }
    EGLConfig config = nullptr;
    const EGLint* context_attributes = nullptr;
    static const EGLint kEs3[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE};
    if (eglBindAPI(EGL_OPENGL_API)) {
      config = TenBitConfig(display, EGL_OPENGL_BIT);
    }
    if (!config && eglBindAPI(EGL_OPENGL_ES_API)) {
      config = TenBitConfig(display, EGL_OPENGL_ES3_BIT);
      context_attributes = kEs3;
    }
    if (!config) {
      s->error = "No 10-bit EGL config";
      return;
    }
    context = eglCreateContext(display, config, EGL_NO_CONTEXT,
                               context_attributes);
    if (context == EGL_NO_CONTEXT) {
      s->error = "Could not create an EGL context";
      return;
    }
    egl_window = wl_egl_window_create(s->video, width, height);
    surface = eglCreatePlatformWindowSurface(display, config, egl_window,
                                             nullptr);
    if (surface == EGL_NO_SURFACE ||
        !eglMakeCurrent(display, surface, surface, context)) {
      s->error = "Could not create the EGL surface";
      return;
    }
    // mpv paces frames itself (and must not block on a hidden surface).
    eglSwapInterval(display, 0);

    mpv_opengl_init_params gl_init{
        [](void*, const char* name) {
          return reinterpret_cast<void*>(eglGetProcAddress(name));
        },
        nullptr,
    };
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init},
        // For VA-API interop.
        {MPV_RENDER_PARAM_WL_DISPLAY, s->display},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int result = mpv_render_context_create(&render, s->mpv, params);
    if (result < 0) {
      s->error = std::string("mpv render context: ") + mpv_error_string(result);
      render = nullptr;
      return;
    }
    mpv_render_context_set_update_callback(render, OnMpvUpdate, s);
    ok = true;
  }();
  started.set_value(ok);

  if (ok) {
    std::unique_lock<std::mutex> lock(s->mutex);
    while (true) {
      s->cv.wait(lock, [s] { return s->stop || s->update || s->redraw; });
      if (s->stop) break;
      bool redraw = s->redraw;
      const bool resize = s->size_dirty;
      s->update = s->redraw = s->size_dirty = false;
      const int buffer_w = s->buffer_w, buffer_h = s->buffer_h;
      const int dest_w = s->dest_w, dest_h = s->dest_h;
      lock.unlock();

      const uint64_t flags = mpv_render_context_update(render);
      if (resize && buffer_w > 0 && buffer_h > 0) {
        wl_egl_window_resize(egl_window, buffer_w, buffer_h, 0, 0);
        // Logical size; the buffer is in physical pixels.
        wp_viewport_set_destination(s->video_viewport, dest_w, dest_h);
        redraw = true;
      }
      if (((flags & MPV_RENDER_UPDATE_FRAME) || redraw) && buffer_w > 0 &&
          buffer_h > 0) {
        mpv_opengl_fbo fbo{0, buffer_w, buffer_h, 0};
        int flip_y = 1;
        int depth = 10;
        mpv_render_param render_params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
            {MPV_RENDER_PARAM_DEPTH, &depth},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(render, render_params);
        eglSwapBuffers(display, surface);
        mpv_render_context_report_swap(render);
        s->frames++;
      }
      lock.lock();
    }
  }

  // mpv's vo is switched away before detach, so this doesn't wait long.
  if (render) mpv_render_context_free(render);
  if (display != EGL_NO_DISPLAY) {
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
    if (context != EGL_NO_CONTEXT) eglDestroyContext(display, context);
  }
  if (egl_window) wl_egl_window_destroy(egl_window);
  eglReleaseThread();
}

void Teardown(State* s) {
  if (s->thread.joinable()) {
    {
      std::lock_guard<std::mutex> lock(s->mutex);
      s->stop = true;
    }
    s->cv.notify_one();
    s->thread.join();
    s->stop = s->update = s->redraw = s->size_dirty = false;
  }
  if (s->video_cm) wp_color_management_surface_v1_destroy(s->video_cm);
  if (s->video_viewport) wp_viewport_destroy(s->video_viewport);
  if (s->video_sub) wl_subsurface_destroy(s->video_sub);
  if (s->video) wl_surface_destroy(s->video);
  if (s->backdrop_viewport) wp_viewport_destroy(s->backdrop_viewport);
  if (s->backdrop_sub) wl_subsurface_destroy(s->backdrop_sub);
  if (s->backdrop) wl_surface_destroy(s->backdrop);
  if (s->backdrop_buffer) wl_buffer_destroy(s->backdrop_buffer);
  s->video_cm = nullptr;
  s->video_viewport = nullptr;
  s->video_sub = nullptr;
  s->video = nullptr;
  s->backdrop_viewport = nullptr;
  s->backdrop_sub = nullptr;
  s->backdrop = nullptr;
  s->backdrop_buffer = nullptr;
  s->mpv = nullptr;
  s->attached = false;
  if (s->display) wl_display_flush(s->display);
  SetTransparent(s, false);
}

// Creates the surfaces and the render thread. On failure everything is torn
// down again and |s->error| says why.
bool Attach(State* s, mpv_handle* mpv, double peak) {
  s->error.clear();
  if (!s->display || !HdrUsable(s)) {
    s->error = "This desktop has no HDR support (needs Wayland colour management)";
    return false;
  }
  wl_surface* parent = WindowSurface(s);
  if (!parent) {
    s->error = "The app window isn't shown";
    return false;
  }
  s->mpv = mpv;
  s->backdrop_buffer = BlackPixel(s);
  if (!s->backdrop_buffer) {
    s->error = "Could not create the backdrop";
    return false;
  }
  s->backdrop = wl_compositor_create_surface(s->compositor);
  s->backdrop_sub =
      wl_subcompositor_get_subsurface(s->subcompositor, s->backdrop, parent);
  s->backdrop_viewport = wp_viewporter_get_viewport(s->viewporter, s->backdrop);
  SetEmptyInputRegion(s, s->backdrop);
  wl_surface_attach(s->backdrop, s->backdrop_buffer, 0, 0);
  wl_surface_damage(s->backdrop, 0, 0, INT32_MAX, INT32_MAX);

  s->video = wl_compositor_create_surface(s->compositor);
  s->video_sub =
      wl_subcompositor_get_subsurface(s->subcompositor, s->video, parent);
  s->video_viewport = wp_viewporter_get_viewport(s->viewporter, s->video);
  SetEmptyInputRegion(s, s->video);
  // Frames show as soon as they're committed, not with the window's commits.
  wl_subsurface_set_desync(s->video_sub);
  // Stacking, bottom to top: backdrop, video, app window.
  wl_subsurface_place_below(s->video_sub, parent);
  wl_subsurface_place_below(s->backdrop_sub, s->video);

  s->video_cm = wp_color_manager_v1_get_surface(s->color_manager, s->video);
  if (!TagHdr10(s, peak)) {
    s->error = "The compositor rejected the HDR10 colour space";
    Teardown(s);
    return false;
  }
  UpdatePositions(s);

  std::promise<bool> started;
  auto result = started.get_future();
  s->thread = std::thread(RenderThread, s, std::move(started));
  if (result.wait_for(std::chrono::seconds(5)) != std::future_status::ready ||
      !result.get()) {
    if (s->error.empty()) s->error = "The renderer didn't start";
    Teardown(s);
    return false;
  }
  s->attached = true;
  SetTransparent(s, true);
  return true;
}

int64_t ArgInt(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return 0;
  FlValue* value = fl_value_lookup_string(args, key);
  if (!value) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return fl_value_get_int(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int64_t>(fl_value_get_float(value));
  }
  return 0;
}

double ArgDouble(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return 0;
  FlValue* value = fl_value_lookup_string(args, key);
  if (!value) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return fl_value_get_int(value);
  return 0;
}

void ReadRect(State* s, FlValue* args) {
  s->rect_x = static_cast<int>(ArgInt(args, "x"));
  s->rect_y = static_cast<int>(ArgInt(args, "y"));
  s->rect_w = static_cast<int>(ArgInt(args, "width"));
  s->rect_h = static_cast<int>(ArgInt(args, "height"));
}

void OnUnmap(GtkWidget*, gpointer data) {
  auto* s = static_cast<State*>(data);
  // GDK drops the window's wl_surface when it's hidden: the subsurfaces lose
  // their parent, so the Dart side goes back to the normal video output.
  DropFeedback(s);
  if (s->attached) NotifyDart(s, "surfaceLost");
}

void OnWindowAllocate(GtkWidget*, GdkRectangle*, gpointer data) {
  SetOpaqueRegion(static_cast<State*>(data));
}

void OnViewAllocate(GtkWidget*, GdkRectangle*, gpointer data) {
  auto* s = static_cast<State*>(data);
  // Fullscreen, maximize, resize: the view may have moved in the window.
  if (s->attached) UpdatePositions(s);
}

}  // namespace
#endif  // NIVIO_LINUX_HDR

static void HandleMethodCall(FlMethodChannel*,
                             FlMethodCall* call,
                             gpointer user_data) {
  auto* s = static_cast<HdrVideoHost::State*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
#ifdef NIVIO_LINUX_HDR
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(method, "displayInfo") == 0) {
    g_autoptr(FlValue) info = DisplayInfo(s);
    fl_method_call_respond_success(call, info, nullptr);
  } else if (strcmp(method, "attach") == 0) {
    // Dart has released media_kit's render context and set vo=null first.
    if (s->attached) Teardown(s);
    ReadRect(s, args);
    auto* mpv = reinterpret_cast<mpv_handle*>(ArgInt(args, "handle"));
    if (!mpv || !Attach(s, mpv, ArgDouble(args, "peak"))) {
      fl_method_call_respond_error(call, "attach_failed",
                                   mpv ? s->error.c_str() : "No mpv handle",
                                   nullptr, nullptr);
      return;
    }
    g_autoptr(FlValue) ok = fl_value_new_bool(true);
    fl_method_call_respond_success(call, ok, nullptr);
  } else if (strcmp(method, "setRect") == 0) {
    ReadRect(s, args);
    if (s->attached) UpdatePositions(s);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "status") == 0) {
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string_take(status, "attached", fl_value_new_bool(s->attached));
    fl_value_set_string_take(status, "frames", fl_value_new_int(s->frames.load()));
    fl_method_call_respond_success(call, status, nullptr);
  } else if (strcmp(method, "detach") == 0) {
    // mpv must have left the render context (vo switched) before this.
    Teardown(s);
    s->frames = 0;
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
#else
  if (strcmp(method, "displayInfo") == 0) {
    // Built without Wayland HDR support (see runner/CMakeLists.txt).
    g_autoptr(FlValue) info = fl_value_new_map();
    fl_value_set_string_take(info, "isHdr", fl_value_new_bool(false));
    fl_value_set_string_take(info, "hdrSupported", fl_value_new_bool(false));
    fl_method_call_respond_success(call, info, nullptr);
  } else if (strcmp(method, "attach") == 0) {
    fl_method_call_respond_error(call, "attach_failed",
                                 "Built without HDR support", nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
  (void)s;
#endif
}

HdrVideoHost::HdrVideoHost(GtkWindow* window, FlView* view)
    : state_(std::make_unique<State>()) {
  State* s = state_.get();
  s->window = window;
  s->view = view;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  s->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.nivio/hdr_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(s->channel, HandleMethodCall, s,
                                            nullptr);

#ifdef NIVIO_LINUX_HDR
  GdkDisplay* gdk_display = gtk_widget_get_display(GTK_WIDGET(window));
  if (!GDK_IS_WAYLAND_DISPLAY(gdk_display)) return;  // X11: no HDR
  s->display = gdk_wayland_display_get_wl_display(gdk_display);
  s->queue = wl_display_create_queue(s->display);
  auto* wrapper =
      static_cast<wl_display*>(wl_proxy_create_wrapper(s->display));
  wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(wrapper), s->queue);
  s->registry = wl_display_get_registry(wrapper);
  wl_proxy_wrapper_destroy(wrapper);
  wl_registry_add_listener(s->registry, &kRegistryListener, s);
  Roundtrip(s);  // globals
  Roundtrip(s);  // colour management's supported features
  g_message("HDR video: Wayland colour management %s",
            HdrUsable(s) ? "available" : "not available (no true HDR)");

  s->dispatch_source = g_timeout_add(250, DispatchQueue, s);
  s->unmap_handler =
      g_signal_connect(window, "unmap", G_CALLBACK(OnUnmap), s);
  s->window_allocate_handler = g_signal_connect_after(
      window, "size-allocate", G_CALLBACK(OnWindowAllocate), s);
  s->view_allocate_handler = g_signal_connect_after(
      view, "size-allocate", G_CALLBACK(OnViewAllocate), s);
#endif
}

HdrVideoHost::~HdrVideoHost() {
  State* s = state_.get();
  if (s->channel) {
    fl_method_channel_set_method_call_handler(s->channel, nullptr, nullptr,
                                              nullptr);
  }
#ifdef NIVIO_LINUX_HDR
  if (s->display) {
    Teardown(s);
    if (s->dispatch_source) g_source_remove(s->dispatch_source);
    if (s->unmap_handler) g_signal_handler_disconnect(s->window, s->unmap_handler);
    if (s->window_allocate_handler) {
      g_signal_handler_disconnect(s->window, s->window_allocate_handler);
    }
    if (s->view_allocate_handler) {
      g_signal_handler_disconnect(s->view, s->view_allocate_handler);
    }
    DropFeedback(s);
    if (s->color_manager) wp_color_manager_v1_destroy(s->color_manager);
    if (s->viewporter) wp_viewporter_destroy(s->viewporter);
    if (s->shm) wl_shm_destroy(s->shm);
    if (s->subcompositor) wl_subcompositor_destroy(s->subcompositor);
    if (s->compositor) wl_compositor_destroy(s->compositor);
    if (s->registry) wl_registry_destroy(s->registry);
    wl_display_flush(s->display);
    wl_event_queue_destroy(s->queue);
  }
  if (s->css) g_object_unref(s->css);
#endif
  g_clear_object(&s->channel);
}
