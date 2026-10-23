#ifndef RUNNER_MEDIA_SESSION_H_
#define RUNNER_MEDIA_SESSION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <windows.media.h>
#include <wrl/client.h>

#include <memory>
#include <string>

// Window messages used to hop SMTC events (raised on a worker thread) back
// onto the platform thread before talking to Flutter.
constexpr UINT kMediaSessionButtonMessage = WM_APP + 0x4E1;
constexpr UINT kMediaSessionSeekMessage = WM_APP + 0x4E2;

// Bridges Windows System Media Transport Controls to the Dart
// MediaSessionService over the "com.nivio/media_session" channel, so
// Bluetooth headset buttons, keyboard media keys and the volume-flyout media
// controls drive the player.
class MediaSession {
 public:
  MediaSession(HWND window, flutter::BinaryMessenger* messenger);
  ~MediaSession();

  MediaSession(const MediaSession&) = delete;
  MediaSession& operator=(const MediaSession&) = delete;

  // Handles kMediaSession* messages. Returns true if |message| was one.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool EnsureControls();
  void Update(const flutter::EncodableMap& args);
  void Clear();
  void SendCommand(const char* command, int64_t position_ms = -1);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Microsoft::WRL::ComPtr<ABI::Windows::Media::ISystemMediaTransportControls>
      controls_;
  EventRegistrationToken button_token_{};
  EventRegistrationToken seek_token_{};
  bool has_seek_token_ = false;
  std::wstring last_metadata_key_;
};

#endif  // RUNNER_MEDIA_SESSION_H_
