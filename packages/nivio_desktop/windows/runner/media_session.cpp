#include "media_session.h"

#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <windows.foundation.h>
#include <windows.storage.streams.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

#include <variant>

namespace media = ABI::Windows::Media;
using ABI::Windows::Foundation::ITypedEventHandler;
using ABI::Windows::Foundation::TimeSpan;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), length);
  return wide;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) {
    return std::string();
  }
  const auto* text = std::get_if<std::string>(value);
  return text ? *text : std::string();
}

int64_t GetInt(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) {
    return 0;
  }
  if (const auto* v32 = std::get_if<int32_t>(value)) {
    return *v32;
  }
  if (const auto* v64 = std::get_if<int64_t>(value)) {
    return *v64;
  }
  return 0;
}

bool GetBool(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) {
    return false;
  }
  const auto* flag = std::get_if<bool>(value);
  return flag ? *flag : false;
}

TimeSpan MillisToTimeSpan(int64_t ms) {
  TimeSpan span;
  span.Duration = ms * 10000;  // 100ns ticks
  return span;
}

void SetThumbnail(media::ISystemMediaTransportControlsDisplayUpdater* updater,
                  const std::wstring& url) {
  ComPtr<ABI::Windows::Foundation::IUriRuntimeClassFactory> uri_factory;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(RuntimeClass_Windows_Foundation_Uri).Get(),
          IID_PPV_ARGS(uri_factory.GetAddressOf())))) {
    return;
  }
  ComPtr<ABI::Windows::Foundation::IUriRuntimeClass> uri;
  HStringReference url_ref(url.c_str(), static_cast<unsigned int>(url.size()));
  if (FAILED(uri_factory->CreateUri(url_ref.Get(), uri.GetAddressOf()))) {
    return;
  }
  ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStreamReferenceStatics>
      stream_statics;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(
              RuntimeClass_Windows_Storage_Streams_RandomAccessStreamReference)
              .Get(),
          IID_PPV_ARGS(stream_statics.GetAddressOf())))) {
    return;
  }
  ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStreamReference> stream;
  if (FAILED(stream_statics->CreateFromUri(uri.Get(), stream.GetAddressOf()))) {
    return;
  }
  updater->put_Thumbnail(stream.Get());
}

}  // namespace

MediaSession::MediaSession(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.nivio/media_session",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "update") {
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            Update(*args);
          }
          result->Success();
        } else if (call.method_name() == "clear") {
          Clear();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

MediaSession::~MediaSession() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
  if (controls_) {
    controls_->remove_ButtonPressed(button_token_);
    if (has_seek_token_) {
      ComPtr<media::ISystemMediaTransportControls2> controls2;
      if (SUCCEEDED(controls_.As(&controls2))) {
        controls2->remove_PlaybackPositionChangeRequested(seek_token_);
      }
    }
    controls_->put_IsEnabled(false);
  }
}

bool MediaSession::EnsureControls() {
  if (controls_) {
    return true;
  }

  ComPtr<ISystemMediaTransportControlsInterop> interop;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControls)
              .Get(),
          IID_PPV_ARGS(interop.GetAddressOf())))) {
    return false;
  }
  ComPtr<media::ISystemMediaTransportControls> controls;
  if (FAILED(interop->GetForWindow(window_,
                                   IID_PPV_ARGS(controls.GetAddressOf())))) {
    return false;
  }

  controls->put_IsPlayEnabled(true);
  controls->put_IsPauseEnabled(true);
  controls->put_IsStopEnabled(true);
  controls->put_IsNextEnabled(true);
  controls->put_IsPreviousEnabled(true);
  controls->put_IsFastForwardEnabled(true);
  controls->put_IsRewindEnabled(true);

  // SMTC raises these on a worker thread; post to the window so the Flutter
  // channel is only used from the platform thread.
  const HWND window = window_;
  auto button_handler = Callback<ITypedEventHandler<
      media::SystemMediaTransportControls*,
      media::SystemMediaTransportControlsButtonPressedEventArgs*>>(
      [window](media::ISystemMediaTransportControls* sender,
               media::ISystemMediaTransportControlsButtonPressedEventArgs* args)
          -> HRESULT {
        media::SystemMediaTransportControlsButton button;
        if (SUCCEEDED(args->get_Button(&button))) {
          ::PostMessage(window, kMediaSessionButtonMessage,
                        static_cast<WPARAM>(button), 0);
        }
        return S_OK;
      });
  controls->add_ButtonPressed(button_handler.Get(), &button_token_);

  ComPtr<media::ISystemMediaTransportControls2> controls2;
  if (SUCCEEDED(controls.As(&controls2))) {
    auto seek_handler = Callback<ITypedEventHandler<
        media::SystemMediaTransportControls*,
        media::PlaybackPositionChangeRequestedEventArgs*>>(
        [window](media::ISystemMediaTransportControls* sender,
                 media::IPlaybackPositionChangeRequestedEventArgs* args)
            -> HRESULT {
          TimeSpan position;
          if (SUCCEEDED(args->get_RequestedPlaybackPosition(&position))) {
            ::PostMessage(window, kMediaSessionSeekMessage, 0,
                          static_cast<LPARAM>(position.Duration / 10000));
          }
          return S_OK;
        });
    has_seek_token_ = SUCCEEDED(controls2->add_PlaybackPositionChangeRequested(
        seek_handler.Get(), &seek_token_));
  }

  controls_ = controls;
  return true;
}

