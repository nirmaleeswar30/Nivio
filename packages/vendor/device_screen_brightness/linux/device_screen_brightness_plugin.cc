#include "include/device_screen_brightness/device_screen_brightness_plugin.h"

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <algorithm>
#include <string>

#define DEVICE_SCREEN_BRIGHTNESS_PLUGIN(obj)                              \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),                                     \
                              device_screen_brightness_plugin_get_type(), \
                              DeviceScreenBrightnessPlugin))

struct _DeviceScreenBrightnessPlugin {
  GObject parent_instance;
  FlEventChannel* event_channel;
  gchar* backlight_path;
  guint poll_source;
  gboolean emit_events;
  gint last_value;
};

G_DEFINE_TYPE(DeviceScreenBrightnessPlugin,
              device_screen_brightness_plugin,
              g_object_get_type())

namespace {

constexpr char kMethodChannel[] =
    "dev.arcas.device_screen_brightness/methods";
constexpr char kEventChannel[] =
    "dev.arcas.device_screen_brightness/events";

enum ErrorCode {
  kOk,
  kPermissionDenied,
  kNativeFailure,
  kInvalidValue,
  kBackendNotAvailable,
};

struct BrightnessResult {
  gint value;
  ErrorCode error;
};

int type_priority(const std::string& path) {
  FILE* file = fopen((path + "/type").c_str(), "r");
  if (!file) return 0;
  char buffer[32] = {};
  const bool read = fgets(buffer, sizeof(buffer), file) != nullptr;
  fclose(file);
  if (!read) return 0;
  buffer[strcspn(buffer, "\n")] = '\0';
  if (strcmp(buffer, "firmware") == 0) return 3;
  if (strcmp(buffer, "platform") == 0) return 2;
  if (strcmp(buffer, "raw") == 0) return 1;
  return 0;
}

gchar* find_backlight() {
  constexpr char base[] = "/sys/class/backlight";
  DIR* directory = opendir(base);
  if (!directory) return nullptr;
  std::string best;
  int best_priority = -1;
  while (dirent* entry = readdir(directory)) {
    if (entry->d_name[0] == '.') continue;
    const std::string candidate = std::string(base) + "/" + entry->d_name;
    const int priority = type_priority(candidate);
    if (priority > best_priority) {
      best_priority = priority;
      best = candidate;
    }
  }
  closedir(directory);
  return best.empty() ? nullptr : g_strdup(best.c_str());
}

int read_integer(const std::string& path) {
  FILE* file = fopen(path.c_str(), "r");
  if (!file) return -1;
  int value = -1;
  if (fscanf(file, "%d", &value) != 1) value = -1;
  fclose(file);
  return value;
}

BrightnessResult query(DeviceScreenBrightnessPlugin* self) {
  if (!self->backlight_path) return {0, kBackendNotAvailable};
  const std::string base(self->backlight_path);
  const int maximum = read_integer(base + "/max_brightness");
  const int current = read_integer(base + "/brightness");
  if (maximum <= 0 || current < 0) return {0, kNativeFailure};
  return {static_cast<gint>(static_cast<long long>(current) * 100 / maximum),
          kOk};
}

BrightnessResult write_brightness(DeviceScreenBrightnessPlugin* self,
                                  gint normalized) {
  if (normalized < 0 || normalized > 100) return {0, kInvalidValue};
  if (!self->backlight_path) return {0, kBackendNotAvailable};
  const std::string base(self->backlight_path);
  const int maximum = read_integer(base + "/max_brightness");
  if (maximum <= 0) return {0, kNativeFailure};
  FILE* file = fopen((base + "/brightness").c_str(), "w");
  if (!file) {
    return {0, errno == EACCES || errno == EPERM ? kPermissionDenied
                                                 : kNativeFailure};
  }
  const int native_value =
      static_cast<int>(static_cast<long long>(normalized) * maximum / 100);
  const bool written = fprintf(file, "%d", native_value) >= 0;
  const bool closed = fclose(file) == 0;
  if (!written || !closed) return {0, kNativeFailure};
  return query(self);
}

FlValue* details(const gchar* operation) {
  g_autoptr(FlValue) value = fl_value_new_map();
  fl_value_set_string_take(value, "platform", fl_value_new_string("linux"));
  fl_value_set_string_take(value, "operation", fl_value_new_string(operation));
  fl_value_set_string_take(value, "backend", fl_value_new_string("sysfs"));
  return g_steal_pointer(&value);
}

const gchar* error_code(ErrorCode error) {
  switch (error) {
    case kPermissionDenied:
      return "permission_denied";
    case kInvalidValue:
      return "invalid_brightness_value";
    case kBackendNotAvailable:
      return "backend_not_available";
    default:
      return "native_backend_failure";
  }
}

const gchar* error_message(ErrorCode error) {
  switch (error) {
    case kPermissionDenied:
      return "Linux denied access to the sysfs brightness file.";
    case kInvalidValue:
      return "Brightness must be between 0 and 100.";
    case kBackendNotAvailable:
      return "No Linux sysfs backlight device is available.";
    default:
      return "The Linux sysfs brightness backend failed.";
  }
}

FlMethodResponse* response_for(BrightnessResult native_result,
                               const gchar* operation) {
  if (native_result.error == kOk) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "value",
                             fl_value_new_int(native_result.value));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  g_autoptr(FlValue) error_details = details(operation);
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      error_code(native_result.error), error_message(native_result.error),
      error_details));
}

