#include "native_trailer_overlay.h"

#include <WebView2.h>
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <wil/com.h>
#include <windowsx.h>
#include <wrl.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace {

using Microsoft::WRL::Callback;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

constexpr char kChannelName[] = "nivio/native_trailer_preview";
constexpr wchar_t kHostClassName[] = L"NivioNativeTrailerHost";
constexpr wchar_t kBadgeClassName[] = L"NivioNativeTrailerBadge";
constexpr wchar_t kPreviewOrigin[] = L"https://nivio.local";
constexpr int kBadgeSize = 32;
constexpr int kBadgeInset = 10;
constexpr int kBadgeGap = 8;
constexpr int kMuteBadgeId = 1001;
constexpr int kCloseBadgeId = 1002;
constexpr char kBlankHtml[] =
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head>"
    "<body style=\"margin:0;background:#000;\"></body></html>";

class NativeTrailerOverlayWindows;

LRESULT CALLBACK HostWndProc(HWND hwnd, UINT message, WPARAM wparam,
                             LPARAM lparam);
LRESULT CALLBACK BadgeWndProc(HWND hwnd, UINT message, WPARAM wparam,
                              LPARAM lparam);

std::wstring Utf16FromUtf8(const std::string &text) {
  if (text.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring(text.begin(), text.end());
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size);
  return result;
}

std::string Utf8FromUtf16(const std::wstring &text) {
  if (text.empty()) {
    return std::string();
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size <= 0) {
    return std::string(text.begin(), text.end());
  }
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring HtmlEscape(const std::string &text) {
  std::wstring escaped;
  for (char value : text) {
    switch (value) {
    case '&':
      escaped += L"&amp;";
      break;
    case '<':
      escaped += L"&lt;";
      break;
    case '>':
      escaped += L"&gt;";
      break;
    case '"':
      escaped += L"&quot;";
      break;
    case '\'':
      escaped += L"&#39;";
      break;
    default:
      escaped += static_cast<wchar_t>(static_cast<unsigned char>(value));
      break;
    }
  }
  return escaped;
}

std::wstring YoutubePreviewHtml(const std::string &video_id) {
  const std::wstring escaped_video_id = HtmlEscape(video_id);
  const std::wstring source =
      std::wstring(L"https://www.youtube-nocookie.com/embed/") +
      escaped_video_id +
      L"?autoplay=1&mute=1"
      L"&controls=0&enablejsapi=1&playsinline=1&fs=0"
      L"&iv_load_policy=3&rel=0&modestbranding=1&loop=1"
      L"&playlist=" +
      escaped_video_id + L"&origin=" + kPreviewOrigin;

  return std::wstring(LR"(<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    * { margin: 0; padding: 0; overflow: hidden; }
    html, body { width: 100%; height: 100%; background: transparent; }
    body { position: relative; border-radius: 9px 9px 0 0; overflow: hidden; }
    #player { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe
    id="player"
    src=")") +
         source + LR"("
    allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
    allowfullscreen
    referrerpolicy="strict-origin-when-cross-origin">
  </iframe>
  <script>
    document.body.dataset.ytReady = '0';
    document.body.dataset.ytPlaying = '0';
    document.body.dataset.ytError = '';
    document.body.dataset.ytPlayAttempts = '0';
    document.body.dataset.nivioMuted = '1';

    var tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    window.nivioPlayer = null;
    window.nivioSetMuted = function(muted) {
      document.body.dataset.nivioMuted = muted ? '1' : '0';
      try {
        if (window.nivioPlayer) {
          if (muted) {
            window.nivioPlayer.mute();
            window.nivioPlayer.setVolume(0);
          } else {
            window.nivioPlayer.unMute();
            window.nivioPlayer.setVolume(100);
          }
          window.nivioPlayer.playVideo();
        }
      } catch (error) {}
      try {
        var iframe = document.getElementById('player');
        if (iframe && iframe.contentWindow) {
          var post = function(func, args) {
            iframe.contentWindow.postMessage(JSON.stringify({
              event: 'command',
              func: func,
              args: args || []
            }), '*');
          };
          if (muted) {
            post('mute');
            post('setVolume', [0]);
          } else {
            post('unMute');
            post('setVolume', [100]);
          }
          post('playVideo');
        }
      } catch (error) {}
    };

    window.nivioForcePlay = function() {
      document.body.dataset.ytPlayAttempts = String(
        Number(document.body.dataset.ytPlayAttempts || '0') + 1
      );
      try {
        if (window.nivioPlayer) {
          if (document.body.dataset.nivioMuted !== '0') {
            window.nivioPlayer.mute();
            window.nivioPlayer.setVolume(0);
          }
          window.nivioPlayer.playVideo();
        }
      } catch (error) {}
      try {
        var iframe = document.getElementById('player');
        if (iframe && iframe.contentWindow) {
          var post = function(func, args) {
            iframe.contentWindow.postMessage(JSON.stringify({
              event: 'command',
              func: func,
              args: args || []
            }), '*');
          };
          if (document.body.dataset.nivioMuted !== '0') {
            post('mute');
            post('setVolume', [0]);
          }
          post('playVideo');
        }
      } catch (error) {}
    };

    window.nivioPlayTimer = window.setInterval(function() {
      if (document.body.dataset.ytPlaying === '1') {
        window.clearInterval(window.nivioPlayTimer);
        return;
      }
      window.nivioForcePlay();
    }, 350);

    function onYouTubeIframeAPIReady() {
      window.nivioPlayer = new YT.Player('player', {
        events: {
          onReady: function(event) {
            document.body.dataset.ytReady = '1';
            event.target.mute();
            event.target.setVolume(0);
            event.target.playVideo();
            window.nivioForcePlay();
          },
          onStateChange: function(event) {
            if (event.data === 1) {
              document.body.dataset.ytPlaying = '1';
              window.clearInterval(window.nivioPlayTimer);
            }
            if (event.data === 0) {
              event.target.seekTo(0);
              event.target.playVideo();
            }
            if (document.body.dataset.nivioMuted !== '0') {
              event.target.mute();
              event.target.setVolume(0);
            }
          },
          onError: function(event) {
            document.body.dataset.ytError = String(event.data || 'unknown');
          }
        }
      });
    }
  </script>
</body>
</html>
)";
}

