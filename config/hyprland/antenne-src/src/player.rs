//! libmpv drawing into a GtkGLArea through mpv's render API.
//!
//! Measured on battery before writing this (1080p50, internal screen):
//! mpv's own gpu-next window drew 0.3-0.4 W less than vo=dmabuf-wayland,
//! because mpv converts frames to RGB for the compositor, which composes
//! them anyway. So the frames go through GL here, as in mpv itself.

use gtk4::glib;
use gtk4::prelude::*;
use libmpv2::render::{OpenGLInitParams, RenderContext, RenderParam, RenderParamApiType};
use libmpv2::Mpv;
use std::cell::RefCell;
use std::ffi::{c_char, c_void, CString};
use std::rc::Rc;
use std::sync::OnceLock;

type GetProc = unsafe extern "C" fn(*const c_char) -> *mut c_void;
type GetIntegerv = unsafe extern "C" fn(u32, *mut i32);
const GL_FRAMEBUFFER_BINDING: u32 = 0x8CA6;

/// GTK uses EGL on Wayland; libmpv resolves its GL functions through it.
fn egl_proc(name: &str) -> *mut c_void {
    static EGL: OnceLock<Option<libloading::Library>> = OnceLock::new();
    let Some(lib) = EGL.get_or_init(|| unsafe { libloading::Library::new("libEGL.so.1").ok() }) else {
        return std::ptr::null_mut();
    };
    let Ok(f) = (unsafe { lib.get::<GetProc>(b"eglGetProcAddress\0") }) else { return std::ptr::null_mut() };
    let Ok(c) = CString::new(name) else { return std::ptr::null_mut() };
    unsafe { f(c.as_ptr()) }
}

fn get_proc(_: &(), name: &str) -> *mut c_void {
    egl_proc(name)
}

extern "C" {
    fn gdk_wayland_display_get_wl_display(display: *mut c_void) -> *mut c_void;
    fn setlocale(category: i32, locale: *const c_char) -> *mut c_char;
}

/// What Antenne listens to from mpv.
pub enum MpvEvent {
    Restart,
    Failed,
    /// The end of the file: the end of a recording, or a live stream cut.
    Ended,
    Reconfig,
    /// Waiting for the network (true), or playing again (false).
    Stall(bool),
    /// What yt-dlp said when it could not find the video.
    Error(String),
}

pub struct Player {
    pub mpv: RefCell<Mpv>,
    render: RefCell<Option<RenderContext>>,
    pub area: gtk4::GLArea,
    /// The HLS quality asked for normally (around 720p on battery).
    base_bitrate: &'static str,
}

