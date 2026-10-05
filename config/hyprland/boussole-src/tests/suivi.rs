mod common;

use std::collections::{BTreeMap, BTreeSet};

use common::*;

use boussole::journee::{Place, SlotKind};
use boussole::liseuse;
use boussole::plan::{Part, Session, Work};
use boussole::seance::{self, Prompt, Tracker, READ_SECS};

/// The shape of a real sheet's outline (mutool show … outline): a title,
/// numbered sections with numbered subsections, then the exercises.
const OUTLINE: &str = "-\t\"The title\"\t#page=1&zoom=nan,57,44\n\
-\t\t\"1. Formal\"\t#page=1&zoom=nan,57,279\n\
|\t\t\t\"1.1 First point\"\t#page=1&zoom=nan,57,321\n\
|\t\t\t\"1.2 Second point\"\t#page=2&zoom=nan,57,38\n\
|\t\t\"2. Intuitive\"\t#page=3&zoom=nan,57,186\n\
|\t\t\"3. Worked example\"\t#page=4&zoom=nan,57,113\n\
|\t\t\"4. Pitfalls\"\t#page=5&zoom=nan,57,265\n\
-\t\t\"5. Exercices\"\t#page=6&zoom=nan,57,114\n\
|\t\t\t\"Exercice 1 — Run it\"\t#page=6&zoom=nan,57,155\n\
|\t\t\t\"Exercice 2 — \\\"Order\\\" matters\"\t#page=8&zoom=nan,57,190\n\
|\t\t\t\"Exercice 3 — A proof\"\t#page=9&zoom=nan,57,38\n";

fn sheet_map() -> liseuse::Map {
    liseuse::map(&liseuse::parse_outline(OUTLINE), 10)
}

#[test]
fn the_outline_gives_each_section_its_pages() {
    let o = liseuse::parse_outline(OUTLINE);
    assert_eq!(o.len(), 11);
    assert_eq!((o[1].depth, o[1].title.as_str(), o[1].page), (2, "1. Formal", 1));
    assert_eq!(o[9].title, "Exercice 2 — \"Order\" matters");
    let m = sheet_map();
    assert_eq!(m.sections, [(1, 1), (2, 3), (3, 4), (4, 5), (5, 6)], "1.1 and 1.2 are inside §1");
    assert_eq!(m.exercises, [(1, 6), (2, 8), (3, 9)]);
    assert_eq!(m.section_at(2), Some(1));
    assert_eq!(m.section_at(7), Some(5));
    assert_eq!(m.page_of(3), Some(4));

    let read = |pages: &[u32]| m.read_upto(&pages.iter().copied().collect::<BTreeSet<u32>>());
    assert_eq!(read(&[1, 2]), 1, "§1 spans pages 1-2, §2 starts on 3");
    assert_eq!(read(&[1, 2, 3]), 2);
    assert_eq!(read(&[1, 3, 4]), 0, "page 2 missing: §1 is not read");
    assert_eq!(read(&[1, 2, 3, 4, 5]), 4);
}

#[test]
fn an_open_pdf_leads_back_to_its_sheet() {
    let dir = std::env::temp_dir().join(format!("boussole-liseuse-{}", std::process::id()));
    let cache = dir.join("cache/53e6");
    std::fs::create_dir_all(&cache).unwrap();
    let courses = dir.join("courses");
    let src = courses.join("A&C/Ch/30_LS/31_LS.md");
    // Liseuse writes the source path without a newline.
    std::fs::write(cache.join("31_LS.src"), src.to_string_lossy().as_bytes()).unwrap();
    assert_eq!(liseuse::item_of(&cache.join("31_LS.pdf"), &courses).as_deref(), Some("A&C/Ch/30_LS/31_LS.md"));
    assert_eq!(liseuse::item_of(&courses.join("OC/cours.pdf"), &courses).as_deref(), Some("OC/cours.pdf"));
    assert_eq!(liseuse::item_of(&dir.join("Livres/roman.pdf"), &courses), None, "a book is not a sheet");
    let _ = std::fs::remove_dir_all(dir);
}

const SHEET: &str = "A&C/Ch/30_LS/31_LS.md";

#[test]
fn time_counts_only_when_working() {
    let mut t = Tracker::start(Some("s".into()), 0);
    t.set(0, |f| f.visible = true);
    t.page(0, SHEET, 1, 10);
    // 10 minutes reading page 1, then 6 idle, 20 of a game, 4 with a video.
    t.set(600, |f| f.idle = true);
    t.set(960, |f| {
        f.idle = false;
        f.game = true;
    });
    t.set(2160, |f| {
        f.game = false;
        f.media = true;
    });
    t.advance(2400);
    assert_eq!((t.effective, t.idle_secs, t.game_secs, t.media_secs), (600 + 240, 360, 1200, 240));
    assert_eq!(t.dwell[SHEET][&1], 600 + 240, "reading only while it counts");

    // Liseuse behind another window: the time counts, the page does not.
    t.set(2400, |f| f.visible = false);
    t.advance(3000);
    assert_eq!(t.dwell[SHEET][&1], 840);
    assert_eq!(t.effective, 840 + 600);
}

