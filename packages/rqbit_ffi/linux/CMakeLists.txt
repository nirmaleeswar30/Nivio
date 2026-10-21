# Builds the Rust `rqbit_ffi` cdylib via cargo and bundles librqbit_ffi.so with
# the Flutter app so Dart FFI (DynamicLibrary.open('librqbit_ffi.so')) loads it.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "rqbit_ffi")
project(${PROJECT_NAME} LANGUAGES CXX)

set(rust_manifest "${CMAKE_CURRENT_SOURCE_DIR}/../rust/Cargo.toml")

if(NOT DEFINED RQBIT_CARGO_PROFILE)
  if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "Profile")
    set(RQBIT_CARGO_PROFILE "release")
  else()
    set(RQBIT_CARGO_PROFILE "debug")
  endif()
endif()
set(rust_out "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/${RQBIT_CARGO_PROFILE}/librqbit_ffi.so")

find_program(CARGO_EXE cargo
  HINTS "$ENV{HOME}/.cargo/bin" "$ENV{USERPROFILE}/.cargo/bin")
if(NOT CARGO_EXE)
  message(FATAL_ERROR
    "cargo not found. Install Rust (https://rustup.rs) to build rqbit_ffi.")
endif()

set(cargo_cmd "${CARGO_EXE}" build --manifest-path "${rust_manifest}")
if(RQBIT_CARGO_PROFILE STREQUAL "release")
  list(APPEND cargo_cmd --release)
endif()

add_custom_target(rqbit_ffi_rust ALL
  COMMAND ${cargo_cmd}
  BYPRODUCTS "${rust_out}"
  COMMENT "Building rqbit_ffi (librqbit) via cargo [${RQBIT_CARGO_PROFILE}]"
  USES_TERMINAL
  VERBATIM
)

set(rqbit_ffi_bundled_libraries
  "${rust_out}"
  PARENT_SCOPE
)
