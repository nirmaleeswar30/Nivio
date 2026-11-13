#ifndef RUNNER_HDR_VIDEO_HOST_H_
#define RUNNER_HDR_VIDEO_HOST_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// True HDR video on Windows.
//
// Flutter composites everything (media_kit's video texture included) as 8-bit
// SDR, so HDR video can't go through it. Instead mpv renders with its own
// gpu-next / Direct3D 11 swapchain (which it tags as HDR10) into a separate
// window kept directly behind the app window, and the app window turns
// see-through, so Flutter's controls and subtitles draw on top of the video.
// With Windows HDR on, DWM composes both: the video as HDR, the UI as SDR.
//
// Dart side: lib/widgets/windows_hdr_video_surface.dart, over the
// "com.nivio/hdr_window" channel.
class HdrVideoHost {
 public:
  HdrVideoHost(HWND window, flutter::BinaryMessenger* messenger);
  ~HdrVideoHost();

  HdrVideoHost(const HdrVideoHost&) = delete;
  HdrVideoHost& operator=(const HdrVideoHost&) = delete;

  // Called for every message of the top-level window; never consumes one.
  void HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // HDR state of the monitor the app window is on (asked fresh each time:
  // Windows HDR can be switched on and off at any moment).
  flutter::EncodableMap DisplayInfo();

  bool EnsureVideoWindow();
  void DestroyVideoWindow();
  // Moves the backdrop under the app window's client area, just below the
  // app window in z-order, and mpv's window to the video rect. Hidden while
  // the app window is minimized or hidden.
  void UpdateVideoWindow();
  // See-through app window (alpha 0 pixels show the video window).
  void SetTransparent(bool transparent);
  void NotifyDisplayChanged();

  HWND window_;
  // Black backdrop covering the app window's whole client area (so nothing
  // Flutter leaves unpainted shows the desktop), and mpv's window inside it
  // at the video rect.
  HWND video_ = nullptr;
  HWND video_child_ = nullptr;
  // Video rect in physical pixels, relative to the app window's client area.
  RECT rect_{};
  bool transparent_ = false;
  HMONITOR monitor_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_HDR_VIDEO_HOST_H_
