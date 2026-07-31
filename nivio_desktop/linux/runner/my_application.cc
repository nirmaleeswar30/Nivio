#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "native_trailer_overlay.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void nivio_set_window_icon(GtkWindow* window) {
  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    return;
  }

  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  g_autofree gchar* icon_path =
      g_build_filename(executable_dir, "data", "resources", "app_icon.png",
                       nullptr);
  g_autoptr(GError) error = nullptr;
  gtk_window_set_icon_from_file(window, icon_path, &error);
}

static const gchar* nivio_event_type_name(GdkEventType type) {
  switch (type) {
    case GDK_BUTTON_PRESS:
      return "button-press";
    case GDK_BUTTON_RELEASE:
      return "button-release";
    case GDK_FOCUS_CHANGE:
      return "focus-change";
    case GDK_ENTER_NOTIFY:
      return "enter";
    case GDK_LEAVE_NOTIFY:
      return "leave";
    default:
      return "other";
  }
}

static const gchar* nivio_widget_type_from_event(GdkEvent* event) {
  if (event == nullptr || event->any.window == nullptr) {
    return "none";
  }
  gpointer user_data = nullptr;
  gdk_window_get_user_data(event->any.window, &user_data);
  if (user_data != nullptr && G_IS_OBJECT(user_data)) {
    return G_OBJECT_TYPE_NAME(user_data);
  }
  return "unknown";
}

static GdkFilterReturn nivio_global_event_filter(GdkXEvent*,
                                                 GdkEvent* event,
                                                 gpointer data) {
  if (event == nullptr) {
    return GDK_FILTER_CONTINUE;
  }
  if (event->type != GDK_BUTTON_PRESS &&
      event->type != GDK_BUTTON_RELEASE &&
      event->type != GDK_FOCUS_CHANGE) {
    return GDK_FILTER_CONTINUE;
  }

  GtkWindow* window = GTK_WINDOW(data);
  GtkWidget* focus = gtk_window_get_focus(window);
  const gchar* focus_type =
      focus == nullptr ? "none" : G_OBJECT_TYPE_NAME(focus);
  gdouble x_root = 0;
  gdouble y_root = 0;
  if (event->type == GDK_BUTTON_PRESS || event->type == GDK_BUTTON_RELEASE) {
    x_root = event->button.x_root;
    y_root = event->button.y_root;
  }

  g_print("[GTK] Pointer/focus event type=%s target=%s focus=%s "
          "x=%.1f y=%.1f\n",
          nivio_event_type_name(event->type),
          nivio_widget_type_from_event(event), focus_type, x_root, y_root);
  return GDK_FILTER_CONTINUE;
}

static gboolean nivio_view_focus_event(GtkWidget* widget,
                                       GdkEventFocus* event,
                                       gpointer) {
  g_print("[GTK] PlatformView focus widget=%s in=%d\n",
          G_OBJECT_TYPE_NAME(widget), event->in);
  return FALSE;
}

static gboolean nivio_widget_event(GtkWidget* widget, GdkEvent* event,
                                   gpointer data) {
  if (event == nullptr) {
    return FALSE;
  }
  if (event->type != GDK_BUTTON_PRESS &&
      event->type != GDK_BUTTON_RELEASE &&
      event->type != GDK_FOCUS_CHANGE) {
    return FALSE;
  }
  GtkWindow* window = GTK_WINDOW(data);
  GtkWidget* focus = gtk_window_get_focus(window);
  const gchar* focus_type =
      focus == nullptr ? "none" : G_OBJECT_TYPE_NAME(focus);
  gdouble x_root = 0;
  gdouble y_root = 0;
  if (event->type == GDK_BUTTON_PRESS || event->type == GDK_BUTTON_RELEASE) {
    x_root = event->button.x_root;
    y_root = event->button.y_root;
  }
  g_print("[GTK] Widget event receiver=%s type=%s target=%s focus=%s "
          "x=%.1f y=%.1f\n",
          G_OBJECT_TYPE_NAME(widget), nivio_event_type_name(event->type),
          nivio_widget_type_from_event(event), focus_type, x_root, y_root);
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  nivio_set_window_icon(window);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "nivio_desktop");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "nivio_desktop");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_set_hexpand(GTK_WIDGET(view), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(view), TRUE);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_widget_add_events(GTK_WIDGET(view), GDK_FOCUS_CHANGE_MASK |
                                      GDK_BUTTON_PRESS_MASK |
                                      GDK_BUTTON_RELEASE_MASK);
  g_signal_connect(view, "focus-in-event", G_CALLBACK(nivio_view_focus_event),
                   nullptr);
  g_signal_connect(view, "focus-out-event", G_CALLBACK(nivio_view_focus_event),
                   nullptr);
  g_signal_connect(view, "event", G_CALLBACK(nivio_widget_event), window);

  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_set_hexpand(overlay, TRUE);
  gtk_widget_set_vexpand(overlay, TRUE);
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);
  gtk_widget_add_events(GTK_WIDGET(window), GDK_FOCUS_CHANGE_MASK |
                                        GDK_BUTTON_PRESS_MASK |
                                        GDK_BUTTON_RELEASE_MASK);
  g_signal_connect(window, "event", G_CALLBACK(nivio_widget_event), window);
  gdk_window_add_filter(nullptr, nivio_global_event_filter, window);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  nivio_native_trailer_overlay_register(view, overlay);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
