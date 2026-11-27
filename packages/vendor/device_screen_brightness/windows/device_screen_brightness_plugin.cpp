#include "device_screen_brightness_plugin.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <highlevelmonitorconfigurationapi.h>
#include <physicalmonitorenumerationapi.h>

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

namespace device_screen_brightness {
namespace {

constexpr char kMethodChannel[] =
    "dev.arcas.device_screen_brightness/methods";
constexpr char kEventChannel[] =
    "dev.arcas.device_screen_brightness/events";
constexpr UINT_PTR kPollTimerId = 0x445342;

enum class ErrorCode { kOk, kBackendNotAvailable, kNativeFailure };

struct BrightnessResult {
  int value;
  ErrorCode error;
};

const flutter::EncodableMap* Arguments(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  return std::get_if<flutter::EncodableMap>(call.arguments());
}

const std::string* StringArgument(const flutter::EncodableMap* arguments,
                                  const char* key) {
  if (!arguments) return nullptr;
  const auto found = arguments->find(flutter::EncodableValue(key));
  if (found == arguments->end()) return nullptr;
  return std::get_if<std::string>(&found->second);
}

std::optional<int> IntArgument(const flutter::EncodableMap* arguments,
                               const char* key) {
  if (!arguments) return std::nullopt;
  const auto found = arguments->find(flutter::EncodableValue(key));
  if (found == arguments->end()) return std::nullopt;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    return static_cast<int>(*value);
  }
  return std::nullopt;
}

flutter::EncodableValue ErrorDetails(const std::string& operation) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("platform"), flutter::EncodableValue("windows")},
      {flutter::EncodableValue("operation"), flutter::EncodableValue(operation)},
      {flutter::EncodableValue("backend"), flutter::EncodableValue("dxva2")},
  });
}

BrightnessResult WithPhysicalMonitor(bool write, int requested = 0) {
  const HMONITOR logical =
      MonitorFromWindow(GetDesktopWindow(), MONITOR_DEFAULTTOPRIMARY);
  if (!logical) return {0, ErrorCode::kBackendNotAvailable};

  DWORD count = 0;
  if (!GetNumberOfPhysicalMonitorsFromHMONITOR(logical, &count) || count == 0) {
    return {0, ErrorCode::kBackendNotAvailable};
  }
  std::vector<PHYSICAL_MONITOR> monitors(count);
  if (!GetPhysicalMonitorsFromHMONITOR(logical, count, monitors.data())) {
    return {0, ErrorCode::kBackendNotAvailable};
  }

  BrightnessResult answer{0, ErrorCode::kBackendNotAvailable};
  for (const auto& monitor : monitors) {
    DWORD minimum = 0;
    DWORD current = 0;
    DWORD maximum = 0;
    if (!GetMonitorBrightness(monitor.hPhysicalMonitor, &minimum, &current,
                              &maximum) || maximum <= minimum) {
      continue;
    }
    if (write) {
      const DWORD native_value = minimum + static_cast<DWORD>(std::lround(
          static_cast<double>(requested) * (maximum - minimum) / 100.0));
      if (!SetMonitorBrightness(monitor.hPhysicalMonitor, native_value)) {
        answer = {0, ErrorCode::kNativeFailure};
        break;
      }
      if (!GetMonitorBrightness(monitor.hPhysicalMonitor, &minimum, &current,
                                &maximum)) {
        answer = {0, ErrorCode::kNativeFailure};
        break;
      }
    }
    answer = {static_cast<int>(std::lround(
                  static_cast<double>(current - minimum) * 100.0 /
                  static_cast<double>(maximum - minimum))),
              ErrorCode::kOk};
    break;
  }
  DestroyPhysicalMonitors(count, monitors.data());
  return answer;
}

flutter::EncodableValue ValueResult(int value) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("value"), flutter::EncodableValue(value)},
  });
}

}  // namespace

void DeviceScreenBrightnessPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto methods =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kMethodChannel,
          &flutter::StandardMethodCodec::GetInstance());
  auto events =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kEventChannel,
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<DeviceScreenBrightnessPlugin>(registrar);
  auto* plugin_pointer = plugin.get();

  methods->SetMethodCallHandler(
      [plugin_pointer](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  events->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_pointer](const auto* arguments, auto&& sink) {
            return plugin_pointer->OnListen(arguments, std::move(sink));
          },
          [plugin_pointer](const auto* arguments) {
            return plugin_pointer->OnCancel(arguments);
          }));
  registrar->AddPlugin(std::move(plugin));
}

