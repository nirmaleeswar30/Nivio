#include "native_trailer_overlay.h"

#include <webkit2/webkit2.h>

#include <cmath>
#include <cstring>
#include <string>

namespace {

constexpr char kChannelName[] = "nivio/native_trailer_preview";
constexpr char kPreviewOrigin[] = "https://nivio.local";
constexpr char kPreviewDocumentUrl[] = "https://nivio.local/trailer-preview.html";
constexpr int kMuteBadgeSize = 32;
constexpr int kMuteBadgeInset = 10;
constexpr int kTrailerBadgeGap = 8;
constexpr char kBlankHtml[] =
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head>"
    "<body style=\"margin:0;background:#000;\"></body></html>";

struct NativeTrailerOverlay;
gboolean window_button_press_cb(GtkWidget* widget,
                                GdkEventButton* event,
                                gpointer user_data);
gboolean trailer_scroll_cb(GtkWidget* widget,
                           GdkEventScroll* event,
                           gpointer user_data);

typedef struct _NivioFixedBin NivioFixedBin;
typedef struct _NivioFixedBinClass NivioFixedBinClass;

struct _NivioFixedBin {
  GtkBin parent_instance;
  gint width;
  gint height;
};

struct _NivioFixedBinClass {
  GtkBinClass parent_class;
};

G_DEFINE_TYPE(NivioFixedBin, nivio_fixed_bin, GTK_TYPE_BIN)

void nivio_fixed_bin_get_preferred_width(GtkWidget* widget,
                                         gint* minimum_width,
                                         gint* natural_width) {
  NivioFixedBin* self = reinterpret_cast<NivioFixedBin*>(widget);
  if (minimum_width != nullptr) {
    *minimum_width = self->width;
  }
  if (natural_width != nullptr) {
    *natural_width = self->width;
  }
}

void nivio_fixed_bin_get_preferred_height(GtkWidget* widget,
                                          gint* minimum_height,
                                          gint* natural_height) {
  NivioFixedBin* self = reinterpret_cast<NivioFixedBin*>(widget);
  if (minimum_height != nullptr) {
    *minimum_height = self->height;
  }
  if (natural_height != nullptr) {
    *natural_height = self->height;
  }
}

void nivio_fixed_bin_size_allocate(GtkWidget* widget,
                                   GtkAllocation* allocation) {
  NivioFixedBin* self = reinterpret_cast<NivioFixedBin*>(widget);
  GtkAllocation fixed = *allocation;
  fixed.width = self->width;
  fixed.height = self->height;
  gtk_widget_set_allocation(widget, &fixed);
  gtk_widget_set_clip(widget, &fixed);

  GtkWidget* child = gtk_bin_get_child(GTK_BIN(widget));
  if (child != nullptr && gtk_widget_get_visible(child)) {
    gtk_widget_size_allocate(child, &fixed);
  }
}

void nivio_fixed_bin_class_init(NivioFixedBinClass* klass) {
  GtkWidgetClass* widget_class = GTK_WIDGET_CLASS(klass);
  widget_class->get_preferred_width = nivio_fixed_bin_get_preferred_width;
  widget_class->get_preferred_height = nivio_fixed_bin_get_preferred_height;
  widget_class->size_allocate = nivio_fixed_bin_size_allocate;
}

void nivio_fixed_bin_init(NivioFixedBin* self) {
  self->width = 1;
  self->height = 1;
}

GtkWidget* nivio_fixed_bin_new() {
  return GTK_WIDGET(g_object_new(nivio_fixed_bin_get_type(), nullptr));
}

void nivio_fixed_bin_set_size(GtkWidget* widget, gint width, gint height) {
  NivioFixedBin* self = reinterpret_cast<NivioFixedBin*>(widget);
  self->width = width;
  self->height = height;
  gtk_widget_set_size_request(widget, width, height);
  gtk_widget_queue_resize(widget);
}

FlValue* map_lookup(FlValue* map, const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(map, key);
}

const gchar* map_lookup_string(FlValue* map, const gchar* key) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

gint64 map_lookup_int(FlValue* map, const gchar* key, gint64 fallback) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return fl_value_get_int(value);
}

