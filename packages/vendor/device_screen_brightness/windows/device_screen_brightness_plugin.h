#ifndef FLUTTER_PLUGIN_DEVICE_SCREEN_BRIGHTNESS_PLUGIN_H_
#define FLUTTER_PLUGIN_DEVICE_SCREEN_BRIGHTNESS_PLUGIN_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <optional>

namespace device_screen_brightness {

class DeviceScreenBrightnessPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DeviceScreenBrightnessPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~DeviceScreenBrightnessPlugin() override;

  DeviceScreenBrightnessPlugin(const DeviceScreenBrightnessPlugin&) = delete;
  DeviceScreenBrightnessPlugin& operator=(const DeviceScreenBrightnessPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListen(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events);
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancel(
      const flutter::EncodableValue* arguments);
  std::optional<LRESULT> HandleWindowMessage(HWND hwnd,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam);
  void EmitCurrentBrightness();

  flutter::PluginRegistrarWindows* registrar_;
  HWND window_ = nullptr;
  int window_proc_delegate_id_ = -1;
  UINT_PTR timer_id_ = 0;
  int last_emitted_value_ = -1;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace device_screen_brightness

#endif
