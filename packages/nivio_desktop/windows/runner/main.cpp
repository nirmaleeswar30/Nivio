#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"
#include <app_links/app_links_plugin_c_api.h>

namespace {

// The startup window, in logical pixels: centred on the primary monitor's
// work area, 16:9, as large as 1920x1080 allows within 90% of that area. A
// fixed 1920x1080 is larger than a 1080p screen at 125% scaling (1536x864
// logical), which put the window at the top-left, partly off screen.
void InitialWindowBounds(Win32Window::Point& origin, Win32Window::Size& size) {
  HMONITOR monitor = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info)) return;
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const RECT& work = info.rcWork;
  const double work_width = (work.right - work.left) / scale;
  const double work_height = (work.bottom - work.top) / scale;

  double width = std::min(1920.0, work_width * 0.9);
  double height = width * 9.0 / 16.0;
  if (height > work_height * 0.9) {
    height = work_height * 0.9;
    width = height * 16.0 / 9.0;
  }
  // The primary monitor's work area starts at or near (0, 0).
  const double left = std::max(0.0, work.left / scale + (work_width - width) / 2);
  const double top = std::max(0.0, work.top / scale + (work_height - height) / 2);
  origin = Win32Window::Point(static_cast<unsigned int>(left),
                              static_cast<unsigned int>(top));
  size = Win32Window::Size(static_cast<unsigned int>(width),
                           static_cast<unsigned int>(height));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // If an instance of this app is already running, forward the link to it,
  // bring it to foreground, and exit this instance.
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // Skia reduces idle graphics memory on Windows.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  InitialWindowBounds(origin, size);
  if (!window.Create(L"nivio", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
