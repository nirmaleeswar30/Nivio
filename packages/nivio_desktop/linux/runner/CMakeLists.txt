cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "hdr_video_host.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# True HDR video on Wayland (hdr_video_host.cc): libmpv's render API, a 10-bit
# EGL surface, and the Wayland colour-management and viewporter protocols
# (vendored in protocols/, client code generated with wayland-scanner).
# Without these the app still builds, and HDR video is tone-mapped to SDR.
pkg_check_modules(NIVIO_HDR IMPORTED_TARGET
  wayland-client wayland-egl egl mpv)
find_program(WAYLAND_SCANNER wayland-scanner)
if(NIVIO_HDR_FOUND AND WAYLAND_SCANNER)
  enable_language(C)
  set(NIVIO_PROTOCOL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/protocols")
  set(NIVIO_PROTOCOL_OUT "${CMAKE_CURRENT_BINARY_DIR}/protocols")
  file(MAKE_DIRECTORY "${NIVIO_PROTOCOL_OUT}")
  foreach(protocol color-management-v1 viewporter)
    set(xml "${NIVIO_PROTOCOL_DIR}/${protocol}.xml")
    add_custom_command(
      OUTPUT "${NIVIO_PROTOCOL_OUT}/${protocol}-client-protocol.h"
      COMMAND "${WAYLAND_SCANNER}" client-header "${xml}"
        "${NIVIO_PROTOCOL_OUT}/${protocol}-client-protocol.h"
      DEPENDS "${xml}")
    add_custom_command(
      OUTPUT "${NIVIO_PROTOCOL_OUT}/${protocol}-protocol.c"
      COMMAND "${WAYLAND_SCANNER}" private-code "${xml}"
        "${NIVIO_PROTOCOL_OUT}/${protocol}-protocol.c"
      DEPENDS "${xml}")
    target_sources(${BINARY_NAME} PRIVATE
      "${NIVIO_PROTOCOL_OUT}/${protocol}-client-protocol.h"
      "${NIVIO_PROTOCOL_OUT}/${protocol}-protocol.c")
  endforeach()
  target_include_directories(${BINARY_NAME} PRIVATE "${NIVIO_PROTOCOL_OUT}")
  target_compile_definitions(${BINARY_NAME} PRIVATE NIVIO_LINUX_HDR)
  target_compile_features(${BINARY_NAME} PRIVATE cxx_std_17)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::NIVIO_HDR)
else()
  message(WARNING "Building without true HDR video: needs wayland-client, "
    "wayland-egl, egl, mpv (development packages) and wayland-scanner.")
endif()
