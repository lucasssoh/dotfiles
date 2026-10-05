use std::path::Path;

use boussole::ade::{self, Change, Event, Outcome, Selection, Snapshot};
use boussole::model::{CourseKind, Domain};
use boussole::time::{Date, Hm, Local, Tz};

fn paris() -> Tz {
    Tz::named("Europe/Paris").expect("tzdata")
}

fn vevent(uid: &str, start: &str, end: &str, summary: &str) -> String {
    format!("BEGIN:VEVENT\r\nDTSTART:{start}\r\nDTEND:{end}\r\nSUMMARY:{summary}\r\nUID:{uid}\r\nEND:VEVENT\r\n")
}

fn calendar(events: &[String]) -> String {
    format!("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n{}END:VCALENDAR\r\n", events.concat())
}

fn domains() -> Vec<Domain> {
    let d = |id: &str, names: &[&str]| Domain {
        id: id.into(),
        calendar_names: names.iter().map(|s| s.to_string()).collect(),
        ..Domain::default()
    };
    vec![
        d("A&C", &["Algorithmique et complexité"]),
        d("L&MC", &["Logique et modèles de calculs"]),
        d("OC", &["Optimisation combinatoire"]),
        d("ACL", &["ACL", "EC 715.1 Analyse et conception des logiciels"]),
        d("Anglais", &["Anglais"]),
    ]
}

#[test]
fn parses_folded_escaped_and_zoned_lines() {
    let text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261211T144500Z\r\nDTEND:20261211T164500Z\r\n\
        SUMMARY:TD 2 Logique et modèles de calculs\r\nLOCATION:Technopole_BRJ-006 (Exam1)\\,Technopo\r\n le_BRJ-008\r\n\
        DESCRIPTION:\\n\\nCOLSON Loïc\\n(Modif\r\n ié le:12/06/2026 17:07)\r\nUID:ADE6032\r\n 2d30\r\nEND:VEVENT\r\n\
        BEGIN:VEVENT\r\nDTSTART;TZID=Europe/Paris:20261005T083000\r\nDTEND;TZID=Europe/Paris:20261005T100000\r\n\
        SUMMARY:Rendez-vous\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261010\r\nSUMMARY:All day\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
    let tz = paris();
    let ev = ade::parse(text, &tz).unwrap();
    assert_eq!(ev.len(), 3);
    assert_eq!(ev[0].uid, "ADE60322d30");
    assert_eq!(ev[0].location, "Technopole_BRJ-006 (Exam1),Technopole_BRJ-008");
    assert!(ev[0].description.contains("Modifié le:12/06/2026 17:07"));
    assert_eq!(tz.to_local(ev[0].start), Local::new(Date::ymd(2026, 12, 11), Hm::new(15, 45)));
    assert_eq!(tz.to_local(ev[1].start), Local::new(Date::ymd(2026, 10, 5), Hm::new(8, 30)));
    assert_eq!(tz.to_local(ev[2].start), Local::new(Date::ymd(2026, 10, 10), Hm(0)));
    assert!(ade::parse("<html>login</html>", &tz).is_err());
}

#[test]
fn titles_give_kind_groups_and_name() {
    let t = ade::read_title("TD1 Algorithmique  et complexité");
    assert_eq!((t.kind, t.groups.clone()), (CourseKind::Tutorial, vec![("TD".into(), "1".into())]));
    assert_eq!(t.name, "Algorithmique et complexité");
    let t = ade::read_title("TP 2 Réseaux");
    assert_eq!(t.groups, vec![("TP".into(), "2".into())]);
    let t = ade::read_title("TP2: EC 715.1 Analyse et conception des logiciels");
    assert_eq!(t.groups, vec![("TP".into(), "2".into())]);
    let t = ade::read_title("TP1 ACL G1");
    assert_eq!(t.groups, vec![("TP".into(), "1".into()), ("G".into(), "1".into())]);
    let t = ade::read_title("TEST ORAL -- TPL Groupe B Anglais");
    assert_eq!((t.kind, t.groups.clone()), (CourseKind::Exam, vec![("GROUPE".into(), "B".into())]));
    assert_eq!(t.name, "Anglais");
    assert_eq!(ade::read_title("Examen écrit Anglais").kind, CourseKind::Exam);
    assert_eq!(ade::read_title("CM ACL: EC 715.1 Analyse et conception des logiciels").kind, CourseKind::Lecture);
    assert_eq!(ade::read_title("TPL02 Anglais").groups, vec![("TPL".into(), "2".into())]);
}

