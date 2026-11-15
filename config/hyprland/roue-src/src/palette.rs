//! The wheel's inks, dark or light with the desktop's colour scheme --
//! DrawerTheme.qml's values (quickshell/bar/theme), the same names where
//! they exist there. The screen behind is blurred under a veil (style.css),
//! so the pastilles are that palette's cards: a veil of the ink in dark,
//! white in light, with the panes' rim and top light.

pub type Rgba = (f32, f32, f32, f32);

#[derive(Clone, Copy)]
pub struct Palette {
    /// Text, and the icon on a pastille at rest.
    pub primary: Rgba,
    /// The wheel's name and a pending question, while nothing is aimed.
    pub secondary: Rgba,
    /// The aimed pastille's fill (DrawerTheme's `on`)...
    pub on: Rgba,
    /// ...and the icon drawn on it (`onInk`).
    pub on_ink: Rgba,
    /// A pastille at rest.
    pub pill: Rgba,
    pub rim: Rgba,
    pub highlight: Rgba,
    /// The dotted circle the pastilles sit on.
    pub guide: Rgba,
    /// Confirm on a destructive confirmation.
    pub danger: Rgba,
}

const fn hex(rgb: u32) -> Rgba {
    (
        ((rgb >> 16) & 0xff) as f32 / 255.0,
        ((rgb >> 8) & 0xff) as f32 / 255.0,
        (rgb & 0xff) as f32 / 255.0,
        1.0,
    )
}

impl Palette {
    pub fn new(dark: bool) -> Self {
        if dark {
            Palette {
                primary: hex(0xf2f2f7),
                secondary: hex(0xa1a1a6),
                on: hex(0xf2f2f7),
                on_ink: hex(0x0c0c0e),
                pill: (0.949, 0.949, 0.969, 0.10),
                rim: (1.0, 1.0, 1.0, 0.14),
                highlight: (1.0, 1.0, 1.0, 0.12),
                guide: (1.0, 1.0, 1.0, 0.22),
                danger: hex(0xff6e6e),
            }
        } else {
            Palette {
                primary: hex(0x1c1c1e),
                secondary: hex(0x3f3f44),
                on: hex(0x1c1c1e),
                on_ink: hex(0xf7f5f0),
                pill: (1.0, 1.0, 1.0, 0.50),
                rim: (1.0, 1.0, 1.0, 0.65),
                highlight: (1.0, 1.0, 1.0, 0.85),
                guide: (0.11, 0.11, 0.12, 0.22),
                danger: hex(0xb3261e),
            }
        }
    }
}

/// `#rrggbb` for an ink, to bake it into an icon raster (icons.rs).
pub fn to_hex(c: Rgba) -> String {
    let b = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
    format!("#{:02x}{:02x}{:02x}", b(c.0), b(c.1), b(c.2))
}
