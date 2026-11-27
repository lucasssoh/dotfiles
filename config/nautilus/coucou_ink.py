"""coucou-shell in Nautilus, two things its CSS cannot do:

- Ink: the shell theme's sheet, read again whenever shell-theme.py sync
  rewrites it. GTK4 reads ~/.config/gtk-4.0/gtk.css only at startup, and
  only Nautilus needs these rules, so the sheet is loaded here.
- Disk gauges: under each place that is a whole disk (the home folder, a
  mounted drive), a bar of the space used, as Nemo had. Nautilus's sidebar
  has none. Rows are watched as they come and go, and the figures are read
  again when a window comes to the front, so nothing polls.
"""

import locale
import os

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Nautilus

STATE = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
SHEET = os.path.join(STATE, "coucou-shell", "theme", "nautilus-ink.css")
HOME_URI = Gio.File.new_for_path(GLib.get_home_dir()).get_uri()
FS_ATTRS = "filesystem::size,filesystem::free"
FRENCH = (locale.getlocale(locale.LC_MESSAGES)[0] or os.environ.get("LANG", "")).startswith("fr")


def children(widget):
    child = widget.get_first_child()
    while child is not None:
        yield child
        child = child.get_next_sibling()


def walk(widget):
    yield widget
    for child in children(widget):
        yield from walk(child)


def type_name(widget):
    return GObject.type_name(widget.__gtype__)


class CoucouInk(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()
        self.provider = Gtk.CssProvider()
        self.monitor = None
        self.gauges = {}          # row -> (uri, levelbar, holder)
        self.watched = set()      # list boxes and windows already followed
        GLib.idle_add(self.attach)

    # ---- the sheet -------------------------------------------------------
    def attach(self):
        display = Gdk.Display.get_default()
        if display is None:
            return True
        # Media queries in the sheet follow light and dark as gtk.css does.
        Gtk.Settings.get_for_display(display).bind_property(
            "gtk-interface-color-scheme", self.provider, "prefers-color-scheme",
            GObject.BindingFlags.SYNC_CREATE)
        Gtk.StyleContext.add_provider_for_display(
            display, self.provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        self.load()
        self.monitor = Gio.File.new_for_path(SHEET).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", lambda *_: self.load())

        toplevels = Gtk.Window.get_toplevels()
        toplevels.connect("items-changed", lambda model, *_: self.follow_windows(model))
        self.follow_windows(toplevels)
        return False

    def load(self):
        try:
            with open(SHEET, encoding="utf-8") as f:
                self.provider.load_from_string(f.read())
        except OSError:
            self.provider.load_from_string("")

    # ---- disk gauges -----------------------------------------------------
    def follow_windows(self, model):
        for i in range(model.get_n_items()):
            window = model.get_item(i)
            if window in self.watched:
                continue
            self.watched.add(window)
            window.connect("notify::is-active", self.on_active)
            # The sidebar is filled after the window is made.
            GLib.idle_add(self.follow_sidebar, window)

    def follow_sidebar(self, window):
        for widget in walk(window):
            if isinstance(widget, Gtk.ListBox) and any(
                    type_name(c) == "NautilusSidebarRow" for c in children(widget)):
                if widget not in self.watched:
                    self.watched.add(widget)
                    widget.observe_children().connect(
                        "items-changed", lambda *_, box=widget: GLib.idle_add(self.decorate, box))
                self.decorate(widget)
        return False

    def on_active(self, window, _pspec):
        if window.is_active():
            for row in list(self.gauges):
                self.refresh(row)

    def decorate(self, box):
        live = set()
        for row in children(box):
            if type_name(row) != "NautilusSidebarRow":
                continue
            uri = row.get_property("uri") or ""
            if not uri.startswith("file://"):
                continue
            if row.get_property("mount") is None and uri.rstrip("/") not in (HOME_URI.rstrip("/"), "file:"):
                continue
            live.add(row)
            if row not in self.gauges:
                self.add_gauge(row, uri)
        for row in [r for r in self.gauges if r.get_parent() is box and r not in live]:
            self.gauges.pop(row, None)
        return False

    def add_gauge(self, row, uri):
        revealer = row.get_child()
        line = revealer.get_child() if revealer is not None else None
        label = next((c for c in children(line) if isinstance(c, Gtk.Label)), None) if line else None
        if label is None:
            return
        holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                         valign=Gtk.Align.CENTER, hexpand=True)
        line.insert_child_after(holder, label)
        line.remove(label)
        holder.append(label)
        bar = Gtk.LevelBar(min_value=0, max_value=1, visible=False)
        for name in (Gtk.LEVEL_BAR_OFFSET_LOW, Gtk.LEVEL_BAR_OFFSET_HIGH, Gtk.LEVEL_BAR_OFFSET_FULL):
            bar.remove_offset_value(name)
        bar.add_css_class("coucou-gauge")
        holder.append(bar)
        self.gauges[row] = (uri, bar, holder)
        self.refresh(row)

    def refresh(self, row):
        uri, bar, holder = self.gauges[row]
        Gio.File.new_for_uri(uri).query_filesystem_info_async(
            FS_ATTRS, GLib.PRIORITY_LOW, None, self.on_info, (bar, holder))

    def on_info(self, gfile, result, widgets):
        bar, holder = widgets
        try:
            info = gfile.query_filesystem_info_finish(result)
        except GLib.Error:
            bar.set_visible(False)
            return
        size = info.get_attribute_uint64("filesystem::size")
        free = info.get_attribute_uint64("filesystem::free")
        if not size:
            bar.set_visible(False)
            return
        bar.set_value((size - free) / size)
        bar.set_visible(True)
        free_s, size_s = GLib.format_size(free), GLib.format_size(size)
        holder.set_tooltip_text(f"{free_s} libres sur {size_s}" if FRENCH else f"{free_s} free of {size_s}")

    def get_file_items(self, files):
        return []
