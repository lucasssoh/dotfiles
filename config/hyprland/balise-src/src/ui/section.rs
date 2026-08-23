//! Shared "section card" helper: one rounded, unified background per
//! list section (ACTIVE CONNECTION / AVAILABLE NETWORKS / CONNECTED /
//! PAIRED / AVAILABLE / SAVED NETWORKS...) instead of every row inside
//! it having its own border+background. Asked for, with iOS Control
//! Center's Bluetooth panel as the reference: rows flow inside one
//! grouped card with no per-item contour.

use gtk4::{self as gtk, Orientation};

/// Builds an empty card; caller appends rows into it, then appends the
/// card itself (not the individual rows) into the outer list. Pass
/// `&["connected"]` for the section that represents the current/active
/// item (a single connected WiFi network, connected Bluetooth devices,
/// an active wired connection) to get the accent-tinted glass ring
/// instead of the plain card fill (see .balise-section-card.connected in
/// style.css).
///
/// `overflow(Hidden)` is what makes this work: rows inside stay flat
/// (no border-radius of their own -- see .balise-network-row in
/// style.css), and their hover/focus background tint still clips
/// cleanly to the card's rounded corners instead of poking past them,
/// the same trick window.rs uses for .balise-panel/.balise-panel-inner.
pub fn section_card(extra_classes: &[&str]) -> gtk::Box {
    let mut classes: Vec<&str> = vec!["balise-section-card"];
    classes.extend_from_slice(extra_classes);

    let card = gtk::Box::builder().orientation(Orientation::Vertical).css_classes(classes).overflow(gtk::Overflow::Hidden).build();
    card
}
