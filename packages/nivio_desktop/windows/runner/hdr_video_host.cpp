#include "hdr_video_host.h"

#include <dxgi1_6.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

// DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2 (Windows 11 24H2+), declared here so
// older SDKs build too. Bits of |flags|: 0 advancedColorSupported,
// 1 advancedColorActive, 3 advancedColorLimitedByPolicy,
// 4 highDynamicRangeSupported, 5 highDynamicRangeUserEnabled,
// 6 wideColorSupported, 7 wideColorUserEnabled.
constexpr UINT32 kGetAdvancedColorInfo2 = 15;
struct AdvancedColorInfo2 {
  DISPLAYCONFIG_DEVICE_INFO_HEADER header;
  UINT32 flags;
  DISPLAYCONFIG_COLOR_ENCODING color_encoding;
  UINT32 bits_per_color_channel;
  UINT32 active_color_mode;
};

// Whether the monitor showing GDI device |gdi_name| (e.g. \\.\DISPLAY1) can
// do HDR, whether or not Windows HDR is switched on for it. False if Windows
// doesn't say.
bool HdrSupported(const wchar_t* gdi_name, bool* supported) {
  UINT32 path_count = 0, mode_count = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &path_count,
                                  &mode_count) != ERROR_SUCCESS) {
    return false;
  }
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(path_count);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(mode_count);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths.data(),
                         &mode_count, modes.data(),
                         nullptr) != ERROR_SUCCESS) {
    return false;
  }
  for (UINT32 i = 0; i < path_count; ++i) {
    DISPLAYCONFIG_SOURCE_DEVICE_NAME source{};
    source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
    source.header.size = sizeof(source);
    source.header.adapterId = paths[i].sourceInfo.adapterId;
    source.header.id = paths[i].sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS ||
        wcscmp(source.viewGdiDeviceName, gdi_name) != 0) {
      continue;
    }
    // Windows 11 24H2+: HDR support on its own.
    AdvancedColorInfo2 info2{};
    info2.header.type =
        static_cast<DISPLAYCONFIG_DEVICE_INFO_TYPE>(kGetAdvancedColorInfo2);
    info2.header.size = sizeof(info2);
    info2.header.adapterId = paths[i].targetInfo.adapterId;
    info2.header.id = paths[i].targetInfo.id;
    if (DisplayConfigGetDeviceInfo(&info2.header) == ERROR_SUCCESS) {
      *supported = ((info2.flags >> 4) & 1u) != 0;
      return true;
    }
    // Older Windows: "advanced colour" (HDR, or wide colour gamut).
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO info{};
    info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
    info.header.size = sizeof(info);
    info.header.adapterId = paths[i].targetInfo.adapterId;
    info.header.id = paths[i].targetInfo.id;
    if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
      *supported = info.advancedColorSupported != 0;
      return true;
    }
    return false;
  }
  return false;
}

constexpr wchar_t kVideoWindowClass[] = L"NIVIO_HDR_VIDEO_WINDOW";

// Undocumented SetWindowCompositionAttribute (what window_manager's
// setBackgroundColor uses for its transparent / coloured backgrounds).
enum AccentState {
  kAccentEnableGradient = 1,
  kAccentEnableTransparentGradient = 2,
};
struct AccentPolicy {
  int accent_state;
  int accent_flags;
  DWORD gradient_color;  // ABGR
  int animation_id;
};
struct WindowCompositionAttribData {
  int attribute;  // 19 = WCA_ACCENT_POLICY
  void* data;
  SIZE_T size;
};
using SetWindowCompositionAttributeFn =
    BOOL(WINAPI*)(HWND, WindowCompositionAttribData*);

void SetAccent(HWND hwnd, int state, DWORD color) {
  HMODULE user32 = GetModuleHandle(L"user32.dll");
  if (!user32) return;
  auto fn = reinterpret_cast<SetWindowCompositionAttributeFn>(
      GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (!fn) return;
  AccentPolicy policy{state, 2, color, 0};
  WindowCompositionAttribData data{19, &policy, sizeof(policy)};
  fn(hwnd, &data);
}

std::string Utf8(const wchar_t* text) {
  if (!text || !*text) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr,
                                 nullptr);
  if (size <= 1) return {};
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), size, nullptr,
                      nullptr);
  return out;
}

int64_t ArgInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (auto v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second)) return *v;
  if (auto v = std::get_if<double>(&it->second)) return static_cast<int64_t>(*v);
  return 0;
}

