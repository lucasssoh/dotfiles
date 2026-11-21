//! The coucou bird (site/src/assets/coucou-*.svg), drawn with block
//! characters: a round body, an eye cut out of it, a beak.
//!
//! Traced from the SVG's own shapes, a cell being twice as tall as it is
//! wide. SMALL is in half blocks (▀ ▄), two pixels per cell. BIG is in
//! quadrants (▘ ▟ …), four per cell, for smoother edges; the Linux console's
//! font has no quadrants, so it gets BIG_PLAIN, in half blocks.

pub const SMALL: [&str; 5] = [
    " ▄▄████▄▄   ",
    "▄██████ █▄  ",
    "███████████▀",
    "▀████████▀  ",
    " ▀▀████▀▀   ",
];

const BIG: [&str; 10] = [
    "     ▗▄▄▟███▄▄▄          ",
    "   ▄████████████▙▖       ",
    " ▗▟██████████▀ ▀██▄      ",
    " ███████████▙  ▗███▙▄▖   ",
    "▐██████████████████████▙▄",
    "▐███████████████████▛▀▀  ",
    " ██████████████████▘     ",
    " ▝▜███████████████▀      ",
    "   ▀████████████▛▘       ",
    "     ▝▀▀▜███▀▀▀          ",
];

const BIG_PLAIN: [&str; 10] = [
    "     ▄▄▄███▄▄▄           ",
    "  ▄████████████▄         ",
    " ███████████▀ ▀██▄       ",
    "████████████   ███▄▄     ",
    "███████████████████████▄ ",
    "████████████████████▀▀   ",
    "██████████████████▀      ",
    " ████████████████▀       ",
    "  ▀████████████▀         ",
    "     ▀▀▀███▀▀▀           ",
];

/// The big bird, in what this terminal can draw.
pub fn big() -> &'static [&'static str] {
    if std::env::var("TERM").is_ok_and(|t| t == "linux") { &BIG_PLAIN } else { &BIG }
}

/// The bird on the left, `lines` beside it, top-aligned; extra lines go on
/// below the bird, in the same column.
pub fn beside(art: &[&str], bold: impl Fn(&str) -> String, lines: &[String]) -> Vec<String> {
    let width = art.iter().map(|r| r.chars().count()).max().unwrap_or(0);
    let rows = art.len().max(lines.len());
    (0..rows)
        .map(|i| {
            let bird = art.get(i).map(|r| bold(r)).unwrap_or_else(|| " ".repeat(width));
            let text = lines.get(i).map(String::as_str).unwrap_or("");
            format!("  {bird}    {text}").trim_end().to_string()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_are_even() {
        for art in [&SMALL[..], &BIG[..], &BIG_PLAIN[..]] {
            let w = art[0].chars().count();
            assert!(art.iter().all(|r| r.chars().count() == w));
        }
    }

    #[test]
    fn text_lines_up_past_the_bird() {
        let rows = beside(&SMALL, |s| s.to_string(), &["a".into(), "b".into()]);
        assert_eq!(rows.len(), 5);
        assert_eq!(rows[0], format!("  {}    a", SMALL[0]));
        assert_eq!(rows[2], format!("  {}", SMALL[2]));
    }
}
