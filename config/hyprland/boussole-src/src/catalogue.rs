//! The course folder, read and never written.
//!
//! Each top-level folder is a domain. Inside, a chapter is a folder holding a
//! `00_Carte_du_cours.md`: its numbered blocks hold sheets (`NN_Block/MM_Sheet.md`)
//! and its `90_…` block the synthesis and exam-type exercises; the map's tree
//! marks the priority sheets with ★. Anything else, a teacher's PDF, notes,
//! is an item of its own without structure. A new file is never planned
//! before the user says so (`Inclusion`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::model::Domain;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ItemKind {
    /// A chapter's map, read first.
    Map,
    /// A sheet: sections to read, then exercises.
    Sheet,
    /// Synthesis exercises at the end of a chapter.
    Synthesis,
    /// Exam-type subjects, done in limited time.
    ExamPractice,
    /// One exercise of a tutorial sheet.
    TdExercise,
    Pdf,
    Notes,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Section {
    pub num: u32,
    pub title: String,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
pub struct Item {
    /// Path relative to the courses root: `A&C/Cours_03/30_LS/31_Algorithme_LS.md`.
    pub id: String,
    pub domain: String,
    /// The chapter folder, relative to the domain, for structured items.
    pub chapter: Option<String>,
    pub kind: ItemKind,
    pub title: String,
    /// Sections to read, the exercises one left out.
    pub sections: Vec<Section>,
    /// § number of the exercises section.
    pub exercises_section: Option<u32>,
    pub exercises: u32,
    /// Exam-type subjects in the file.
    pub subjects: u32,
    pub starred: bool,
    /// What the map says next to the ★.
    pub star_note: Option<String>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Inclusion {
    Planned,
    Ignored,
}

#[derive(Clone, PartialEq, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Ignore {
    /// File names, any case.
    pub files: Vec<String>,
    /// Folder names, any case. Hidden folders are always skipped.
    pub dirs: Vec<String>,
}

impl Default for Ignore {
    fn default() -> Ignore {
        Ignore {
            files: ["00_Index.md", "roadmap.md", "README.md"].map(String::from).to_vec(),
            dirs: ["_outils", "References", "node_modules", "target"].map(String::from).to_vec(),
        }
    }
}

#[derive(Clone, PartialEq, Debug, Default, Serialize, Deserialize)]
pub struct Catalogue {
    pub root: PathBuf,
    /// In file order: domain, then natural order of the path.
    pub items: Vec<Item>,
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug)]
enum Run {
    Num(u64),
    Text(String),
}

/// Natural order: digit runs compare as numbers, the rest ignoring case
/// ("Exo_2" before "Exo_16", "00_Carte" before "10_Bloc").
fn natural(name: &str) -> Vec<Run> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut digits = false;
    for c in name.chars() {
        if c.is_ascii_digit() != digits && !cur.is_empty() {
            out.push(if digits { Run::Num(cur.parse().unwrap_or(u64::MAX)) } else { Run::Text(cur.to_lowercase()) });
            cur.clear();
        }
        digits = c.is_ascii_digit();
        cur.push(c);
    }
    if !cur.is_empty() {
        out.push(if digits { Run::Num(cur.parse().unwrap_or(u64::MAX)) } else { Run::Text(cur.to_lowercase()) });
    }
    out
}

fn path_key(id: &str) -> Vec<Vec<Run>> {
    id.split('/').map(natural).collect()
}

