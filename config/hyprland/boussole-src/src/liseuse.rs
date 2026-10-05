//! What a document open in Liseuse is, and where its sections start.
//!
//! Liseuse renders Markdown to `~/.cache/liseuse/md/<hash>/<name>.pdf`, with
//! `<name>.src` next to it holding the source's path: that is how an open
//! PDF leads back to a sheet of the course folder. The PDF's outline
//! (`mutool show FILE outline`) gives the page of every heading, hence the
//! section a page belongs to ("page 7" = "§5 Exercises").

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

#[derive(Clone, PartialEq, Debug)]
pub struct Heading {
    pub depth: usize,
    pub title: String,
    /// 1-based, as in the outline.
    pub page: u32,
}

/// `mutool show FILE outline`: one heading per line,
/// `|\t\t"Title"\t#page=7&zoom=…`.
pub fn parse_outline(text: &str) -> Vec<Heading> {
    let mut out = Vec::new();
    for line in text.lines() {
        let Some(open) = line.find('"') else { continue };
        let Some(close) = line.rfind('"').filter(|&c| c > open) else { continue };
        let depth = line[..open].chars().filter(|&c| c == '\t').count();
        let title = line[open + 1..close].replace("\\\"", "\"");
        let Some(page) = line[close..].split("#page=").nth(1) else { continue };
        let digits: String = page.chars().take_while(|c| c.is_ascii_digit()).collect();
        let Ok(page) = digits.parse() else { continue };
        out.push(Heading { depth, title, page });
    }
    out
}

/// The source of a rendered Markdown, or the file itself.
pub fn source_of(file: &Path) -> PathBuf {
    let src = file.with_extension("src");
    match std::fs::read_to_string(&src) {
        Ok(text) => text.lines().next().map(|l| PathBuf::from(l.trim())).filter(|p| p.is_absolute()).unwrap_or(file.to_path_buf()),
        Err(_) => file.to_path_buf(),
    }
}

/// The catalogue id of an open file, when it lies in the course folder.
pub fn item_of(file: &Path, courses: &Path) -> Option<String> {
    let src = source_of(file);
    let rel = src.strip_prefix(courses).ok()?;
    Some(rel.to_string_lossy().into_owned())
}

/// Where a sheet's sections and exercises start.
#[derive(Clone, PartialEq, Debug, Default)]
pub struct Map {
    /// (§ number, first page), in order.
    pub sections: Vec<(u32, u32)>,
    /// (exercise number, page).
    pub exercises: Vec<(u32, u32)>,
    pub pages: u32,
}

fn leading_number(title: &str) -> Option<u32> {
    let digits: String = title.chars().take_while(|c| c.is_ascii_digit()).collect();
    let rest = &title[digits.len()..];
    (!digits.is_empty() && (rest.starts_with('.') || rest.starts_with(' '))).then(|| digits.parse().ok()).flatten()
}

pub fn map(outline: &[Heading], pages: u32) -> Map {
    // The numbered sections are the shallowest headings that carry a
    // number ("1. Formal explanation"); deeper ones ("1.2 …") are inside.
    let depth = outline.iter().filter(|h| leading_number(&h.title).is_some()).map(|h| h.depth).min();
    let sections = outline
        .iter()
        .filter(|h| Some(h.depth) == depth)
        .filter_map(|h| Some((leading_number(&h.title)?, h.page)))
        .collect();
    let exercises = outline
        .iter()
        .filter_map(|h| {
            let t = h.title.to_lowercase();
            let rest = t.strip_prefix("exercice ").or_else(|| t.strip_prefix("exercise "))?;
            Some((leading_number(rest)?, h.page))
        })
        .collect();
    Map { sections, exercises, pages }
}

impl Map {
    /// The section a page is in (the last one started on or before it).
    pub fn section_at(&self, page: u32) -> Option<u32> {
        self.sections.iter().take_while(|(_, p)| *p <= page).last().map(|(n, _)| *n)
    }

    pub fn page_of(&self, section: u32) -> Option<u32> {
        self.sections.iter().find(|(n, _)| *n == section).map(|(_, p)| *p)
    }

    /// The pages a section spans, its first to the one the next starts on
    /// (a section ending mid-page shares that page).
    fn span(&self, i: usize) -> (u32, u32) {
        let start = self.sections[i].1;
        let end = self.sections.get(i + 1).map_or(self.pages.max(start), |(_, p)| (*p).max(start));
        (start, end)
    }

    /// The last § such that it and every one before it had all their pages
    /// read, the page shared with the next section counting for both.
    pub fn read_upto(&self, read: &BTreeSet<u32>) -> u32 {
        let mut upto = 0;
        for i in 0..self.sections.len() {
            let (a, b) = self.span(i);
            // The next section's first page only needs reading if this one
            // takes more than a line of it: it does when it starts there.
            let last = if b > a && self.sections.get(i + 1).is_some() { b - 1 } else { b };
            if (a..=last).all(|p| read.contains(&p)) {
                upto = self.sections[i].0;
            } else {
                break;
            }
        }
        upto
    }
}
