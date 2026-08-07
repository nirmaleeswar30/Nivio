#ifndef RUNNER_NATIVE_TRAILER_OVERLAY_H_
#define RUNNER_NATIVE_TRAILER_OVERLAY_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class NativeTrailerOverlay {
public:
  virtual ~NativeTrailerOverlay() = default;

  virtual bool HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam, LRESULT *result) = 0;
};

std::unique_ptr<NativeTrailerOverlay>
CreateNativeTrailerOverlay(HWND parent_window,
                           flutter::BinaryMessenger *messenger);

#endif // RUNNER_NATIVE_TRAILER_OVERLAY_H_