impl Player {
    pub fn new(on_battery: bool) -> Result<Rc<Self>, libmpv2::Error> {
        // libmpv refuses to start under a locale whose decimal separator is
        // not "." (mpv_create returns NULL), and GTK has just set the
        // user's (fr_FR: ","). Numbers only; text keeps the user's locale.
        const LC_NUMERIC: i32 = 1;
        unsafe { setlocale(LC_NUMERIC, c"C".as_ptr()) };
        let mpv = Mpv::with_initializer(|i| {
            i.set_property("vo", "libmpv")?;
            i.set_property("hwdec", "auto-safe")?;
            // Render as soon as a frame is ready instead of blocking GTK's
            // main loop until the frame's display time.
            i.set_property("video-timing-offset", 0i64)?;
            i.set_property("terminal", false)?;
            i.set_property("input-default-bindings", false)?;
            i.set_property("osc", false)?;
            // mpv's own bar and messages over the picture: Antenne draws its own
            i.set_property("osd-level", 0i64)?;
            i.set_property("osd-bar", false)?;
            // a web page: mpv opens what it can itself, and asks yt-dlp for
            // the video only when it cannot (never for a channel's stream)
            i.set_property("ytdl", true)?;
            i.set_property("ytdl-format", if on_battery { "bv*[height<=720]+ba/b[height<=720]/b" } else { "bv*[height<=1080]+ba/b[height<=1080]/b" })?;
            i.set_property("idle", "yes")?;
            i.set_property("keep-open", "no")?;
            i.set_property("audio-client-name", "Antenne")?;
            i.set_property("network-timeout", 8i64)?;
            i.set_property("demuxer-max-bytes", "48MiB")?;
            i.set_property("hls-bitrate", if on_battery { "3000000" } else { "max" })?;
            Ok(())
        })?;
        // mpv says when it is waiting for the network: the stalls behind the
        // "weak connection" cue.
        let _ = mpv.event_context().observe_property("paused-for-cache", libmpv2::Format::Flag, 1);
        // warnings and errors come as events: yt-dlp's reason for a failure is among them
        unsafe {
            libmpv2_sys::mpv_request_log_messages(mpv.ctx.as_ptr(), c"warn".as_ptr());
        }
        let area = gtk4::GLArea::new();
        area.set_hexpand(true);
        area.set_vexpand(true);
        let base_bitrate = if on_battery { "3000000" } else { "max" };
        let player = Rc::new(Player { mpv: RefCell::new(mpv), render: RefCell::new(None), area: area.clone(), base_bitrate });

        let p = player.clone();
        area.connect_realize(move |area| {
            area.make_current();
            if let Some(e) = area.error() {
                eprintln!("antenne: no GL context: {e}");
                return;
            }
            let mut params = vec![
                RenderParam::ApiType(RenderParamApiType::OpenGl),
                RenderParam::InitParams(OpenGLInitParams { get_proc_address: get_proc, ctx: () }),
            ];
            // The Wayland display lets mpv hand VA-API frames to GL without a copy.
            let display = area.display();
            if display.type_().name() == "GdkWaylandDisplay" {
                let wl = unsafe { gdk_wayland_display_get_wl_display(display.as_ptr() as *mut c_void) };
                if !wl.is_null() {
                    params.push(RenderParam::WaylandDisplay(wl as *const c_void));
                }
            }
            let mpv = p.mpv.borrow_mut();
            match RenderContext::new(unsafe { &mut *mpv.ctx.as_ptr() }, params) {
                Ok(mut rc) => {
                    let (tx, rx) = async_channel::bounded::<()>(1);
                    rc.set_update_callback(move || {
                        let _ = tx.try_send(());
                    });
                    let area = area.clone();
                    glib::spawn_future_local(async move {
                        while rx.recv().await.is_ok() {
                            area.queue_render();
                        }
                    });
                    *p.render.borrow_mut() = Some(rc);
                }
                Err(e) => eprintln!("antenne: mpv render context: {e}"),
            }
        });

        let p = player.clone();
        area.connect_render(move |area, _ctx| {
            if let Some(rc) = p.render.borrow().as_ref() {
                static GETI: OnceLock<usize> = OnceLock::new();
                let geti = *GETI.get_or_init(|| egl_proc("glGetIntegerv") as usize);
                let mut fbo: i32 = 0;
                if geti != 0 {
                    let f: GetIntegerv = unsafe { std::mem::transmute(geti) };
                    unsafe { f(GL_FRAMEBUFFER_BINDING, &mut fbo) };
                }
                let s = area.scale_factor();
                let _ = rc.render::<()>(fbo, area.width() * s, area.height() * s, true);
            }
            glib::Propagation::Stop
        });

        let p = player.clone();
        area.connect_unrealize(move |area| {
            area.make_current();
            p.render.borrow_mut().take();
        });

        Ok(player)
    }

    pub fn load(&self, url: &str, user_agent: &str, referrer: Option<&str>) {
        self.load_at(url, user_agent, referrer, None);
    }

    /// `start`: seconds in, to resume an episode.
    pub fn load_at(&self, url: &str, user_agent: &str, referrer: Option<&str>, start: Option<f64>) {
        let mpv = self.mpv.borrow();
        let _ = mpv.set_property("user-agent", user_agent);
        let _ = mpv.set_property("referrer", referrer.unwrap_or(""));
        let _ = mpv.set_property("start", start.map(|s| format!("{s:.0}")).unwrap_or_else(|| "none".into()));
        let _ = mpv.command("loadfile", &[&format!("\"{}\"", url.replace('"', "%22")), "replace"]);
    }

    /// (seconds in, length) of what is playing, when mpv knows.
    pub fn position(&self) -> Option<(f64, f64)> {
        let mpv = self.mpv.borrow();
        let pos = mpv.get_property::<f64>("time-pos").ok()?;
        let dur = mpv.get_property::<f64>("duration").ok()?;
        (dur > 0.0).then_some((pos, dur))
    }

