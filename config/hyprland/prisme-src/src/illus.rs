//! The illustration over the preview: no module of the shell and no text,
//! a bar with its centre island, a window whose lines stand for text, and
//! three tiles with an icon dot. In Glass, neutral (the theme only colours
//! the terminal and Neovim there); in Ink, the theme's colours with black
//! ink, the window ringed like the active one.

use crate::themes::{self, Colors};
use gtk4::cairo::Context;
use gtk4::glib;
use gtk4::prelude::*;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

#[derive(Clone)]
pub struct Look {
    pub ink: bool,
    pub dark: bool,
    pub colors: Colors,
}

fn round_rect(cr: &Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let r = r.min(w / 2.0).min(h / 2.0);
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -PI / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, PI / 2.0);
    cr.arc(x + r, y + h - r, r, PI / 2.0, PI);
    cr.arc(x + r, y + r, r, PI, 1.5 * PI);
    cr.close_path();
}

fn set(cr: &Context, hex: &str, a: f64) {
    let (r, g, b) = themes::rgb(hex);
    cr.set_source_rgba(r, g, b, a);
}

/// Fills the current path, then outlines it in black `ink` wide (0: none).
fn fill_ink(cr: &Context, ink: f64) {
    if ink > 0.0 {
        let _ = cr.fill_preserve();
        cr.set_source_rgb(0.0, 0.0, 0.0);
        cr.set_line_width(ink);
        let _ = cr.stroke();
    } else {
        let _ = cr.fill();
    }
}

fn draw(cr: &Context, w: f64, h: f64, look: &Look) {
    let c = &look.colors;
    let (glass_fill, glass_tile, glass_ink, glass_on, glass_on_ink) = if look.dark {
        ("#121214", "#f2f2f7", "#f2f2f7", "#f2f2f7", "#0c0c0e")
    } else {
        ("#faf9f6", "#1c1c1e", "#1c1c1e", "#1c1c1e", "#f7f5f0")
    };
    let line = |cr: &Context| cr.set_line_width(if look.ink { 2.5 } else { 0.0 });
    line(cr);

    // The bar's centre island, hanging from the top edge.
    let (iw, ih) = (w * 0.22, h * 0.075);
    let ix = (w - iw) / 2.0;
    cr.new_sub_path();
    cr.move_to(ix, -2.0);
    cr.line_to(ix + iw, -2.0);
    cr.arc(ix + iw - 12.0, ih - 12.0, 12.0, 0.0, PI / 2.0);
    cr.arc(ix + 12.0, ih - 12.0, 12.0, PI / 2.0, PI);
    cr.close_path();
    if look.ink { set(cr, &c.accent, 1.0) } else { set(cr, glass_fill, if look.dark { 0.72 } else { 0.78 }) }
    fill_ink(cr, if look.ink { 2.5 } else { 0.0 });

    // A window, its text drawn as lines.
    let (wx, wy, ww, wh) = (w * 0.06, h * 0.20, w * 0.46, h * 0.56);
    round_rect(cr, wx, wy, ww, wh, 12.0);
    if look.ink {
        set(cr, &c.card, 1.0);
        let _ = cr.fill_preserve();
        set(cr, &themes::mix(&c.accent, &c.panel, 0.35), 1.0);
        cr.set_line_width(3.0);
        let _ = cr.stroke();
    } else {
        set(cr, glass_fill, if look.dark { 0.62 } else { 0.8 });
        let _ = cr.fill_preserve();
        set(cr, glass_ink, 0.12);
        cr.set_line_width(1.0);
        let _ = cr.stroke();
    }
    let (px, py) = (ww * 0.09, wh * 0.13);
    let lh = wh * 0.065;
    for (k, share) in [0.78, 0.46, 0.78, 0.62].iter().enumerate() {
        round_rect(cr, wx + px, wy + py + k as f64 * lh * 2.0, (ww - 2.0 * px) * share, lh, lh / 2.0);
        if look.ink { set(cr, &c.primary, 0.55) } else { set(cr, glass_ink, 0.55) }
        let _ = cr.fill();
    }

    // Three tiles in a drawer: one on, one other colour, one off.
    let (dw, dx, dy) = (w * 0.30, w * 0.675, h * 0.11);
    let pad = dw * 0.07;
    let th = (dw - 2.0 * pad) * 0.24;
    let dh = pad * 3.0 + th * 2.0;
    round_rect(cr, dx, dy, dw, dh, 14.0);
    if look.ink { set(cr, &c.panel, 1.0) } else { set(cr, glass_fill, if look.dark { 0.62 } else { 0.78 }) }
    fill_ink(cr, if look.ink { 2.5 } else { 0.0 });
    let inner = dw - 2.0 * pad;
    let half = (inner - pad * 0.8) / 2.0;
    let tiles = [
        (dx + pad, dy + pad, inner, true, 0),
        (dx + pad, dy + pad * 2.0 + th, half, false, 1),
        (dx + pad + half + pad * 0.8, dy + pad * 2.0 + th, half, false, 2),
    ];
    for (x, y, tw, on, k) in tiles {
        round_rect(cr, x, y, tw, th, 10.0);
        let (fill, dot) = if look.ink {
            match k {
                0 => (c.accent.as_str(), c.on_accent.as_str()),
                1 => (c.info.as_str(), c.on_accent.as_str()),
                _ => (c.card.as_str(), c.primary.as_str()),
            }
        } else if on {
            (glass_on, glass_on_ink)
        } else {
            (glass_tile, glass_ink)
        };
        set(cr, fill, if look.ink || on { 1.0 } else { 0.08 });
        fill_ink(cr, if look.ink { 2.0 } else { 0.0 });
        let r = th * 0.18;
        cr.arc(x + th * 0.45, y + th / 2.0, r, 0.0, 2.0 * PI);
        set(cr, dot, 0.85);
        let _ = cr.fill();
    }
}