RECT ArgRect(const flutter::EncodableValue* args) {
  RECT rect{};
  if (auto map = std::get_if<flutter::EncodableMap>(args)) {
    rect.left = static_cast<LONG>(ArgInt(*map, "x"));
    rect.top = static_cast<LONG>(ArgInt(*map, "y"));
    rect.right = rect.left + static_cast<LONG>(ArgInt(*map, "width"));
    rect.bottom = rect.top + static_cast<LONG>(ArgInt(*map, "height"));
  }
  return rect;
}

LRESULT CALLBACK VideoWndProc(HWND hwnd, UINT message, WPARAM wparam,
                              LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE: {
      // Never take focus; hand it to the app window instead.
      auto app = reinterpret_cast<HWND>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
      if (app) SetForegroundWindow(app);
      return MA_NOACTIVATEANDEAT;
    }
    case WM_ERASEBKGND: {
      RECT rect;
      GetClientRect(hwnd, &rect);
      FillRect(reinterpret_cast<HDC>(wparam), &rect,
               static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
      return 1;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace

HdrVideoHost::HdrVideoHost(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  monitor_ = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.nivio/hdr_window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

HdrVideoHost::~HdrVideoHost() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  DestroyVideoWindow();
}

void HdrVideoHost::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "displayInfo") {
    result->Success(flutter::EncodableValue(DisplayInfo()));
  } else if (method == "attach") {
    // Shows the video window under |rect| and returns its HWND for mpv's
    // "wid" option.
    rect_ = ArgRect(call.arguments());
    if (!EnsureVideoWindow()) {
      result->Error("create_failed", "Could not create the HDR video window");
      return;
    }
    SetTransparent(true);
    UpdateVideoWindow();
    result->Success(flutter::EncodableValue(
        static_cast<int64_t>(reinterpret_cast<intptr_t>(video_child_))));
  } else if (method == "setRect") {
    rect_ = ArgRect(call.arguments());
    UpdateVideoWindow();
    result->Success();
  } else if (method == "detach") {
    // mpv must have left the window (vo switched) before this is called.
    SetTransparent(false);
    DestroyVideoWindow();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

flutter::EncodableMap HdrVideoHost::DisplayInfo() {
  flutter::EncodableMap info;
  info[flutter::EncodableValue("isHdr")] = flutter::EncodableValue(false);
  HMONITOR monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);

  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return info;
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT a = 0; factory->EnumAdapters1(a, &adapter) != DXGI_ERROR_NOT_FOUND;
       ++a) {
    ComPtr<IDXGIOutput> output;
    for (UINT o = 0; adapter->EnumOutputs(o, &output) != DXGI_ERROR_NOT_FOUND;
         ++o) {
      DXGI_OUTPUT_DESC desc{};
      if (FAILED(output->GetDesc(&desc)) || desc.Monitor != monitor) continue;

      DXGI_ADAPTER_DESC1 adapter_desc{};
      if (SUCCEEDED(adapter->GetDesc1(&adapter_desc))) {
        // For mpv's d3d11-adapter (matched by name prefix): render on the
        // GPU that drives this monitor (laptops with two GPUs).
        info[flutter::EncodableValue("adapter")] =
            flutter::EncodableValue(Utf8(adapter_desc.Description));
      }
      info[flutter::EncodableValue("monitor")] =
          flutter::EncodableValue(Utf8(desc.DeviceName));
      bool supported = false;
      if (HdrSupported(desc.DeviceName, &supported)) {
        // Can the screen do HDR at all (whether or not it's switched on)?
        info[flutter::EncodableValue("hdrSupported")] =
            flutter::EncodableValue(supported);
      }

      ComPtr<IDXGIOutput6> output6;
      DXGI_OUTPUT_DESC1 desc1{};
      if (SUCCEEDED(output.As(&output6)) &&
          SUCCEEDED(output6->GetDesc1(&desc1))) {
        info[flutter::EncodableValue("isHdr")] = flutter::EncodableValue(
            desc1.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020);
        info[flutter::EncodableValue("bitsPerColor")] =
            flutter::EncodableValue(static_cast<int32_t>(desc1.BitsPerColor));
        info[flutter::EncodableValue("maxLuminance")] =
            flutter::EncodableValue(static_cast<double>(desc1.MaxLuminance));
        info[flutter::EncodableValue("minLuminance")] =
            flutter::EncodableValue(static_cast<double>(desc1.MinLuminance));
        info[flutter::EncodableValue("maxFullFrameLuminance")] =
            flutter::EncodableValue(
                static_cast<double>(desc1.MaxFullFrameLuminance));
      }
      return info;
    }
  }
  return info;
}

bool HdrVideoHost::EnsureVideoWindow() {
  if (video_) return true;
  static bool registered = false;
  if (!registered) {
    WNDCLASS wc{};
    wc.lpfnWndProc = VideoWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = kVideoWindowClass;
    registered = RegisterClass(&wc) != 0;
    if (!registered) return false;
  }
  // Not owned by the app window: owned windows always stay above their
  // owner, and this one has to stay below it. A tool window, so it has no
  // taskbar button or Alt+Tab entry.
  video_ = CreateWindowEx(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                          kVideoWindowClass, L"Nivio HDR video",
                          WS_POPUP | WS_CLIPCHILDREN, 0, 0, 0, 0, nullptr,
                          nullptr, GetModuleHandle(nullptr), nullptr);
  if (!video_) return false;
  video_child_ = CreateWindowEx(0, kVideoWindowClass, L"",
                                WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS |
                                    WS_CLIPCHILDREN,
                                0, 0, 0, 0, video_, nullptr,
                                GetModuleHandle(nullptr), nullptr);
  if (!video_child_) {
    DestroyVideoWindow();
    return false;
  }
  SetWindowLongPtr(video_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_));
  SetWindowLongPtr(video_child_, GWLP_USERDATA,
                   reinterpret_cast<LONG_PTR>(window_));
  return true;
}