void emit_current(DeviceScreenBrightnessPlugin* self) {
  if (!self->emit_events) return;
  const BrightnessResult current = query(self);
  if (current.error != kOk) {
    g_autoptr(FlValue) error_details = details("streamBrightness");
    fl_event_channel_send_error(self->event_channel, error_code(current.error),
                                error_message(current.error), error_details,
                                nullptr, nullptr);
    return;
  }
  if (current.value == self->last_value) return;
  self->last_value = current.value;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "value", fl_value_new_int(current.value));
  fl_value_set_string_take(event, "mode", fl_value_new_string("system"));
  fl_event_channel_send(self->event_channel, event, nullptr, nullptr);
}

gboolean poll_cb(gpointer user_data) {
  emit_current(DEVICE_SCREEN_BRIGHTNESS_PLUGIN(user_data));
  return G_SOURCE_CONTINUE;
}

void handle_method_call(DeviceScreenBrightnessPlugin* self,
                        FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "hasPermission") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(TRUE)));
  } else if (strcmp(method, "requestPermission") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getCapabilities") == 0) {
    const BrightnessResult current = query(self);
    const gboolean available = current.error == kOk;
    const std::string brightness_path = self->backlight_path
                                            ? std::string(self->backlight_path) + "/brightness"
                                            : std::string();
    const gboolean writable =
        available && access(brightness_path.c_str(), W_OK) == 0;
    g_autoptr(FlValue) capabilities = fl_value_new_map();
    g_autoptr(FlValue) modes = fl_value_new_list();
    fl_value_append_take(modes, fl_value_new_string("system"));
    fl_value_set_string_take(capabilities, "canRead", fl_value_new_bool(available));
    fl_value_set_string_take(capabilities, "canWrite", fl_value_new_bool(writable));
    fl_value_set_string_take(capabilities, "canObserve", fl_value_new_bool(available));
    fl_value_set_string_take(capabilities, "writeSupport",
                             fl_value_new_string(writable ? "supported" : "unsupported"));
    fl_value_set_string_take(capabilities, "supportedModes", g_steal_pointer(&modes));
    fl_value_set_string_take(capabilities, "requiresWriteSettingsPermission",
                             fl_value_new_bool(FALSE));
    fl_value_set_string_take(capabilities, "backend", fl_value_new_string("linux-sysfs"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(capabilities));
  } else if (strcmp(method, "getBrightness") == 0) {
    response = response_for(query(self), method);
  } else if (strcmp(method, "setBrightness") == 0 ||
             strcmp(method, "adjustBrightness") == 0) {
    FlValue* arguments = fl_method_call_get_args(method_call);
    gint requested = -1;
    if (strcmp(method, "setBrightness") == 0) {
      FlValue* value = arguments ? fl_value_lookup_string(arguments, "value") : nullptr;
      if (value && fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
        requested = static_cast<gint>(fl_value_get_int(value));
      }
    } else {
      const BrightnessResult current = query(self);
      if (current.error != kOk) {
        response = response_for(current, method);
      } else {
        FlValue* direction_value =
            arguments ? fl_value_lookup_string(arguments, "direction") : nullptr;
        const gchar* direction = direction_value &&
                                         fl_value_get_type(direction_value) == FL_VALUE_TYPE_STRING
                                     ? fl_value_get_string(direction_value)
                                     : "";
        if (strcmp(direction, "increase") == 0) {
          requested = std::min(100, current.value + 5);
        } else if (strcmp(direction, "decrease") == 0) {
          requested = std::max(0, current.value - 5);
        }
      }
    }
    if (!response) response = response_for(write_brightness(self, requested), method);
    emit_current(self);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

void method_call_cb(FlMethodChannel* channel,
                    FlMethodCall* method_call,
                    gpointer user_data) {
  handle_method_call(DEVICE_SCREEN_BRIGHTNESS_PLUGIN(user_data), method_call);
}

FlMethodErrorResponse* event_listen_cb(FlEventChannel* channel,
                                       FlValue* arguments,
                                       gpointer user_data) {
  auto* self = DEVICE_SCREEN_BRIGHTNESS_PLUGIN(user_data);
  self->emit_events = TRUE;
  self->last_value = -1;
  emit_current(self);
  if (self->last_value >= 0 && self->poll_source == 0) {
    self->poll_source = g_timeout_add(250, poll_cb, self);
  }
  return nullptr;
}

FlMethodErrorResponse* event_cancel_cb(FlEventChannel* channel,
                                       FlValue* arguments,
                                       gpointer user_data) {
  auto* self = DEVICE_SCREEN_BRIGHTNESS_PLUGIN(user_data);
  self->emit_events = FALSE;
  self->last_value = -1;
  if (self->poll_source != 0) {
    g_source_remove(self->poll_source);
    self->poll_source = 0;
  }
  return nullptr;
}

}  // namespace

static void device_screen_brightness_plugin_dispose(GObject* object) {
  auto* self = DEVICE_SCREEN_BRIGHTNESS_PLUGIN(object);
  if (self->poll_source != 0) g_source_remove(self->poll_source);
  if (self->event_channel) {
    fl_event_channel_set_stream_handlers(self->event_channel, nullptr, nullptr,
                                         nullptr, nullptr);
  }
  g_clear_object(&self->event_channel);
  g_clear_pointer(&self->backlight_path, g_free);
  G_OBJECT_CLASS(device_screen_brightness_plugin_parent_class)->dispose(object);
}

static void device_screen_brightness_plugin_class_init(
    DeviceScreenBrightnessPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = device_screen_brightness_plugin_dispose;
}

static void device_screen_brightness_plugin_init(
    DeviceScreenBrightnessPlugin* self) {
  self->last_value = -1;
}

void device_screen_brightness_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* plugin = DEVICE_SCREEN_BRIGHTNESS_PLUGIN(
      g_object_new(device_screen_brightness_plugin_get_type(), nullptr));
  plugin->backlight_path = find_backlight();

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) method_channel = fl_method_channel_new(
      messenger, kMethodChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      method_channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  plugin->event_channel = fl_event_channel_new(
      messenger, kEventChannel, FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel, event_listen_cb,
                                       event_cancel_cb, plugin, nullptr);
  g_object_unref(plugin);
}