const flutter::EncodableMap *AsMap(const flutter::EncodableValue *value) {
  if (value == nullptr) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(value);
}

const flutter::EncodableValue *Lookup(const flutter::EncodableMap *map,
                                      const char *key) {
  if (map == nullptr) {
    return nullptr;
  }
  const auto it = map->find(flutter::EncodableValue(std::string(key)));
  if (it == map->end()) {
    return nullptr;
  }
  return &it->second;
}

int64_t ReadInt(const flutter::EncodableMap *map, const char *key,
                int64_t fallback) {
  const flutter::EncodableValue *value = Lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto typed = std::get_if<int32_t>(value)) {
    return *typed;
  }
  if (const auto typed = std::get_if<int64_t>(value)) {
    return *typed;
  }
  return fallback;
}

double ReadDouble(const flutter::EncodableMap *map, const char *key,
                  double fallback) {
  const flutter::EncodableValue *value = Lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto typed = std::get_if<double>(value)) {
    return *typed;
  }
  if (const auto typed = std::get_if<int32_t>(value)) {
    return static_cast<double>(*typed);
  }
  if (const auto typed = std::get_if<int64_t>(value)) {
    return static_cast<double>(*typed);
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap *map, const char *key,
              bool fallback) {
  const flutter::EncodableValue *value = Lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto typed = std::get_if<bool>(value)) {
    return *typed;
  }
  return fallback;
}

std::string ReadString(const flutter::EncodableMap *map, const char *key) {
  const flutter::EncodableValue *value = Lookup(map, key);
  if (value == nullptr) {
    return std::string();
  }
  if (const auto typed = std::get_if<std::string>(value)) {
    return *typed;
  }
  return std::string();
}

