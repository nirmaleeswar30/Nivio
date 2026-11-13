#ifndef RUNNER_HDR_VIDEO_HOST_H_
#define RUNNER_HDR_VIDEO_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <memory>

// True HDR video on Linux (Wayland).
//
// Flutter composites everything (media_kit's video texture included) as 8-bit
// SDR, so HDR video can't go through it. mpv can't embed its own window on
// Wayland (--wid is X11 / Windows only), so here Nivio renders the video
// itself: it takes over mpv's render context (media_kit's is released first,
// see lib/widgets/linux_hdr_video_surface.dart), and a render thread draws
// mpv's PQ / BT.2020 output into a 10-bit EGL surface. That surface is a
// Wayland subsurface placed just below the app window's surface, tagged as
// HDR10 with the colour-management protocol, and the app window turns
// see-through over it, so Flutter's controls and subtitles draw on top. The
// compositor (KDE Plasma 6, GNOME 48+, Hyprland, ...) then shows the video in
// HDR and the UI in SDR.
//
// Needs the compositor's HDR mode on for the screen. NIVIO_FORCE_HDR=1 in the
// environment treats every screen as HDR (the compositor then tone-maps the
// video), to test this path on an SDR screen.
//
// Dart side: lib/widgets/linux_hdr_video_surface.dart and
// AppPlatform.hdrDisplay, over the "com.nivio/hdr_window" channel.
class HdrVideoHost {
 public:
  HdrVideoHost(GtkWindow* window, FlView* view);
  ~HdrVideoHost();

  HdrVideoHost(const HdrVideoHost&) = delete;
  HdrVideoHost& operator=(const HdrVideoHost&) = delete;

  struct State;

 private:
  std::unique_ptr<State> state_;
};

#endif  // RUNNER_HDR_VIDEO_HOST_H_