#[test]
fn families_are_offered_and_filter_courses() {
    let tz = paris();
    let text = calendar(&[
        vevent("1", "20261005T060000Z", "20261005T080000Z", "CM Algorithmique et complexité"),
        vevent("2", "20261005T113000Z", "20261005T133000Z", "TD1 Algorithmique et complexité"),
        vevent("3", "20261005T113000Z", "20261005T133000Z", "TD2 Algorithmique et complexité"),
        vevent("4", "20261006T113000Z", "20261006T133000Z", "TP 1 Optimisation combinatoire"),
        vevent("5", "20261006T113000Z", "20261006T133000Z", "TP 3 Optimisation combinatoire"),
        vevent("6", "20261009T060000Z", "20261009T080000Z", "TEST ORAL -- TPL Groupe B Anglais"),
        vevent("7", "20261009T081500Z", "20261009T101500Z", "TEST ORAL -- TPL Groupe B Anglais"),
        vevent("8", "20261009T060000Z", "20261009T080000Z", "TEST ORAL -- TPL Groupe A Anglais"),
        vevent("9", "20261105T091500Z", "20261105T111500Z", "TP1 ACL G1"),
        vevent("10", "20261218T133000Z", "20261218T153000Z", "Examen Logique et modèles de calculs"),
    ]);
    let events = ade::parse(&text, &tz).unwrap();
    let fams = ade::families(&events);
    let names: Vec<&str> = fams.iter().map(|f| f.name.as_str()).collect();
    assert_eq!(names, ["GROUPE", "TD", "TP"], "G has a single value: nothing to ask");
    let tp = fams.iter().find(|f| f.name == "TP").unwrap();
    assert_eq!(tp.values, vec![("1".into(), 2), ("3".into(), 1)]);

    let mut sel = Selection::new();
    sel.insert("TD".into(), vec!["1".into()]);
    sel.insert("TP".into(), vec!["1".into()]);
    sel.insert("GROUPE".into(), vec!["B".into()]);
    let (courses, exams) = ade::timetable(&events, &sel, &domains(), &tz);
    let uids: Vec<&str> = courses.iter().map(|c| c.uid.as_str()).collect();
    assert_eq!(uids, ["1", "2", "4", "6", "7", "9", "10"]);
    assert_eq!(courses.iter().find(|c| c.uid == "9").unwrap().domain.as_deref(), Some("ACL"));
    assert_eq!(courses.iter().find(|c| c.uid == "4").unwrap().domain.as_deref(), Some("OC"));
    // Two oral slots, one exam; the written L&MC exam, in local time.
    assert_eq!(exams.len(), 2);
    let oral = exams.iter().find(|e| e.domain.as_deref() == Some("Anglais")).unwrap();
    assert_eq!(oral.at, Local::new(Date::ymd(2026, 10, 9), Hm::new(8, 0)));
    let lmc = exams.iter().find(|e| e.domain.as_deref() == Some("L&MC")).unwrap();
    assert_eq!(lmc.at, Local::new(Date::ymd(2026, 12, 18), Hm::new(14, 30)));
}

#[test]
fn course_names_suggest_their_folder() {
    let ids = ["A&C", "ACL", "Anglais", "L&MC", "OC", "RESEAUX"];
    let s = |n: &str| ade::suggest_domain(n, &ids);
    assert_eq!(s("Algorithmique et complexité"), Some("A&C"));
    assert_eq!(s("Logique et modèles de calculs"), Some("L&MC"));
    assert_eq!(s("Optimisation combinatoire"), Some("OC"));
    assert_eq!(s("Réseaux"), Some("RESEAUX"));
    assert_eq!(s("ACL: EC 715.1 Analyse et conception des logiciels"), Some("ACL"));
    assert_eq!(s("EC 715.1 Analyse et conception des logiciels"), Some("ACL"));
    assert_eq!(s("Anglais"), Some("Anglais"));
    assert_eq!(s("Gestion de projet"), None);
}

#[test]
fn the_window_slides_and_avoids_the_redirect() {
    let url = "https://planning.univ-lorraine.fr/jsp/custom/modules/plannings/anonymous_cal.jsp?resources=468251&projectId=14&calType=ical&firstDate=2026-09-01&lastDate=2026-09-30";
    let u = ade::window_url(url, Date::ymd(2026, 10, 5));
    assert!(u.contains("firstDate=2026-09-28"), "{u}");
    assert!(u.contains("lastDate=2027-02-02"), "{u}");
    assert!(u.ends_with("&sqlMode=true"), "{u}");
    assert!(u.contains("resources=468251&projectId=14"));
    assert_eq!(ade::window_url("https://example.org/cal.ics", Date::ymd(2026, 10, 5)), "https://example.org/cal.ics");
}

fn ev(uid: &str, summary: &str, start: i64) -> Event {
    Event { uid: uid.into(), summary: summary.into(), location: String::new(), description: String::new(), start, end: start + 7200 }
}