RECT RectFromArgs(const flutter::EncodableMap *map) {
  const double x = ReadDouble(map, "x", 0);
  const double y = ReadDouble(map, "y", 0);
  const double width = ReadDouble(map, "width", 0);
  const double height = ReadDouble(map, "height", 0);
  RECT rect{
      static_cast<LONG>(std::lround(x)),
      static_cast<LONG>(std::lround(y)),
      static_cast<LONG>(std::lround(x + width)),
      static_cast<LONG>(std::lround(y + height)),
  };
  return rect;
}

bool HasUsableSize(const RECT &rect) {
  return rect.right - rect.left > 1 && rect.bottom - rect.top > 1;
}

void RegisterWindowClasses() {
  static bool registered = false;
  if (registered) {
    return;
  }
  HINSTANCE instance = GetModuleHandle(nullptr);

  WNDCLASS host_class{};
  host_class.lpfnWndProc = HostWndProc;
  host_class.hInstance = instance;
  host_class.lpszClassName = kHostClassName;
  host_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClass(&host_class);

  WNDCLASS badge_class{};
  badge_class.lpfnWndProc = BadgeWndProc;
  badge_class.hInstance = instance;
  badge_class.lpszClassName = kBadgeClassName;
  badge_class.hCursor = LoadCursor(nullptr, IDC_HAND);
  RegisterClass(&badge_class);

  registered = true;
}