/// How long a new look takes to fade in over the old one, as the
/// preview's pictures do.
const FADE_MS: f64 = 220.0;

#[derive(Default)]
pub struct State {
    current: Option<Look>,
    previous: Option<Look>,
    fade: f64,
    start_us: Option<i64>,
    ticking: bool,
}

/// The drawing area: the current look, faded in over the previous one
/// while a change is under way.
pub fn new() -> (gtk4::DrawingArea, Rc<RefCell<State>>) {
    let state = Rc::new(RefCell::new(State { fade: 1.0, ..Default::default() }));
    let area = gtk4::DrawingArea::builder().can_target(false).hexpand(true).vexpand(true).build();
    let st = state.clone();
    area.set_draw_func(move |_, cr, w, h| {
        let st = st.borrow();
        let (w, h) = (w as f64, h as f64);
        match (&st.previous, &st.current) {
            (Some(old), Some(new)) if st.fade < 1.0 => {
                draw(cr, w, h, old);
                cr.push_group();
                draw(cr, w, h, new);
                let _ = cr.pop_group_to_source();
                let _ = cr.paint_with_alpha(st.fade);
            }
            (_, Some(new)) => draw(cr, w, h, new),
            _ => {}
        }
    });
    (area, state)
}

/// Shows `look`: at once the first time, faded in over the one before
/// afterwards. Ticks only while fading.
pub fn set_look(area: &gtk4::DrawingArea, state: &Rc<RefCell<State>>, look: Look) {
    {
        let mut st = state.borrow_mut();
        let first = st.current.is_none();
        let old = st.current.replace(look);
        if first {
            st.fade = 1.0;
        } else {
            st.previous = old;
            st.fade = 0.0;
            st.start_us = None;
        }
    }
    area.queue_draw();
    if state.borrow().fade >= 1.0 || state.borrow().ticking {
        return;
    }
    state.borrow_mut().ticking = true;
    let st = state.clone();
    area.add_tick_callback(move |area, clock| {
        let mut s = st.borrow_mut();
        let now = clock.frame_time();
        let start = *s.start_us.get_or_insert(now);
        let t = ((now - start) as f64 / 1000.0 / FADE_MS).clamp(0.0, 1.0);
        s.fade = t * t * (3.0 - 2.0 * t);
        area.queue_draw();
        if t >= 1.0 {
            s.previous = None;
            s.ticking = false;
            return glib::ControlFlow::Break;
        }
        glib::ControlFlow::Continue
    });
}