double map_lookup_double(FlValue* map, const gchar* key, double fallback) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return fallback;
}

gboolean map_lookup_bool(FlValue* map, const gchar* key, gboolean fallback) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

void respond(FlMethodCall* method_call, FlMethodResponse* response) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send native trailer response: %s",
              error != nullptr ? error->message : "unknown");
  }
}

void respond_success(FlMethodCall* method_call, FlValue* value = nullptr) {
  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_success_response_new(value)));
}

void respond_error(FlMethodCall* method_call,
                   const gchar* code,
                   const gchar* message) {
  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(code, message,
                                                          nullptr)));
}

std::string html_escape(const char* text) {
  std::string escaped;
  if (text == nullptr) {
    return escaped;
  }
  for (const char* cursor = text; *cursor != '\0'; cursor++) {
    switch (*cursor) {
      case '&':
        escaped += "&amp;";
        break;
      case '<':
        escaped += "&lt;";
        break;
      case '>':
        escaped += "&gt;";
        break;
      case '"':
        escaped += "&quot;";
        break;
      case '\'':
        escaped += "&#39;";
        break;
      default:
        escaped += *cursor;
        break;
    }
  }
  return escaped;
}

std::string youtube_preview_html(const char* video_id) {
  std::string escaped_video_id = html_escape(video_id);
  std::string source = "https://www.youtube-nocookie.com/embed/" +
                       escaped_video_id +
                       "?autoplay=1&mute=1"
                       "&controls=0&enablejsapi=1&playsinline=1&fs=0"
                       "&iv_load_policy=3&rel=0&modestbranding=1&loop=1"
                       "&playlist=" + escaped_video_id +
                       "&origin=" + kPreviewOrigin;

  return std::string(R"(<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    * { margin: 0; padding: 0; overflow: hidden; }
    html, body { width: 100%; height: 100%; background: transparent; }
    body { position: relative; border-radius: 9px 9px 0 0; overflow: hidden; }
    #player { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe
    id="player"
    src=")") + source + R"("
    allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
    allowfullscreen
    referrerpolicy="strict-origin-when-cross-origin">
  </iframe>
  <script>
    document.body.dataset.ytReady = '0';
    document.body.dataset.ytPlaying = '0';
    document.body.dataset.ytError = '';
    document.body.dataset.ytPlayAttempts = '0';
    document.body.dataset.nivioMuted = '1';

    var tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    window.nivioPlayer = null;
    window.nivioSetMuted = function(muted) {
      document.body.dataset.nivioMuted = muted ? '1' : '0';
      try {
        if (window.nivioPlayer) {
          if (muted) {
            window.nivioPlayer.mute();
            window.nivioPlayer.setVolume(0);
          } else {
            window.nivioPlayer.unMute();
            window.nivioPlayer.setVolume(100);
          }
          window.nivioPlayer.playVideo();
        }
      } catch (error) {}
      try {
        var iframe = document.getElementById('player');
        if (iframe && iframe.contentWindow) {
          var post = function(func, args) {
            iframe.contentWindow.postMessage(JSON.stringify({
              event: 'command',
              func: func,
              args: args || []
            }), '*');
          };
          if (muted) {
            post('mute');
            post('setVolume', [0]);
          } else {
            post('unMute');
            post('setVolume', [100]);
          }
          post('playVideo');
        }
      } catch (error) {}
    };

    window.nivioForcePlay = function() {
      document.body.dataset.ytPlayAttempts = String(
        Number(document.body.dataset.ytPlayAttempts || '0') + 1
      );
      try {
        if (window.nivioPlayer) {
          if (document.body.dataset.nivioMuted !== '0') {
            window.nivioPlayer.mute();
            window.nivioPlayer.setVolume(0);
          }
          window.nivioPlayer.playVideo();
        }
      } catch (error) {}
      try {
        var iframe = document.getElementById('player');
        if (iframe && iframe.contentWindow) {
          var post = function(func, args) {
            iframe.contentWindow.postMessage(JSON.stringify({
              event: 'command',
              func: func,
              args: args || []
            }), '*');
          };
          if (document.body.dataset.nivioMuted !== '0') {
            post('mute');
            post('setVolume', [0]);
          }
          post('playVideo');
        }
      } catch (error) {}
    };

    window.nivioPlayTimer = window.setInterval(function() {
      if (document.body.dataset.ytPlaying === '1') {
        window.clearInterval(window.nivioPlayTimer);
        return;
      }
      window.nivioForcePlay();
    }, 350);

    function onYouTubeIframeAPIReady() {
      window.nivioPlayer = new YT.Player('player', {
        events: {
          onReady: function(event) {
            document.body.dataset.ytReady = '1';
            event.target.mute();
            event.target.setVolume(0);
            event.target.playVideo();
            window.nivioForcePlay();
          },
          onStateChange: function(event) {
            if (event.data === 1) {
              document.body.dataset.ytPlaying = '1';
              window.clearInterval(window.nivioPlayTimer);
            }
            if (event.data === 0) {
              event.target.seekTo(0);
              event.target.playVideo();
            }
            if (document.body.dataset.nivioMuted !== '0') {
              event.target.mute();
              event.target.setVolume(0);
            }
          },
          onError: function(event) {
            document.body.dataset.ytError = String(event.data || 'unknown');
          }
        }
      });
    }
  </script>
</body>
</html>
)";
}