    /// Off when nobody can see the picture: the sound goes on, the decoder
    /// stops (about 4 W for a 1080p channel on this laptop).
    ///
    /// Turning it back on alone left the picture 5.4 s off the sound on a
    /// live channel (measured with mpv's avsync), catching up at 0.3 s a
    /// second: video restarts from the network buffer, which runs ahead,
    /// and a live stream cannot be seeked back into line. drop-buffers
    /// restarts both from the live edge: avsync 0 straight away.
    /// Every event waiting in mpv's queue, read with the C API until the
    /// queue is really empty. libmpv2's wait_event answers None both for an
    /// empty queue and for an observed property that has just become
    /// unavailable (between two channels): a loop on it stopped there and
    /// left "playback started" waiting behind, which left the sound faded
    /// out for good.
    pub fn drain(&self) -> Vec<MpvEvent> {
        use libmpv2_sys as sys;
        let mut out = vec![];
        let ctx = self.mpv.borrow().ctx.as_ptr();
        loop {
            // SAFETY: mpv owns the event until the next mpv_wait_event call;
            // everything needed is copied out before then.
            let ev = unsafe { &*sys::mpv_wait_event(ctx, 0.0) };
            match ev.event_id {
                sys::mpv_event_id_MPV_EVENT_NONE => break,
                sys::mpv_event_id_MPV_EVENT_PLAYBACK_RESTART => out.push(MpvEvent::Restart),
                sys::mpv_event_id_MPV_EVENT_VIDEO_RECONFIG => out.push(MpvEvent::Reconfig),
                sys::mpv_event_id_MPV_EVENT_LOG_MESSAGE if !ev.data.is_null() => {
                    let m = unsafe { &*(ev.data as *const sys::mpv_event_log_message) };
                    let text = |p: *const std::os::raw::c_char| if p.is_null() { String::new() } else { unsafe { std::ffi::CStr::from_ptr(p) }.to_string_lossy().into_owned() };
                    let (prefix, msg) = (text(m.prefix), text(m.text));
                    if prefix == "ytdl_hook" && msg.contains("ERROR") {
                        out.push(MpvEvent::Error(msg.trim().to_string()));
                    }
                }
                sys::mpv_event_id_MPV_EVENT_END_FILE if !ev.data.is_null() => {
                    let end = unsafe { &*(ev.data as *const sys::mpv_event_end_file) };
                    if end.reason == sys::mpv_end_file_reason_MPV_END_FILE_REASON_ERROR {
                        out.push(MpvEvent::Failed);
                    } else if end.reason == sys::mpv_end_file_reason_MPV_END_FILE_REASON_EOF {
                        out.push(MpvEvent::Ended);
                    }
                }
                sys::mpv_event_id_MPV_EVENT_PROPERTY_CHANGE if !ev.data.is_null() => {
                    let p = unsafe { &*(ev.data as *const sys::mpv_event_property) };
                    let name = if p.name.is_null() { "" } else { unsafe { std::ffi::CStr::from_ptr(p.name) }.to_str().unwrap_or("") };
                    if name == "paused-for-cache" && p.format == sys::mpv_format_MPV_FORMAT_FLAG && !p.data.is_null() {
                        let on = unsafe { *(p.data as *const std::os::raw::c_int) } != 0;
                        out.push(MpvEvent::Stall(on));
                    }
                }
                _ => {}
            }
        }
        out
    }

    /// 0-100, mpv's own volume; the system's stays the user's.
    pub fn set_volume(&self, v: f64) {
        let _ = self.mpv.borrow().set_property("volume", v);
    }

    /// The lowest HLS variant on a weak connection, else the usual one.
    /// Takes effect at the next load.
    pub fn set_low_quality(&self, low: bool) {
        let _ = self.mpv.borrow().set_property("hls-bitrate", if low { "min" } else { self.base_bitrate });
    }

    /// Resuming goes back to the live edge rather than playing on from
    /// where the pause left the buffer: it is TV.
    /// `live`: a channel, which resumes at the live edge rather than where
    /// it stopped; a recording goes on from the same frame.
    pub fn set_pause(&self, paused: bool, live: bool) {
        let mpv = self.mpv.borrow();
        let _ = mpv.set_property("pause", paused);
        if !paused && live {
            let _ = mpv.command("drop-buffers", &[]);
        }
    }

    /// A point in a recording, 0 to 1.
    pub fn seek_to(&self, frac: f64) {
        let _ = self.mpv.borrow().command("seek", &[&format!("{:.2}", frac.clamp(0.0, 1.0) * 100.0), "absolute-percent"]);
    }

    /// Seconds forward (or back, negative) in a recording.
    pub fn seek(&self, secs: f64) {
        let _ = self.mpv.borrow().command("seek", &[&format!("{secs}"), "relative"]);
    }

    pub fn set_video(&self, on: bool) {
        let mpv = self.mpv.borrow();
        let _ = mpv.set_property("vid", if on { "auto" } else { "no" });
        if on {
            let _ = mpv.command("drop-buffers", &[]);
        }
    }
}