#[test]
fn cancellations_moves_and_bad_downloads() {
    let day = |d: Date, h: i64| d.0 as i64 * 86_400 + h * 3600;
    let mon = Date::ymd(2026, 10, 5);
    let now = day(mon, 5);
    let old = Snapshot {
        fetched: now - 3600,
        events: vec![
            ev("past", "CM OC", day(mon.add(-1), 8)),
            ev("a", "TD 1 Réseaux", day(mon, 8)),
            ev("b", "CM A&C", day(mon.add(1), 6)),
            ev("c", "TD1 A&C", day(mon.add(1), 12)),
            ev("d", "CM OC", day(mon.add(5), 6)),
        ],
    };
    // The TD is gone, the CM moved, TD1 changed UID but kept its time, the
    // OC lecture came back under a new UID at another hour of the same day.
    let new = vec![
        ev("b", "CM A&C", day(mon.add(1), 8)),
        ev("c2", "TD1 A&C", day(mon.add(1), 12)),
        ev("d2", "CM OC", day(mon.add(5), 9)),
        ev("e", "CM L&MC", day(mon.add(2), 6)),
    ];
    let Outcome::Updated { snapshot, changes } = ade::reconcile(Some(&old), Ok(new), now) else { panic!() };
    assert_eq!(snapshot.events.len(), 4);
    let kinds: Vec<(&str, &str)> = changes
        .iter()
        .map(|c| {
            let k = match c {
                Change::Added { .. } => "added",
                Change::Cancelled { .. } => "cancelled",
                Change::Moved { .. } => "moved",
            };
            (k, c.event().uid.as_str())
        })
        .collect();
    assert_eq!(kinds, [("cancelled", "a"), ("moved", "b"), ("added", "e"), ("moved", "d2")]);

    let tz = Tz::utc();
    let tell = ade::worth_telling(&changes, &Selection::new(), &tz, mon);
    let told: Vec<&str> = tell.iter().map(|c| c.event().uid.as_str()).collect();
    assert_eq!(told, ["a", "b"], "only today and tomorrow");

    // An empty or failed download keeps the last good timetable.
    assert_eq!(ade::reconcile(Some(&old), Ok(Vec::new()), now), Outcome::Kept { reason: "empty".into() });
    assert!(matches!(ade::reconcile(Some(&old), Err("timeout".into()), now), Outcome::Kept { .. }));
    // A first download has nothing to compare with.
    assert!(matches!(ade::reconcile(None, Ok(vec![ev("x", "CM", now)]), now), Outcome::Updated { changes, .. } if changes.is_empty()));
}

/// The promotion's real feed, if a capture sits in tests/fixtures (it is
/// kept out of the repository until its owner agrees).
#[test]
fn real_promotion_feed() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/ade-promo.ics");
    let Ok(text) = std::fs::read_to_string(&path) else {
        eprintln!("no {}, skipped", path.display());
        return;
    };
    let tz = paris();
    let events = ade::parse(&text, &tz).unwrap();
    assert!(events.len() > 100);
    let fams = ade::families(&events);
    let values = |n: &str| -> Vec<String> {
        fams.iter().find(|f| f.name == n).map(|f| f.values.iter().map(|v| v.0.clone()).collect()).unwrap_or_default()
    };
    assert_eq!(values("TD"), ["1", "2"]);
    assert_eq!(values("TP"), ["1", "2", "3", "4"]);
    assert_eq!(values("GROUPE"), ["A", "B", "C"]);

    let mut sel = Selection::new();
    for (f, v) in [("TD", "1"), ("TP", "1"), ("GROUPE", "B")] {
        sel.insert(f.into(), vec![v.into()]);
    }
    let (courses, exams) = ade::timetable(&events, &sel, &domains(), &tz);
    assert!(courses.iter().all(|c| !c.title.contains("TD2") && !c.title.contains("TD 2") && !c.title.contains("Groupe A")));
    assert!(courses.iter().any(|c| c.title == "TP1 ACL G1"));
    for c in &courses {
        if c.kind != CourseKind::Exam {
            assert!(c.domain.is_some() || c.title.contains("Réseaux"), "{} has no domain", c.title);
        }
    }
    let oral = exams.iter().find(|e| e.domain.as_deref() == Some("Anglais") && e.at.date == Date::ymd(2026, 10, 9));
    assert_eq!(oral.map(|e| e.at.time), Some(Hm::new(8, 0)));
    assert!(exams.iter().any(|e| e.domain.as_deref() == Some("Anglais") && e.at.date == Date::ymd(2026, 11, 6)));
    assert!(exams.iter().any(|e| e.domain.as_deref() == Some("L&MC") && e.at.date == Date::ymd(2026, 12, 18)));
}