void MediaSession::Update(const flutter::EncodableMap& args) {
  if (!EnsureControls()) {
    return;
  }

  const std::wstring title = Utf8ToWide(GetString(args, "title"));
  const std::wstring subtitle = Utf8ToWide(GetString(args, "subtitle"));
  const std::wstring art_url = Utf8ToWide(GetString(args, "artUrl"));
  const int64_t duration_ms = GetInt(args, "durationMs");
  const int64_t position_ms = GetInt(args, "positionMs");
  const bool playing = GetBool(args, "playing");

  controls_->put_IsEnabled(true);
  controls_->put_PlaybackStatus(playing ? media::MediaPlaybackStatus_Playing
                                        : media::MediaPlaybackStatus_Paused);

  const std::wstring metadata_key = title + L"\n" + subtitle + L"\n" + art_url;
  if (metadata_key != last_metadata_key_) {
    ComPtr<media::ISystemMediaTransportControlsDisplayUpdater> updater;
    if (SUCCEEDED(controls_->get_DisplayUpdater(updater.GetAddressOf()))) {
      last_metadata_key_ = metadata_key;
      updater->ClearAll();
      updater->put_Type(media::MediaPlaybackType_Video);
      ComPtr<media::IVideoDisplayProperties> video;
      if (SUCCEEDED(updater->get_VideoProperties(video.GetAddressOf()))) {
        HStringReference title_ref(title.c_str(),
                                   static_cast<unsigned int>(title.size()));
        video->put_Title(title_ref.Get());
        HStringReference subtitle_ref(subtitle.c_str(),
                                      static_cast<unsigned int>(subtitle.size()));
        video->put_Subtitle(subtitle_ref.Get());
      }
      if (!art_url.empty()) {
        SetThumbnail(updater.Get(), art_url);
      }
      updater->Update();
    }
  }

  // Timeline drives the seek bar in the Windows media flyout.
  ComPtr<media::ISystemMediaTransportControls2> controls2;
  if (duration_ms > 0 && SUCCEEDED(controls_.As(&controls2))) {
    ComPtr<IInspectable> instance;
    ComPtr<media::ISystemMediaTransportControlsTimelineProperties> timeline;
    if (SUCCEEDED(::RoActivateInstance(
            HStringReference(
                RuntimeClass_Windows_Media_SystemMediaTransportControlsTimelineProperties)
                .Get(),
            instance.GetAddressOf())) &&
        SUCCEEDED(instance.As(&timeline))) {
      timeline->put_StartTime(MillisToTimeSpan(0));
      timeline->put_MinSeekTime(MillisToTimeSpan(0));
      timeline->put_EndTime(MillisToTimeSpan(duration_ms));
      timeline->put_MaxSeekTime(MillisToTimeSpan(duration_ms));
      timeline->put_Position(MillisToTimeSpan(position_ms));
      controls2->UpdateTimelineProperties(timeline.Get());
    }
  }
}

void MediaSession::Clear() {
  if (!controls_) {
    return;
  }
  controls_->put_PlaybackStatus(media::MediaPlaybackStatus_Closed);
  ComPtr<media::ISystemMediaTransportControlsDisplayUpdater> updater;
  if (SUCCEEDED(controls_->get_DisplayUpdater(updater.GetAddressOf()))) {
    updater->ClearAll();
    updater->Update();
  }
  controls_->put_IsEnabled(false);
  last_metadata_key_.clear();
}

bool MediaSession::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kMediaSessionButtonMessage) {
    switch (static_cast<media::SystemMediaTransportControlsButton>(wparam)) {
      case media::SystemMediaTransportControlsButton_Play:
        SendCommand("play");
        break;
      case media::SystemMediaTransportControlsButton_Pause:
        SendCommand("pause");
        break;
      case media::SystemMediaTransportControlsButton_Stop:
        SendCommand("stop");
        break;
      case media::SystemMediaTransportControlsButton_Next:
        SendCommand("next");
        break;
      case media::SystemMediaTransportControlsButton_Previous:
        SendCommand("previous");
        break;
      case media::SystemMediaTransportControlsButton_FastForward:
        SendCommand("fastForward");
        break;
      case media::SystemMediaTransportControlsButton_Rewind:
        SendCommand("rewind");
        break;
      default:
        break;
    }
    return true;
  }
  if (message == kMediaSessionSeekMessage) {
    SendCommand("seek", static_cast<int64_t>(lparam));
    return true;
  }
  return false;
}

void MediaSession::SendCommand(const char* command, int64_t position_ms) {
  if (!channel_) {
    return;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("command")] =
      flutter::EncodableValue(std::string(command));
  if (position_ms >= 0) {
    args[flutter::EncodableValue("positionMs")] =
        flutter::EncodableValue(position_ms);
  }
  channel_->InvokeMethod("onCommand",
                         std::make_unique<flutter::EncodableValue>(args));
}
