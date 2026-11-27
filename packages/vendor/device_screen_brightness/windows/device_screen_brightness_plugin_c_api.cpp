#include "include/device_screen_brightness/device_screen_brightness_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "device_screen_brightness_plugin.h"

void DeviceScreenBrightnessPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  device_screen_brightness::DeviceScreenBrightnessPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