struct NativeTrailerOverlay {
  GtkWidget* overlay = nullptr;
  GtkWidget* web_host = nullptr;
  GtkWidget* web_view = nullptr;
  GtkWidget* mute_badge = nullptr;
  GtkWidget* mute_icon = nullptr;
  GtkWidget* close_badge = nullptr;
  GtkWidget* close_icon = nullptr;
  GtkWidget* toplevel = nullptr;
  FlMethodChannel* channel = nullptr;
  int active_token = 0;
  bool muted = true;
  bool show_close_button = false;
  std::string loaded_video_id;

  explicit NativeTrailerOverlay(GtkWidget* overlay_widget)
      : overlay(overlay_widget) {}

  void ensure_web_view() {
    if (web_view != nullptr) {
      return;
    }
    toplevel = gtk_widget_get_toplevel(overlay);

    web_host = nivio_fixed_bin_new();
    gtk_widget_set_name(web_host, "nivio-native-trailer-host");
    gtk_widget_set_can_focus(web_host, FALSE);
    gtk_widget_set_focus_on_click(web_host, FALSE);
    gtk_widget_set_halign(web_host, GTK_ALIGN_START);
    gtk_widget_set_valign(web_host, GTK_ALIGN_START);
    gtk_widget_set_no_show_all(web_host, TRUE);
    gtk_widget_add_events(web_host, GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK);
    g_signal_connect(web_host, "scroll-event", G_CALLBACK(trailer_scroll_cb),
                     this);

    web_view = webkit_web_view_new();
    gtk_widget_set_name(web_view, "nivio-native-trailer-preview");
    gtk_widget_set_can_focus(web_view, FALSE);
    gtk_widget_set_focus_on_click(web_view, FALSE);
    gtk_widget_set_hexpand(web_view, FALSE);
    gtk_widget_set_vexpand(web_view, FALSE);
    gtk_widget_add_events(web_view, GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK);
    g_signal_connect(web_view, "scroll-event", G_CALLBACK(trailer_scroll_cb),
                     this);

    WebKitSettings* settings =
        webkit_web_view_get_settings(WEBKIT_WEB_VIEW(web_view));
    webkit_settings_set_enable_javascript(settings, TRUE);
    webkit_settings_set_media_playback_requires_user_gesture(settings, FALSE);
    webkit_settings_set_media_playback_allows_inline(settings, TRUE);
    webkit_settings_set_user_agent(
        settings,
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    GdkRGBA transparent = {0, 0, 0, 0};
    webkit_web_view_set_background_color(WEBKIT_WEB_VIEW(web_view),
                                         &transparent);

    gtk_container_add(GTK_CONTAINER(web_host), web_view);
    gtk_widget_show(web_view);
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), web_host);
    gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(overlay), web_host, TRUE);
    gtk_widget_set_opacity(web_host, 0.0);

    mute_badge = gtk_event_box_new();
    gtk_widget_set_name(mute_badge, "nivio-native-trailer-mute-badge");
    gtk_widget_set_can_focus(mute_badge, FALSE);
    gtk_widget_set_focus_on_click(mute_badge, FALSE);
    gtk_widget_set_halign(mute_badge, GTK_ALIGN_START);
    gtk_widget_set_valign(mute_badge, GTK_ALIGN_START);
    gtk_widget_set_no_show_all(mute_badge, TRUE);
    gtk_widget_set_size_request(mute_badge, kMuteBadgeSize, kMuteBadgeSize);

    GtkWidget* mute_icon =
        gtk_image_new_from_icon_name("audio-volume-muted-symbolic",
                                     GTK_ICON_SIZE_MENU);
    this->mute_icon = mute_icon;
    gtk_widget_show(this->mute_icon);
    gtk_container_add(GTK_CONTAINER(mute_badge), this->mute_icon);

    close_badge = gtk_event_box_new();
    gtk_widget_set_name(close_badge, "nivio-native-trailer-close-badge");
    gtk_widget_set_can_focus(close_badge, FALSE);
    gtk_widget_set_focus_on_click(close_badge, FALSE);
    gtk_widget_set_halign(close_badge, GTK_ALIGN_START);
    gtk_widget_set_valign(close_badge, GTK_ALIGN_START);
    gtk_widget_set_no_show_all(close_badge, TRUE);
    gtk_widget_set_size_request(close_badge, kMuteBadgeSize, kMuteBadgeSize);

    GtkWidget* close_icon =
        gtk_image_new_from_icon_name("window-close-symbolic",
                                     GTK_ICON_SIZE_MENU);
    this->close_icon = close_icon;
    gtk_widget_show(this->close_icon);
    gtk_container_add(GTK_CONTAINER(close_badge), this->close_icon);

    GtkCssProvider* provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(
        provider,
        "#nivio-native-trailer-mute-badge,"
        "#nivio-native-trailer-close-badge {"
        "background-color: rgba(0,0,0,0.68);"
        "border-radius: 16px;"
        "}"
        "#nivio-native-trailer-mute-badge image,"
        "#nivio-native-trailer-close-badge image {"
        "color: #ffffff;"
        "}",
        -1, nullptr);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(mute_badge),
        GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(close_badge),
        GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);

    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), mute_badge);
    gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(overlay), mute_badge,
                                         TRUE);
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), close_badge);
    gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(overlay), close_badge,
                                         TRUE);

    if (GTK_IS_WIDGET(toplevel)) {
      gtk_widget_add_events(toplevel, GDK_BUTTON_PRESS_MASK);
      g_signal_connect(toplevel, "button-press-event",
                       G_CALLBACK(window_button_press_cb), this);
    }
  }

  bool token_matches(int token) const {
    return token != 0 && token == active_token;
  }

  void update_rect(FlValue* args) {
    ensure_web_view();
    double x = map_lookup_double(args, "x", 0);
    double y = map_lookup_double(args, "y", 0);
    double width = map_lookup_double(args, "width", 0);
    double height = map_lookup_double(args, "height", 0);
    show_close_button = map_lookup_bool(args, "showCloseButton", FALSE);

    gint left = static_cast<gint>(std::round(x));
    gint top = static_cast<gint>(std::round(y));
    gint request_width = static_cast<gint>(std::round(width));
    gint request_height = static_cast<gint>(std::round(height));

    if (request_width <= 1 || request_height <= 1) {
      gtk_widget_set_opacity(web_host, 0.0);
      if (mute_badge != nullptr) {
        gtk_widget_hide(mute_badge);
      }
      if (close_badge != nullptr) {
        gtk_widget_hide(close_badge);
      }
      return;
    }

    gtk_widget_set_margin_start(web_host, left);
    gtk_widget_set_margin_top(web_host, top);
    nivio_fixed_bin_set_size(web_host, request_width, request_height);
    gtk_widget_set_size_request(web_view, request_width, request_height);

    if (mute_badge != nullptr) {
      gint badge_left =
          left + request_width - kMuteBadgeSize - kMuteBadgeInset;
      gtk_widget_set_margin_start(mute_badge,
                                  badge_left > left ? badge_left : left);
      gtk_widget_set_margin_top(mute_badge, top + kMuteBadgeInset);
      gtk_widget_set_size_request(mute_badge, kMuteBadgeSize, kMuteBadgeSize);
    }
    if (close_badge != nullptr) {
      gint close_left = left + request_width - (kMuteBadgeSize * 2) -
                        kMuteBadgeInset - kTrailerBadgeGap;
      gtk_widget_set_margin_start(close_badge,
                                  close_left > left ? close_left : left);
      gtk_widget_set_margin_top(close_badge, top + kMuteBadgeInset);
      gtk_widget_set_size_request(close_badge, kMuteBadgeSize, kMuteBadgeSize);
    }
  }

  void hide(bool clear_page) {
    if (web_host == nullptr || web_view == nullptr) {
      return;
    }
    gtk_widget_set_opacity(web_host, 0.0);
    gtk_widget_hide(web_host);
    if (mute_badge != nullptr) {
      gtk_widget_hide(mute_badge);
    }
    if (close_badge != nullptr) {
      gtk_widget_hide(close_badge);
    }
    loaded_video_id.clear();
    if (clear_page) {
      webkit_web_view_load_html(WEBKIT_WEB_VIEW(web_view), kBlankHtml,
                                kPreviewDocumentUrl);
    }
  }

  void set_muted(bool value) {
    muted = value;
    if (mute_icon != nullptr) {
      gtk_image_set_from_icon_name(
          GTK_IMAGE(mute_icon),
          muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic",
          GTK_ICON_SIZE_MENU);
    }
    if (web_view == nullptr || loaded_video_id.empty()) {
      return;
    }
    const gchar* script = muted
        ? "(function(){if(window.nivioSetMuted) window.nivioSetMuted(true);"
          "return '1';})();"
        : "(function(){if(window.nivioSetMuted) window.nivioSetMuted(false);"
          "return '1';})();";
    webkit_web_view_evaluate_javascript(WEBKIT_WEB_VIEW(web_view), script, -1,
                                        nullptr, nullptr, nullptr, nullptr,
                                        nullptr);
  }

  bool is_root_point_inside_badge(GtkWidget* badge,
                                  gdouble x_root,
                                  gdouble y_root) {
    if (badge == nullptr || toplevel == nullptr ||
        !gtk_widget_get_visible(badge) || !gtk_widget_get_mapped(badge)) {
      return false;
    }

    GdkWindow* window = gtk_widget_get_window(toplevel);
    if (window == nullptr) {
      return false;
    }

    gint window_x = 0;
    gint window_y = 0;
    gdk_window_get_origin(window, &window_x, &window_y);

    gint badge_x = 0;
    gint badge_y = 0;
    if (!gtk_widget_translate_coordinates(badge, toplevel, 0, 0,
                                          &badge_x, &badge_y)) {
      return false;
    }

    GtkAllocation allocation;
    gtk_widget_get_allocation(badge, &allocation);
    const gdouble local_x = x_root - window_x;
    const gdouble local_y = y_root - window_y;
    return local_x >= badge_x && local_x <= badge_x + allocation.width &&
           local_y >= badge_y && local_y <= badge_y + allocation.height;
  }

  bool is_root_point_inside_mute_badge(gdouble x_root, gdouble y_root) {
    return is_root_point_inside_badge(mute_badge, x_root, y_root);
  }

  bool is_root_point_inside_close_badge(gdouble x_root, gdouble y_root) {
    return is_root_point_inside_badge(close_badge, x_root, y_root);
  }

  void request_close() {
    if (channel == nullptr) {
      return;
    }
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "token", fl_value_new_int(active_token));
    fl_method_channel_invoke_method(channel, "nativeClose", args, nullptr,
                                    nullptr, nullptr);
  }
};