fn leading_number(name: &str) -> Option<u32> {
    let digits: String = name.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

/// "31_Algorithme_LS.md" → "Algorithme LS".
fn title_from_name(name: &str) -> String {
    let stem = name.rsplit_once('.').map_or(name, |(s, _)| s);
    let stem = stem.trim_start_matches(|c: char| c.is_ascii_digit()).trim_start_matches('_');
    stem.replace('_', " ").trim().to_string()
}

fn heading(line: &str) -> Option<(usize, &str)> {
    let level = line.chars().take_while(|&c| c == '#').count();
    (level > 0 && line[level..].starts_with(' ')).then(|| (level, line[level..].trim()))
}

fn is_exercise(title: &str) -> bool {
    let t = title.to_lowercase();
    t.starts_with("exercice") || t.starts_with("exercise")
}

/// Fills title, sections, exercises and subjects from the Markdown.
fn read_markdown(item: &mut Item, text: &str) {
    let mut first = true;
    let mut subjects = 0;
    let mut in_code = false;
    for line in text.lines() {
        if line.trim_start().starts_with("```") {
            in_code = !in_code;
            continue;
        }
        if in_code {
            continue;
        }
        let Some((level, title)) = heading(line) else { continue };
        if level == 1 {
            if first {
                item.title = title.to_string();
            } else if title.to_lowercase().starts_with("sujet") {
                subjects += 1;
            }
            first = false;
            continue;
        }
        first = false;
        match item.kind {
            ItemKind::Sheet if level == 2 => {
                let num = leading_number(title);
                let rest = title.trim_start_matches(|c: char| c.is_ascii_digit() || c == '.').trim();
                if let Some(num) = num {
                    if is_exercise(rest) {
                        item.exercises_section = Some(num);
                    } else {
                        item.sections.push(Section { num, title: rest.to_string() });
                    }
                }
            }
            ItemKind::Sheet | ItemKind::Synthesis if is_exercise(title) && level <= 3 => item.exercises += 1,
            _ => {}
        }
    }
    if item.kind == ItemKind::ExamPractice {
        item.subjects = subjects.max(1);
    }
    if item.kind == ItemKind::TdExercise {
        item.exercises = 1;
    }
}

/// The files a map marks with ★, and what it says about them.
fn read_stars(map: &str) -> BTreeMap<String, String> {
    let mut stars = BTreeMap::new();
    for line in map.lines() {
        let Some((before, after)) = line.split_once('★') else { continue };
        let file = before
            .split(|c: char| c.is_whitespace() || "│├└─`|".contains(c))
            .filter(|w| w.ends_with(".md"))
            .last();
        if let Some(file) = file {
            let file = file.rsplit('/').next().unwrap_or(file);
            stars.insert(file.to_string(), after.trim().to_string());
        }
    }
    stars
}

struct Walker<'a> {
    root: &'a Path,
    ignore: &'a Ignore,
    items: Vec<Item>,
}

impl Walker<'_> {
    fn skipped_dir(&self, name: &str) -> bool {
        name.starts_with('.') || self.ignore.dirs.iter().any(|d| d.eq_ignore_ascii_case(name))
    }

    fn skipped_file(&self, name: &str) -> bool {
        let lower = name.to_lowercase();
        name.starts_with('.')
            || !(lower.ends_with(".md") || lower.ends_with(".pdf"))
            || self.ignore.files.iter().any(|f| f.eq_ignore_ascii_case(name))
    }

    /// `chapter`: the structured chapter above, relative to the domain.
    /// `td`: below a folder with a `00_Sommaire.md`.
    /// `stars`: the chapter map's ★, carried down into its blocks.
    fn walk(&mut self, domain: &str, rel: &str, chapter: Option<&str>, td: bool, stars: &BTreeMap<String, String>) {
        let dir = self.root.join(rel);
        let Ok(entries) = std::fs::read_dir(&dir) else { return };
        let mut names: Vec<(String, bool)> = entries
            .flatten()
            .map(|e| {
                let is_dir = e.file_type().is_ok_and(|t| t.is_dir());
                (e.file_name().to_string_lossy().into_owned(), is_dir)
            })
            .collect();
        names.sort();
        let has = |n: &str| names.iter().any(|(m, d)| !d && m == n);
        let in_domain = rel.split_once('/').map_or("", |(_, r)| r);
        let chapter = if chapter.is_none() && has("00_Carte_du_cours.md") { Some(in_domain) } else { chapter };
        let td = td || has("00_Sommaire.md");
        let own;
        let stars = match chapter {
            Some(c) if c == in_domain => {
                own = std::fs::read_to_string(dir.join("00_Carte_du_cours.md")).map(|m| read_stars(&m)).unwrap_or_default();
                &own
            }
            _ => stars,
        };

        for (name, is_dir) in &names {
            let child = format!("{rel}/{name}");
            if *is_dir {
                if !self.skipped_dir(name) {
                    self.walk(domain, &child, chapter, td, stars);
                }
                continue;
            }
            if self.skipped_file(name) {
                continue;
            }
            let pdf = name.to_lowercase().ends_with(".pdf");
            let parent = in_domain.rsplit('/').next().unwrap_or("");
            let depth_in_chapter = chapter.map(|c| {
                let c_depth = if c.is_empty() { 0 } else { c.split('/').count() };
                let here = if in_domain.is_empty() { 0 } else { in_domain.split('/').count() };
                here - c_depth
            });
            let kind = if pdf {
                ItemKind::Pdf
            } else if chapter.is_some() && name == "00_Carte_du_cours.md" && depth_in_chapter == Some(0) {
                ItemKind::Map
            } else if td && name == "00_Sommaire.md" {
                ItemKind::Map
            } else if depth_in_chapter == Some(1) && leading_number(name).is_some() {
                match leading_number(parent) {
                    Some(n) if n >= 90 => {
                        let lower = name.to_lowercase();
                        if lower.starts_with("93") || lower.contains("sujet") {
                            ItemKind::ExamPractice
                        } else {
                            ItemKind::Synthesis
                        }
                    }
                    Some(_) => ItemKind::Sheet,
                    None => ItemKind::Notes,
                }
            } else if td && name.to_lowercase().starts_with("exo") {
                ItemKind::TdExercise
            } else {
                ItemKind::Notes
            };
            let starred = stars.get(name);
            let mut item = Item {
                id: child.clone(),
                domain: domain.to_string(),
                chapter: chapter.filter(|_| kind != ItemKind::Pdf && kind != ItemKind::Notes).map(String::from),
                kind,
                title: title_from_name(name),
                sections: Vec::new(),
                exercises_section: None,
                exercises: 0,
                subjects: 0,
                starred: starred.is_some(),
                star_note: starred.filter(|n| !n.is_empty()).cloned(),
            };
            if !pdf {
                if let Ok(text) = std::fs::read_to_string(self.root.join(&child)) {
                    read_markdown(&mut item, &text);
                }
            }
            self.items.push(item);
        }
    }
}