class NativeTrailerOverlayWindows : public NativeTrailerOverlay {
public:
  NativeTrailerOverlayWindows(HWND parent_window,
                              flutter::BinaryMessenger *messenger)
      : parent_window_(parent_window) {
    RegisterWindowClasses();
    channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, kChannelName,
            &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue> &call,
               std::unique_ptr<MethodResult> result) {
          HandleMethodCall(call, std::move(result));
        });
  }

  ~NativeTrailerOverlayWindows() override {
    if (channel_) {
      channel_->SetMethodCallHandler(nullptr);
    }
    if (controller_) {
      controller_->Close();
      controller_.reset();
    }
    webview_.reset();
    environment_.reset();
    if (mute_badge_window_ != nullptr) {
      DestroyWindow(mute_badge_window_);
      mute_badge_window_ = nullptr;
    }
    if (close_badge_window_ != nullptr) {
      DestroyWindow(close_badge_window_);
      close_badge_window_ = nullptr;
    }
    if (host_window_ != nullptr) {
      DestroyWindow(host_window_);
      host_window_ = nullptr;
    }
  }

  bool HandleWindowMessage(HWND, UINT message, WPARAM wparam, LPARAM lparam,
                           LRESULT *result) override {
    if (message == WM_SIZE) {
      UpdateBounds();
      return false;
    }
    if (message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL) {
      if (ForwardWheelMessage(message, wparam, lparam)) {
        if (result != nullptr) {
          *result = 0;
        }
        return true;
      }
    }
    return false;
  }

  LRESULT HandleHostMessage(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
    if (message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL) {
      if (ForwardWheelMessage(message, wparam, lparam)) {
        return 0;
      }
    }
    if (message == WM_ERASEBKGND) {
      return 1;
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  LRESULT HandleBadgeMessage(HWND hwnd, UINT message, WPARAM wparam,
                             LPARAM lparam) {
    switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      PaintBadge(hwnd);
      return 0;
    case WM_LBUTTONUP:
      if (GetDlgCtrlID(hwnd) == kCloseBadgeId) {
        RequestClose();
      } else if (GetDlgCtrlID(hwnd) == kMuteBadgeId) {
        SetMuted(!muted_);
      }
      return 0;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_HAND));
      return TRUE;
    default:
      break;
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

private:
  void
  HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &call,
                   std::unique_ptr<MethodResult> result) {
    const flutter::EncodableMap *args = AsMap(call.arguments());
    const std::string &method = call.method_name();

    if (method == "prepare") {
      active_token_ = static_cast<int>(ReadInt(args, "token", 0));
      pending_prepare_results_.push_back(std::move(result));
      BeginCreateWebView();
      return;
    }

    if (method == "show") {
      const int token = static_cast<int>(ReadInt(args, "token", 0));
      if (!TokenMatches(token) || !webview_ || !controller_) {
        result->Success(flutter::EncodableValue(false));
        return;
      }

      const std::string video_id = ReadString(args, "videoId");
      if (video_id.empty()) {
        result->Error("invalid_video", "videoId is required");
        return;
      }

      UpdateRect(args);
      if (loaded_video_id_ != video_id) {
        SetMuted(true);
        webview_->NavigateToString(YoutubePreviewHtml(video_id).c_str());
        loaded_video_id_ = video_id;
      }
      SetVisible(ReadBool(args, "visible", false));
      result->Success(flutter::EncodableValue(true));
      return;
    }

    if (method == "updateRect") {
      const int token = static_cast<int>(ReadInt(args, "token", 0));
      if (TokenMatches(token)) {
        UpdateRect(args);
      }
      result->Success();
      return;
    }

    if (method == "setVisible") {
      const int token = static_cast<int>(ReadInt(args, "token", 0));
      if (TokenMatches(token)) {
        SetVisible(ReadBool(args, "visible", false));
      }
      result->Success();
      return;
    }

    if (method == "status") {
      const int token = static_cast<int>(ReadInt(args, "token", 0));
      if (!TokenMatches(token) || !webview_ || loaded_video_id_.empty()) {
        result->Success();
        return;
      }
      const wchar_t *script =
          L"(function(){"
          L"if(window.nivioForcePlay) window.nivioForcePlay();"
          L"return JSON.stringify({"
          L"ready:document.body.dataset.ytReady==='1',"
          L"playing:document.body.dataset.ytPlaying==='1',"
          L"error:document.body.dataset.ytError||''"
          L"});})();";
      webview_->ExecuteScript(
          script, Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
                      [result = std::move(result)](HRESULT error,
                                                   LPCWSTR value) -> HRESULT {
                        if (FAILED(error)) {
                          result->Error("javascript_error",
                                        "WebView2 ExecuteScript failed");
                          return S_OK;
                        }
                        if (value == nullptr) {
                          result->Success();
                          return S_OK;
                        }
                        result->Success(flutter::EncodableValue(
                            Utf8FromUtf16(std::wstring(value))));
                        return S_OK;
                      })
                      .Get());
      return;
    }

    if (method == "hide") {
      const int token = static_cast<int>(ReadInt(args, "token", 0));
      if (token == 0 || TokenMatches(token)) {
        Hide(true);
      }
      result->Success();
      return;
    }

    result->NotImplemented();
  }

  bool TokenMatches(int token) const {
    return token != 0 && token == active_token_;
  }

  void BeginCreateWebView() {
    if (!EnsureWindowsCreated()) {
      CompletePrepare(false);
      return;
    }
    if (webview_ && controller_) {
      CompletePrepare(true);
      return;
    }
    if (creating_webview_) {
      return;
    }
    creating_webview_ = true;

    HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, nullptr, nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [this](HRESULT result,
                   ICoreWebView2Environment *environment) -> HRESULT {
              if (FAILED(result) || environment == nullptr) {
                creating_webview_ = false;
                CompletePrepare(false);
                return S_OK;
              }
              HRESULT copy_environment_hr =
                  environment->QueryInterface(IID_PPV_ARGS(environment_.put()));
              if (FAILED(copy_environment_hr)) {
                creating_webview_ = false;
                CompletePrepare(false);
                return S_OK;
              }
              HRESULT controller_hr = environment_->CreateCoreWebView2Controller(
                  host_window_,
                  Callback<
                      ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                      [this](HRESULT controller_result,
                             ICoreWebView2Controller *controller) -> HRESULT {
                        creating_webview_ = false;
                        if (FAILED(controller_result) ||
                            controller == nullptr) {
                          CompletePrepare(false);
                          return S_OK;
                        }
                        HRESULT copy_controller_hr = controller->QueryInterface(
                            IID_PPV_ARGS(controller_.put()));
                        if (FAILED(copy_controller_hr)) {
                          CompletePrepare(false);
                          return S_OK;
                        }
                        controller_->get_CoreWebView2(webview_.put());
                        ConfigureWebView();
                        UpdateBounds();
                        SetVisible(false);
                        CompletePrepare(webview_ != nullptr);
                        return S_OK;
                      })
                      .Get());
              if (FAILED(controller_hr)) {
                creating_webview_ = false;
                CompletePrepare(false);
              }
              return S_OK;
            })
            .Get());

    if (FAILED(hr)) {
      creating_webview_ = false;
      CompletePrepare(false);
    }
  }

  void CompletePrepare(bool success) {
    for (auto &result : pending_prepare_results_) {
      result->Success(flutter::EncodableValue(success));
    }
    pending_prepare_results_.clear();
  }

  bool EnsureWindowsCreated() {
    if (host_window_ != nullptr) {
      return true;
    }
    HINSTANCE instance = GetModuleHandle(nullptr);
    host_window_ =
        CreateWindowEx(WS_EX_NOACTIVATE, kHostClassName, L"",
                       WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN, 0, 0, 1, 1,
                       parent_window_, nullptr, instance, nullptr);
    SetWindowLongPtr(host_window_, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(this));

    mute_badge_window_ = CreateWindowEx(
        WS_EX_NOACTIVATE, kBadgeClassName, L"", WS_CHILD | WS_CLIPSIBLINGS, 0,
        0, kBadgeSize, kBadgeSize, parent_window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kMuteBadgeId)), instance,
        nullptr);
    SetWindowLongPtr(mute_badge_window_, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(this));

    close_badge_window_ = CreateWindowEx(
        WS_EX_NOACTIVATE, kBadgeClassName, L"", WS_CHILD | WS_CLIPSIBLINGS, 0,
        0, kBadgeSize, kBadgeSize, parent_window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCloseBadgeId)), instance,
        nullptr);
    SetWindowLongPtr(close_badge_window_, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(this));

    if (host_window_ == nullptr || mute_badge_window_ == nullptr ||
        close_badge_window_ == nullptr) {
      return false;
    }

    ShowWindow(host_window_, SW_HIDE);
    ShowWindow(mute_badge_window_, SW_HIDE);
    ShowWindow(close_badge_window_, SW_HIDE);
    return true;
  }

  void ConfigureWebView() {
    if (!webview_) {
      return;
    }
    wil::com_ptr<ICoreWebView2Settings> settings;
    webview_->get_Settings(settings.put());
    if (settings) {
      settings->put_IsScriptEnabled(TRUE);
      settings->put_AreDefaultContextMenusEnabled(FALSE);
      settings->put_AreDefaultScriptDialogsEnabled(FALSE);
      settings->put_AreDevToolsEnabled(FALSE);
      settings->put_IsStatusBarEnabled(FALSE);
    }
    webview_->NavigateToString(Utf16FromUtf8(kBlankHtml).c_str());
  }

  void UpdateRect(const flutter::EncodableMap *args) {
    if (!EnsureWindowsCreated()) {
      return;
    }
    trailer_rect_ = RectFromArgs(args);
    show_close_button_ = ReadBool(args, "showCloseButton", false);
    UpdateBounds();
  }

  void UpdateBounds() {
    if (host_window_ == nullptr || !HasUsableSize(trailer_rect_)) {
      SetVisible(false);
      return;
    }

    const int width = trailer_rect_.right - trailer_rect_.left;
    const int height = trailer_rect_.bottom - trailer_rect_.top;
    MoveWindow(host_window_, trailer_rect_.left, trailer_rect_.top, width,
               height, TRUE);
    SetWindowPos(host_window_, HWND_TOP, trailer_rect_.left, trailer_rect_.top,
                 width, height, SWP_NOACTIVATE);

    RECT bounds{0, 0, width, height};
    if (controller_) {
      controller_->put_Bounds(bounds);
    }

    const int mute_left = trailer_rect_.right - kBadgeSize - kBadgeInset;
    const int close_left =
        trailer_rect_.right - (kBadgeSize * 2) - kBadgeInset - kBadgeGap;
    const int badge_top = trailer_rect_.top + kBadgeInset;

    MoveWindow(mute_badge_window_, std::max<int>(trailer_rect_.left, mute_left),
               badge_top, kBadgeSize, kBadgeSize, TRUE);
    MoveWindow(close_badge_window_,
               std::max<int>(trailer_rect_.left, close_left), badge_top,
               kBadgeSize, kBadgeSize, TRUE);
    SetWindowPos(mute_badge_window_, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    SetWindowPos(close_badge_window_, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    if (visible_) {
      ShowBadges();
    }
  }

  void SetVisible(bool visible) {
    visible_ = visible && HasUsableSize(trailer_rect_);
    if (controller_) {
      controller_->put_IsVisible(visible_ ? TRUE : FALSE);
    }
    if (host_window_ != nullptr) {
      ShowWindow(host_window_, visible_ ? SW_SHOWNA : SW_HIDE);
      if (visible_) {
        SetWindowPos(host_window_, HWND_TOP, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      }
    }
    ShowBadges();
  }

  void ShowBadges() {
    if (mute_badge_window_ != nullptr) {
      ShowWindow(mute_badge_window_, visible_ ? SW_SHOWNA : SW_HIDE);
      SetWindowPos(mute_badge_window_, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      InvalidateRect(mute_badge_window_, nullptr, TRUE);
    }
    if (close_badge_window_ != nullptr) {
      ShowWindow(close_badge_window_,
                 visible_ && show_close_button_ ? SW_SHOWNA : SW_HIDE);
      SetWindowPos(close_badge_window_, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      InvalidateRect(close_badge_window_, nullptr, TRUE);
    }
  }

  void Hide(bool clear_page) {
    SetVisible(false);
    loaded_video_id_.clear();
    if (clear_page && webview_) {
      webview_->NavigateToString(Utf16FromUtf8(kBlankHtml).c_str());
    }
  }

  void SetMuted(bool value) {
    muted_ = value;
    if (mute_badge_window_ != nullptr) {
      InvalidateRect(mute_badge_window_, nullptr, TRUE);
    }
    if (!webview_ || loaded_video_id_.empty()) {
      return;
    }
    const wchar_t *script =
        muted_ ? L"(function(){if(window.nivioSetMuted) "
                 L"window.nivioSetMuted(true);return '1';})();"
               : L"(function(){if(window.nivioSetMuted) "
                 L"window.nivioSetMuted(false);return '1';})();";
    webview_->ExecuteScript(script, nullptr);
  }

  bool ForwardWheelMessage(UINT message, WPARAM wparam, LPARAM lparam) {
    if (!visible_ || !channel_ || !HasUsableSize(trailer_rect_)) {
      return false;
    }
    POINT screen_point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    POINT client_point = screen_point;
    ScreenToClient(parent_window_, &client_point);
    if (!PtInRect(&trailer_rect_, client_point)) {
      return false;
    }

    const double units = static_cast<double>(GET_WHEEL_DELTA_WPARAM(wparam)) /
                         static_cast<double>(WHEEL_DELTA);
    double dx = 0;
    double dy = 0;
    if (message == WM_MOUSEHWHEEL) {
      dx = units * 72.0;
    } else {
      dy = -units * 72.0;
    }

    flutter::EncodableMap args;
    args[flutter::EncodableValue("dx")] = flutter::EncodableValue(dx);
    args[flutter::EncodableValue("dy")] = flutter::EncodableValue(dy);
    args[flutter::EncodableValue("x")] =
        flutter::EncodableValue(static_cast<double>(client_point.x));
    args[flutter::EncodableValue("y")] =
        flutter::EncodableValue(static_cast<double>(client_point.y));
    channel_->InvokeMethod(
        "nativeScroll",
        std::make_unique<flutter::EncodableValue>(std::move(args)));
    return true;
  }

  void RequestClose() {
    if (!channel_) {
      return;
    }
    flutter::EncodableMap args;
    args[flutter::EncodableValue("token")] =
        flutter::EncodableValue(active_token_);
    channel_->InvokeMethod(
        "nativeClose",
        std::make_unique<flutter::EncodableValue>(std::move(args)));
  }

  void PaintBadge(HWND hwnd) {
    PAINTSTRUCT paint;
    HDC hdc = BeginPaint(hwnd, &paint);
    RECT rect;
    GetClientRect(hwnd, &rect);

    HBRUSH background = CreateSolidBrush(RGB(0, 0, 0));
    HPEN transparent_pen = CreatePen(PS_SOLID, 1, RGB(0, 0, 0));
    HGDIOBJ old_brush = SelectObject(hdc, background);
    HGDIOBJ old_pen = SelectObject(hdc, transparent_pen);
    RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, 16, 16);
    SelectObject(hdc, old_pen);
    SelectObject(hdc, old_brush);
    DeleteObject(transparent_pen);
    DeleteObject(background);

    HPEN white_pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
    HGDIOBJ old_white_pen = SelectObject(hdc, white_pen);
    SelectObject(hdc, GetStockObject(NULL_BRUSH));

    if (GetDlgCtrlID(hwnd) == kCloseBadgeId) {
      MoveToEx(hdc, 11, 11, nullptr);
      LineTo(hdc, 21, 21);
      MoveToEx(hdc, 21, 11, nullptr);
      LineTo(hdc, 11, 21);
    } else {
      POINT speaker[] = {{9, 14},  {13, 14}, {18, 10},
                         {18, 22}, {13, 18}, {9, 18}};
      Polygon(hdc, speaker, 6);
      if (muted_) {
        MoveToEx(hdc, 22, 12, nullptr);
        LineTo(hdc, 27, 20);
        MoveToEx(hdc, 27, 12, nullptr);
        LineTo(hdc, 22, 20);
      } else {
        Arc(hdc, 18, 11, 27, 21, 21, 13, 21, 19);
        Arc(hdc, 16, 8, 31, 24, 23, 10, 23, 22);
      }
    }

    SelectObject(hdc, old_white_pen);
    DeleteObject(white_pen);
    EndPaint(hwnd, &paint);
  }

  HWND parent_window_ = nullptr;
  HWND host_window_ = nullptr;
  HWND mute_badge_window_ = nullptr;
  HWND close_badge_window_ = nullptr;
  RECT trailer_rect_{0, 0, 0, 0};
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::vector<std::unique_ptr<MethodResult>> pending_prepare_results_;
  wil::com_ptr<ICoreWebView2Environment> environment_;
  wil::com_ptr<ICoreWebView2Controller> controller_;
  wil::com_ptr<ICoreWebView2> webview_;
  int active_token_ = 0;
  bool creating_webview_ = false;
  bool visible_ = false;
  bool muted_ = true;
  bool show_close_button_ = false;
  std::string loaded_video_id_;
};

LRESULT CALLBACK HostWndProc(HWND hwnd, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  auto *overlay = reinterpret_cast<NativeTrailerOverlayWindows *>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (overlay != nullptr) {
    return overlay->HandleHostMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK BadgeWndProc(HWND hwnd, UINT message, WPARAM wparam,
                              LPARAM lparam) {
  auto *overlay = reinterpret_cast<NativeTrailerOverlayWindows *>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (overlay != nullptr) {
    return overlay->HandleBadgeMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

} // namespace

std::unique_ptr<NativeTrailerOverlay>
CreateNativeTrailerOverlay(HWND parent_window,
                           flutter::BinaryMessenger *messenger) {
  if (parent_window == nullptr || messenger == nullptr) {
    return nullptr;
  }
  return std::make_unique<NativeTrailerOverlayWindows>(parent_window,
                                                       messenger);
}