gboolean window_button_press_cb(GtkWidget*,
                                GdkEventButton* event,
                                gpointer user_data) {
  if (event != nullptr && event->button != 1) {
    return FALSE;
  }
  NativeTrailerOverlay* controller =
      static_cast<NativeTrailerOverlay*>(user_data);
  if (event == nullptr) {
    return FALSE;
  }
  if (controller->is_root_point_inside_close_badge(event->x_root,
                                                  event->y_root)) {
    controller->request_close();
    return TRUE;
  }
  if (!controller->is_root_point_inside_mute_badge(event->x_root,
                                                  event->y_root)) {
    return FALSE;
  }
  controller->set_muted(!controller->muted);
  return TRUE;
}

gboolean trailer_scroll_cb(GtkWidget*, GdkEventScroll* event, gpointer user_data) {
  NativeTrailerOverlay* controller =
      static_cast<NativeTrailerOverlay*>(user_data);
  if (controller == nullptr || controller->channel == nullptr ||
      event == nullptr) {
    return FALSE;
  }

  double dx = 0.0;
  double dy = 0.0;
  if (event->direction == GDK_SCROLL_SMOOTH) {
    constexpr double kSmoothScrollScale = 80.0;
    dx = event->delta_x * kSmoothScrollScale;
    dy = event->delta_y * kSmoothScrollScale;
  } else if (event->direction == GDK_SCROLL_UP) {
    dy = -72.0;
  } else if (event->direction == GDK_SCROLL_DOWN) {
    dy = 72.0;
  } else if (event->direction == GDK_SCROLL_LEFT) {
    dx = -72.0;
  } else if (event->direction == GDK_SCROLL_RIGHT) {
    dx = 72.0;
  }

  if (dx == 0.0 && dy == 0.0) {
    return FALSE;
  }

  double x = event->x_root;
  double y = event->y_root;
  if (controller->toplevel != nullptr) {
    GdkWindow* window = gtk_widget_get_window(controller->toplevel);
    if (window != nullptr) {
      gint window_x = 0;
      gint window_y = 0;
      gdk_window_get_origin(window, &window_x, &window_y);
      x -= window_x;
      y -= window_y;
    }
  }

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "dx", fl_value_new_float(dx));
  fl_value_set_string_take(args, "dy", fl_value_new_float(dy));
  fl_value_set_string_take(args, "x", fl_value_new_float(x));
  fl_value_set_string_take(args, "y", fl_value_new_float(y));
  fl_method_channel_invoke_method(controller->channel, "nativeScroll", args,
                                  nullptr, nullptr, nullptr);
  return TRUE;
}