#[test]
fn reading_skimming_and_the_estimate() {
    let mut t = Tracker::start(Some("s".into()), 0);
    t.set(0, |f| f.visible = true);
    // Pages 1-3 read slowly.
    for (i, p) in [1u32, 2, 3].iter().enumerate() {
        t.page(i as i64 * 120, SHEET, *p, 10);
    }
    // Then a quick pass through 4-10.
    let mut at = 360;
    for p in 4..=10 {
        t.page(at, SHEET, p, 10);
        at += 5;
    }
    t.advance(at);
    let (read, skimmed) = t.pages(SHEET);
    assert_eq!(read.into_iter().collect::<Vec<_>>(), [1, 2, 3]);
    assert_eq!(skimmed.into_iter().collect::<Vec<_>>(), [4, 5, 6, 7, 8, 9, 10]);
    assert_eq!(t.skims.len(), 1, "going through most pages quickly is a skim");
    assert_eq!(t.skims[0].pages, 10);
    assert_eq!(seance::estimate(10, 2.2), 20);
    assert!(READ_SECS > 5);
}

#[test]
fn closing_liseuse_ends_nothing_but_asks_once() {
    let end = 4500;
    let mut t = Tracker::start(Some("s".into()), 0);
    t.set(0, |f| f.visible = true);
    t.page(0, SHEET, 6, 10);
    t.closed(600);
    // Work goes on on paper: counted, and one question after 18 minutes.
    assert_eq!(t.prompt(600 + 17 * 60, end), None);
    assert_eq!(t.next_prompt(600, end), Some(600 + 18 * 60));
    assert_eq!(t.prompt(600 + 18 * 60, end), Some(Prompt::StillWorking));
    t.advance(600 + 18 * 60);
    assert_eq!(t.effective, 600 + 18 * 60);
    // "No, I stopped": the time without the sheet goes.
    t.not_working(600 + 18 * 60);
    assert_eq!(t.effective, 600);
    assert_eq!(t.prompt(2000, end), None, "asked once");
    // The closing window, 15 minutes after the planned end.
    assert_eq!(t.prompt(end + 15 * 60, end), Some(Prompt::Closing));
    // Outside a session nothing is ever asked.
    assert_eq!(Tracker::start(None, 0).prompt(99_999, end), None);
}

#[test]
fn the_close_is_prefilled_by_what_liseuse_saw() {
    let mut t = Tracker::start(Some("s".into()), 0);
    t.set(0, |f| f.visible = true);
    for (i, p) in [1u32, 2, 3, 4].iter().enumerate() {
        t.page(i as i64 * 300, SHEET, *p, 10);
    }
    t.page(1200, SHEET, 6, 10);
    t.set(1500, |f| f.media = true);
    t.advance(4200);
    let session = Session {
        id: "2026-10-05-evening1".into(),
        date: MON,
        start: hm("20:30"),
        end: hm("21:45"),
        kind: SlotKind::Evening,
        counted: true,
        place: Place::Home,
        shortened: false,
        pinned: false,
        parts: vec![
            Part {
                task: format!("study:{SHEET}"),
                domain: Some("A&C".into()),
                minutes: 60,
                work: Work::Study { item: SHEET.into(), sections: Some((1, 4)), exercises: Some((1, 3)) },
                timed: false,
            },
            Part { task: "review1:X".into(), domain: None, minutes: 15, work: Work::Review { item: "X".into(), n: 1 }, timed: false },
        ],
        reasons: Vec::new(),
    };
    let mut maps = BTreeMap::new();
    maps.insert(SHEET.to_string(), sheet_map());
    let mut free = BTreeMap::new();
    free.insert(SHEET.to_string(), (MON.add(-1), 1u32));
    let d = seance::draft(&t, &session, &maps, &free, |_| Some(4));
    assert_eq!(d.effective_minutes, 70);
    assert_eq!(d.media_minutes, 45, "asked about, not judged");
    assert_eq!(d.parts[0].read_upto, Some(3), "pages 1-4 read: §1-3, §4 shares page 5 unread");
    assert!(d.parts[0].exercises.is_empty(), "exercises are declared, never guessed");
    assert!(!d.parts[0].done);
    assert_eq!((d.parts[0].minutes, d.parts[0].planned), (56, 60));
    assert_eq!(d.files[0].before, Some((MON.add(-1), 1)), "free reading, to confirm");
}