impl Catalogue {
    pub fn scan(root: &Path, ignore: &Ignore) -> Catalogue {
        let mut w = Walker { root, ignore, items: Vec::new() };
        let mut domains: Vec<String> = std::fs::read_dir(root)
            .map(|rd| {
                rd.flatten()
                    .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .collect()
            })
            .unwrap_or_default();
        domains.sort();
        for d in domains {
            if !w.skipped_dir(&d) {
                w.walk(&d, &d, None, false, &BTreeMap::new());
            }
        }
        let mut items = w.items;
        items.sort_by_cached_key(|i| path_key(&i.id));
        Catalogue { root: root.to_path_buf(), items }
    }

    /// Top-level folders holding at least one item.
    pub fn domains(&self) -> Vec<&str> {
        let mut ids: Vec<&str> = self.items.iter().map(|i| i.domain.as_str()).collect();
        ids.dedup();
        ids
    }

    pub fn get(&self, id: &str) -> Option<&Item> {
        self.items.iter().find(|i| i.id == id)
    }

    /// A domain's items in work order: those placed by hand first, in their
    /// order, then the rest in file order. Stars set by hand win.
    pub fn ordered(&self, domain: &Domain) -> Vec<Item> {
        let mut mine: Vec<&Item> = self.items.iter().filter(|i| i.domain == domain.id).collect();
        let rank = |i: &Item| domain.order.iter().position(|o| *o == i.id).unwrap_or(usize::MAX);
        mine.sort_by_key(|i| rank(i));
        mine.into_iter()
            .map(|i| {
                let mut i = i.clone();
                if let Some(&s) = domain.stars.get(&i.id) {
                    i.starred = s;
                }
                i
            })
            .collect()
    }

    /// Files nobody has decided about yet: shown as "to plan".
    pub fn undecided<'a>(&'a self, decisions: &BTreeMap<String, Inclusion>) -> Vec<&'a Item> {
        self.items.iter().filter(|i| !decisions.contains_key(&i.id)).collect()
    }

    /// The undecided files worth asking about: not those of a domain where
    /// the tutorials are enough, which has nothing to read.
    pub fn pending<'a>(&'a self, decisions: &BTreeMap<String, Inclusion>, domains: &[crate::model::Domain]) -> Vec<&'a Item> {
        let reads = |id: &str| domains.iter().find(|d| d.id == id).is_none_or(|d| d.level.studies());
        self.undecided(decisions).into_iter().filter(|i| reads(&i.domain)).collect()
    }
}