FlValue* serialize_js_result(JSCValue* value) {
  if (value == nullptr || jsc_value_is_null(value) ||
      jsc_value_is_undefined(value)) {
    return fl_value_new_null();
  }
  if (jsc_value_is_boolean(value)) {
    return fl_value_new_bool(jsc_value_to_boolean(value));
  }
  if (jsc_value_is_number(value)) {
    return fl_value_new_float(jsc_value_to_double(value));
  }
  gchar* text = jsc_value_to_string(value);
  FlValue* result = fl_value_new_string(text != nullptr ? text : "");
  g_free(text);
  return result;
}

void status_finished_cb(GObject* object, GAsyncResult* result, gpointer data) {
  FlMethodCall* method_call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  JSCValue* value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr) {
    respond_error(method_call, "javascript_error", error->message);
    g_object_unref(method_call);
    return;
  }

  FlValue* payload = serialize_js_result(value);
  if (value != nullptr) {
    g_object_unref(value);
  }
  respond_success(method_call, payload);
  g_object_unref(method_call);
}

void method_call_cb(FlMethodChannel*,
                    FlMethodCall* method_call,
                    gpointer user_data) {
  NativeTrailerOverlay* controller =
      static_cast<NativeTrailerOverlay*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (std::strcmp(method, "prepare") == 0) {
    controller->active_token =
        static_cast<int>(map_lookup_int(args, "token", 0));
    controller->ensure_web_view();
    respond_success(method_call, fl_value_new_bool(TRUE));
    return;
  }

  if (std::strcmp(method, "show") == 0) {
    int token = static_cast<int>(map_lookup_int(args, "token", 0));
    if (!controller->token_matches(token)) {
      respond_success(method_call, fl_value_new_bool(FALSE));
      return;
    }

    const gchar* video_id = map_lookup_string(args, "videoId");
    if (video_id == nullptr || std::strlen(video_id) == 0) {
      respond_error(method_call, "invalid_video", "videoId is required");
      return;
    }

    controller->update_rect(args);
    if (controller->loaded_video_id != video_id) {
      controller->set_muted(true);
      std::string html = youtube_preview_html(video_id);
      webkit_web_view_load_html(WEBKIT_WEB_VIEW(controller->web_view),
                                html.c_str(), kPreviewDocumentUrl);
      controller->loaded_video_id = video_id;
    }
    gtk_widget_show(controller->web_host);
    bool visible = map_lookup_bool(args, "visible", FALSE);
    gtk_widget_set_opacity(controller->web_host, visible ? 1.0 : 0.0);
    if (controller->mute_badge != nullptr) {
      if (visible) {
        gtk_widget_show(controller->mute_badge);
      } else {
        gtk_widget_hide(controller->mute_badge);
      }
    }
    if (controller->close_badge != nullptr && visible &&
        controller->show_close_button) {
      gtk_widget_show(controller->close_badge);
    } else if (controller->close_badge != nullptr) {
      gtk_widget_hide(controller->close_badge);
    }
    respond_success(method_call, fl_value_new_bool(TRUE));
    return;
  }

  if (std::strcmp(method, "updateRect") == 0) {
    int token = static_cast<int>(map_lookup_int(args, "token", 0));
    if (controller->token_matches(token)) {
      controller->update_rect(args);
    }
    respond_success(method_call);
    return;
  }

  if (std::strcmp(method, "setVisible") == 0) {
    int token = static_cast<int>(map_lookup_int(args, "token", 0));
    if (controller->token_matches(token) && controller->web_host != nullptr) {
      bool visible = map_lookup_bool(args, "visible", FALSE);
      gtk_widget_set_opacity(
          controller->web_host, visible ? 1.0 : 0.0);
      if (visible) {
        gtk_widget_show(controller->web_host);
        if (controller->mute_badge != nullptr) {
          gtk_widget_show(controller->mute_badge);
        }
        if (controller->close_badge != nullptr &&
            controller->show_close_button) {
          gtk_widget_show(controller->close_badge);
        }
      } else {
        if (controller->mute_badge != nullptr) {
          gtk_widget_hide(controller->mute_badge);
        }
        if (controller->close_badge != nullptr) {
          gtk_widget_hide(controller->close_badge);
        }
      }
    }
    respond_success(method_call);
    return;
  }

  if (std::strcmp(method, "status") == 0) {
    int token = static_cast<int>(map_lookup_int(args, "token", 0));
    if (!controller->token_matches(token) || controller->web_view == nullptr ||
        controller->loaded_video_id.empty()) {
      respond_success(method_call);
      return;
    }
    const gchar* script =
        "(function(){"
        "if(window.nivioForcePlay) window.nivioForcePlay();"
        "return JSON.stringify({"
        "ready:document.body.dataset.ytReady==='1',"
        "playing:document.body.dataset.ytPlaying==='1',"
        "error:document.body.dataset.ytError||''"
        "});})();";
    g_object_ref(method_call);
    webkit_web_view_evaluate_javascript(WEBKIT_WEB_VIEW(controller->web_view),
                                        script, -1, nullptr, nullptr, nullptr,
                                        status_finished_cb, method_call);
    return;
  }

  if (std::strcmp(method, "hide") == 0) {
    int token = static_cast<int>(map_lookup_int(args, "token", 0));
    if (token == 0 || controller->token_matches(token)) {
      controller->hide(TRUE);
    }
    respond_success(method_call);
    return;
  }

  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

}  // namespace

void nivio_native_trailer_overlay_register(FlView* view, GtkWidget* overlay) {
  NativeTrailerOverlay* controller = new NativeTrailerOverlay(overlay);
  g_object_set_data_full(G_OBJECT(view), "nivio-native-trailer-overlay",
                         controller,
                         [](gpointer data) {
                           delete static_cast<NativeTrailerOverlay*>(data);
                         });

  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, kChannelName, FL_METHOD_CODEC(codec));
  controller->channel = channel;
  fl_method_channel_set_method_call_handler(channel, method_call_cb, controller,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(view), "nivio-native-trailer-channel",
                         channel, g_object_unref);
}