void HdrVideoHost::DestroyVideoWindow() {
  if (!video_) return;
  DestroyWindow(video_);  // Also destroys video_child_.
  video_ = nullptr;
  video_child_ = nullptr;
}

void HdrVideoHost::UpdateVideoWindow() {
  if (!video_) return;
  RECT client{};
  GetClientRect(window_, &client);
  const bool hidden = !IsWindowVisible(window_) || IsIconic(window_) ||
                      client.right <= 0 || client.bottom <= 0;
  if (hidden) {
    ShowWindow(video_, SW_HIDE);
    return;
  }
  POINT origin{0, 0};
  ClientToScreen(window_, &origin);
  // Insert after the app window: directly below it in z-order.
  SetWindowPos(video_, window_, origin.x, origin.y, client.right,
               client.bottom,
               SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
  const LONG width = rect_.right - rect_.left;
  const LONG height = rect_.bottom - rect_.top;
  if (width > 0 && height > 0) {
    SetWindowPos(video_child_, nullptr, rect_.left, rect_.top, width, height,
                 SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);
  } else {
    ShowWindow(video_child_, SW_HIDE);
  }
}

void HdrVideoHost::SetTransparent(bool transparent) {
  if (transparent == transparent_) return;
  transparent_ = transparent;
  // Transparent accent (as window_manager's setBackgroundColor(transparent)):
  // DWM blends the window over the video window behind it with the alpha
  // Flutter renders, so transparent pixels show the video and translucent
  // fills (scrims, sheet barriers) dim it.
  //
  // Found while testing: a full-screen Flutter opacity layer (e.g.
  // AnimatedOpacity over a black box) comes out as solid black here, so
  // dimming over the video should paint a translucent colour instead.
  // Extending the DWM frame into the client area (-1 margins) tints
  // transparent pixels with the accent colour, so it isn't used.
  if (transparent) {
    SetAccent(window_, kAccentEnableTransparentGradient, 0x00000000);
  } else {
    // Back to window_manager's black window background.
    SetAccent(window_, kAccentEnableGradient, 0xFF000000);
  }
}

void HdrVideoHost::NotifyDisplayChanged() {
  if (channel_) channel_->InvokeMethod("displayChanged", nullptr);
}

void HdrVideoHost::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_WINDOWPOSCHANGED:
    case WM_MOVE:
    case WM_SIZE:
    case WM_SHOWWINDOW: {
      UpdateVideoWindow();
      // Moved to another monitor: its HDR state may differ.
      HMONITOR monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
      if (monitor != monitor_) {
        monitor_ = monitor;
        NotifyDisplayChanged();
      }
      break;
    }
    case WM_DISPLAYCHANGE:
      // Also sent when Windows HDR is switched on or off.
      monitor_ = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
      NotifyDisplayChanged();
      break;
  }
}
