# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(nivio LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "nivio")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode and suppress modern MSVC deprecation errors for legacy plugin headers
add_definitions(-DUNICODE -D_UNICODE -D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS -D_SILENCE_ALL_CXX17_DEPRECATION_WARNINGS -D_SILENCE_ALL_CXX20_DEPRECATION_WARNINGS)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# === Newer libmpv ===
# media_kit_libs_windows_video ships a 2023 libmpv (mpv 0.36) without the
# gpu-next renderer, so it can't output HDR. Replace it with a current build
# (installed after the plugin's copy, so it overwrites it). The client API is
# backwards compatible, so media_kit's import library still links against it.
#
# The archive is shinchiro/mpv-winbuild-cmake's 20261111 build (mpv 0.42),
# unmodified, re-hosted on our own release because shinchiro only keeps the
# last 30 daily builds. To move to a newer mpv: download and test a new build,
# upload it as a new release there, and update the URL and SHA-256 here.
set(NIVIO_LIBMPV_URL
  "https://github.com/nirmaleeswar30/mpvlibAndroid/releases/download/windows-libmpv-20261111/mpv-dev-x86_64-20261111-git-bcde6b93cc.7z")
set(NIVIO_LIBMPV_SHA256
  "273c079b11ea5575822f972756f4c9a71149a5c10130353abeb8586738938452")
set(NIVIO_LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/nivio-libmpv.7z")
set(NIVIO_LIBMPV_DIR "${CMAKE_BINARY_DIR}/nivio-libmpv-${NIVIO_LIBMPV_SHA256}")
if(NOT EXISTS "${NIVIO_LIBMPV_DIR}/libmpv-2.dll")
  message(STATUS "Downloading libmpv: ${NIVIO_LIBMPV_URL}")
  file(DOWNLOAD "${NIVIO_LIBMPV_URL}" "${NIVIO_LIBMPV_ARCHIVE}"
    EXPECTED_HASH SHA256=${NIVIO_LIBMPV_SHA256}
    SHOW_PROGRESS)
  file(MAKE_DIRECTORY "${NIVIO_LIBMPV_DIR}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${NIVIO_LIBMPV_ARCHIVE}"
    WORKING_DIRECTORY "${NIVIO_LIBMPV_DIR}"
    RESULT_VARIABLE NIVIO_LIBMPV_EXTRACT_RESULT)
  if(NOT NIVIO_LIBMPV_EXTRACT_RESULT EQUAL 0 OR NOT EXISTS "${NIVIO_LIBMPV_DIR}/libmpv-2.dll")
    message(FATAL_ERROR "Could not extract libmpv-2.dll from ${NIVIO_LIBMPV_ARCHIVE}")
  endif()
  file(REMOVE "${NIVIO_LIBMPV_ARCHIVE}")
endif()
install(FILES "${NIVIO_LIBMPV_DIR}/libmpv-2.dll"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
