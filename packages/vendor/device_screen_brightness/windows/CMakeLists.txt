cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "device_screen_brightness")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "device_screen_brightness_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/device_screen_brightness/device_screen_brightness_plugin_c_api.h"
  "device_screen_brightness_plugin_c_api.cpp"
  "device_screen_brightness_plugin.cpp"
  "device_screen_brightness_plugin.h"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  dxva2
  user32
)

set(device_screen_brightness_bundled_libraries "" PARENT_SCOPE)