DeviceScreenBrightnessPlugin::DeviceScreenBrightnessPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  if (registrar_->GetView()) window_ = registrar_->GetView()->GetNativeWindow();
  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(hwnd, message, wparam, lparam);
      });
}

DeviceScreenBrightnessPlugin::~DeviceScreenBrightnessPlugin() {
  if (timer_id_ != 0 && window_) KillTimer(window_, timer_id_);
  event_sink_.reset();
  if (window_proc_delegate_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
}

void DeviceScreenBrightnessPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string operation = call.method_name();
  const auto* arguments = Arguments(call);

  if (operation == "hasPermission") {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (operation == "requestPermission") {
    result->Success();
    return;
  }
  if (operation == "getCapabilities") {
    const bool available = WithPhysicalMonitor(false).error == ErrorCode::kOk;
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("canRead"), flutter::EncodableValue(available)},
        {flutter::EncodableValue("canWrite"), flutter::EncodableValue(available)},
        {flutter::EncodableValue("canObserve"), flutter::EncodableValue(available)},
        {flutter::EncodableValue("writeSupport"),
         flutter::EncodableValue(available ? "bestEffort" : "unsupported")},
        {flutter::EncodableValue("supportedModes"),
         flutter::EncodableValue(flutter::EncodableList{
             flutter::EncodableValue("system")})},
        {flutter::EncodableValue("requiresWriteSettingsPermission"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("backend"),
         flutter::EncodableValue("windows-dxva2")},
    }));
    return;
  }

  BrightnessResult native_result{0, ErrorCode::kNativeFailure};
  if (operation == "getBrightness") {
    native_result = WithPhysicalMonitor(false);
  } else if (operation == "setBrightness") {
    const auto value = IntArgument(arguments, "value");
    if (!value || *value < 0 || *value > 100) {
      result->Error("invalid_brightness_value",
                    "Brightness must be between 0 and 100.",
                    ErrorDetails(operation));
      return;
    }
    native_result = WithPhysicalMonitor(true, *value);
  } else if (operation == "adjustBrightness") {
    const auto current = WithPhysicalMonitor(false);
    const std::string* direction = StringArgument(arguments, "direction");
    if (!direction || (*direction != "increase" && *direction != "decrease")) {
      result->Error("invalid_brightness_value", "Invalid adjustment direction.",
                    ErrorDetails(operation));
      return;
    }
    if (current.error == ErrorCode::kOk) {
      const int next = std::clamp(
          current.value + (*direction == "increase" ? 5 : -5), 0, 100);
      native_result = WithPhysicalMonitor(true, next);
    } else {
      native_result = current;
    }
  } else {
    result->NotImplemented();
    return;
  }

  if (native_result.error == ErrorCode::kOk) {
    result->Success(ValueResult(native_result.value));
    EmitCurrentBrightness();
  } else if (native_result.error == ErrorCode::kBackendNotAvailable) {
    result->Error("backend_not_available",
                  "No compatible primary Windows monitor is available.",
                  ErrorDetails(operation));
  } else {
    result->Error("native_backend_failure",
                  "The Windows monitor brightness operation failed.",
                  ErrorDetails(operation));
  }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
DeviceScreenBrightnessPlugin::OnListen(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  event_sink_ = std::move(events);
  last_emitted_value_ = -1;
  EmitCurrentBrightness();
  if (window_ && last_emitted_value_ >= 0) {
    timer_id_ = SetTimer(window_, kPollTimerId, 250, nullptr);
  }
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
DeviceScreenBrightnessPlugin::OnCancel(
    const flutter::EncodableValue* arguments) {
  if (timer_id_ != 0 && window_) KillTimer(window_, timer_id_);
  timer_id_ = 0;
  event_sink_.reset();
  last_emitted_value_ = -1;
  return nullptr;
}

void DeviceScreenBrightnessPlugin::EmitCurrentBrightness() {
  if (!event_sink_) return;
  const auto current = WithPhysicalMonitor(false);
  if (current.error != ErrorCode::kOk) {
    event_sink_->Error("brightness_observation_failure",
                       "Unable to read Windows monitor brightness.",
                       ErrorDetails("streamBrightness"));
    return;
  }
  if (current.value == last_emitted_value_) return;
  last_emitted_value_ = current.value;
  event_sink_->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("value"), flutter::EncodableValue(current.value)},
      {flutter::EncodableValue("mode"), flutter::EncodableValue("system")},
  }));
}

std::optional<LRESULT> DeviceScreenBrightnessPlugin::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == kPollTimerId) EmitCurrentBrightness();
  return std::nullopt;
}

}  // namespace device_screen_brightness
