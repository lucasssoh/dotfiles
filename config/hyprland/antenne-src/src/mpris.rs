//! Antenne as an MPRIS player, so the bar's media module shows the channel
//! (name, number and category, logo) and its controls work: play/pause,
//! next/previous change channel, Raise brings the TV to your workspace.
//! libmpv publishes nothing on its own, and the mpv-mpris plugin would
//! show "mpv" with next/previous walking an empty playlist.

use gtk4::gio;
use gtk4::glib::{self, prelude::ToVariant, Variant};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

const PATH: &str = "/org/mpris/MediaPlayer2";
const ROOT: &str = "org.mpris.MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

const XML: &str = r#"<node>
 <interface name="org.mpris.MediaPlayer2">
  <method name="Raise"/><method name="Quit"/>
  <property name="CanQuit" type="b" access="read"/>
  <property name="CanRaise" type="b" access="read"/>
  <property name="HasTrackList" type="b" access="read"/>
  <property name="Identity" type="s" access="read"/>
  <property name="DesktopEntry" type="s" access="read"/>
  <property name="SupportedUriSchemes" type="as" access="read"/>
  <property name="SupportedMimeTypes" type="as" access="read"/>
 </interface>
 <interface name="org.mpris.MediaPlayer2.Player">
  <method name="Next"/><method name="Previous"/><method name="Pause"/>
  <method name="PlayPause"/><method name="Stop"/><method name="Play"/>
  <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
  <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
  <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
  <signal name="Seeked"><arg name="Position" type="x"/></signal>
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Rate" type="d" access="read"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Volume" type="d" access="read"/>
  <property name="Position" type="x" access="read"/>
  <property name="MinimumRate" type="d" access="read"/>
  <property name="MaximumRate" type="d" access="read"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
 </interface>
</node>"#;

#[derive(Clone, Copy, Debug)]
pub enum Command {
    PlayPause,
    Play,
    Pause,
    Next,
    Previous,
    Raise,
    Quit,
}

#[derive(Default, Clone)]
struct Track {
    id: u64,
    title: String,
    artist: String,
    art: Option<String>,
}

pub struct Mpris {
    conn: RefCell<Option<gio::DBusConnection>>,
    track: RefCell<Track>,
    playing: Cell<bool>,
    pub on_command: RefCell<Option<Box<dyn Fn(Command)>>>,
}

impl Mpris {
    pub fn start() -> Rc<Self> {
        let me = Rc::new(Mpris {
            conn: RefCell::new(None),
            track: RefCell::new(Track::default()),
            playing: Cell::new(false),
            on_command: RefCell::new(None),
        });
        let Ok(conn) = gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE) else { return me };
        let Ok(node) = gio::DBusNodeInfo::for_xml(XML) else { return me };
        for name in [ROOT, PLAYER] {
            let Some(iface) = node.lookup_interface(name) else { continue };
            let call = Rc::downgrade(&me);
            let prop = Rc::downgrade(&me);
            let _ = conn
                .register_object(PATH, &iface)
                .method_call(move |_, _, _, _, method, _, invocation| {
                    let cmd = match method {
                        "PlayPause" => Some(Command::PlayPause),
                        "Play" => Some(Command::Play),
                        "Pause" | "Stop" => Some(Command::Pause),
                        "Next" => Some(Command::Next),
                        "Previous" => Some(Command::Previous),
                        "Raise" => Some(Command::Raise),
                        "Quit" => Some(Command::Quit),
                        _ => None,
                    };
                    invocation.return_value(None);
                    if let (Some(cmd), Some(me)) = (cmd, call.upgrade()) {
                        if let Some(f) = me.on_command.borrow().as_ref() {
                            f(cmd);
                        }
                    }
                })
                .property(move |_, _, _, _, property| match prop.upgrade() {
                    Some(me) => me.property(property),
                    None => false.to_variant(),
                })
                .build();
        }
        let _ = gio::bus_own_name_on_connection(&conn, "org.mpris.MediaPlayer2.antenne", gio::BusNameOwnerFlags::NONE, |_, _| {}, |_, _| {});
        *me.conn.borrow_mut() = Some(conn);
        me
    }

    fn metadata(&self) -> Variant {
        let t = self.track.borrow();
        let dict = glib::VariantDict::new(None);
        let id = format!("/io/github/lucasssoh/Antenne/track/{}", t.id);
        if let Ok(p) = glib::variant::ObjectPath::try_from(id) {
            dict.insert_value("mpris:trackid", &p.to_variant());
        }
        dict.insert_value("xesam:title", &t.title.to_variant());
        dict.insert_value("xesam:artist", &vec![t.artist.clone()].to_variant());
        if let Some(a) = &t.art {
            dict.insert_value("mpris:artUrl", &a.to_variant());
        }
        dict.end()
    }

    fn property(&self, name: &str) -> Variant {
        match name {
            "Identity" => "Antenne".to_variant(),
            "DesktopEntry" => "io.github.lucasssoh.Antenne".to_variant(),
            "SupportedUriSchemes" | "SupportedMimeTypes" => Vec::<String>::new().to_variant(),
            "PlaybackStatus" => (if self.playing.get() { "Playing" } else { "Paused" }).to_variant(),
            "Metadata" => self.metadata(),
            "Rate" | "MinimumRate" | "MaximumRate" | "Volume" => 1.0f64.to_variant(),
            "Position" => 0i64.to_variant(),
            "CanSeek" | "HasTrackList" => false.to_variant(),
            _ => true.to_variant(),
        }
    }

    fn changed(&self, props: &[&str]) {
        let Some(conn) = self.conn.borrow().clone() else { return };
        let map: HashMap<String, Variant> = props.iter().map(|p| (p.to_string(), self.property(p))).collect();
        let body = (PLAYER, map, Vec::<String>::new()).to_variant();
        let _ = conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged", Some(&body));
    }

    pub fn set_track(&self, title: &str, artist: &str, art: Option<String>) {
        {
            let mut t = self.track.borrow_mut();
            t.id += 1;
            t.title = title.to_string();
            t.artist = artist.to_string();
            t.art = art;
        }
        self.changed(&["Metadata"]);
    }

    pub fn set_art(&self, art: Option<String>) {
        self.track.borrow_mut().art = art;
        self.changed(&["Metadata"]);
    }

    pub fn set_playing(&self, playing: bool) {
        if self.playing.replace(playing) != playing {
            self.changed(&["PlaybackStatus"]);
        }
    }
}
