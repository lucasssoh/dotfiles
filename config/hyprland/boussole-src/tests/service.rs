mod common;

use std::collections::{BTreeMap, BTreeSet};

use common::*;

use boussole::ajout::{self, Action, Context, Unclear};
use boussole::alertes::{self, Kind};
use boussole::catalogue::Inclusion;
use boussole::khal;
use boussole::model::*;
use boussole::plan::Plan;
use boussole::store::{self, Event, Outcome, PartReport, Paths, State, Store};
use boussole::time::{Date, Hm, Local, Tz};

fn scratch(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("boussole-svc-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

// ─── Journal ─────────────────────────────────────────────────────────────────

#[test]
fn the_state_is_rebuilt_from_the_journal_and_undo_is_one_more_line() {
    let dir = scratch("journal");
    let mut s = Store::open(Paths::under(&dir)).unwrap();
    let now = at(MON, "21:50");
    let a = "ALGO/Ch1/10_Bloc/11_A.md";
    s.record(Event::Files { items: vec![a.into()], inclusion: Inclusion::Planned }, now).unwrap();
    s.record(Event::Started { session: "2026-10-05-evening1".into(), at: at(MON, "20:40") }, now).unwrap();
    let mut ex = BTreeMap::new();
    ex.insert(1, Exercise::Solo);
    ex.insert(2, Exercise::Failed);
    s.record(
        Event::Closed {
            session: "2026-10-05-evening1".into(),
            at: now,
            minutes: 70,
            parts: vec![PartReport {
                task: format!("study:{a}"),
                minutes: 70,
                planned: 75,
                done: false,
                read_upto: Some(4),
                exercises: ex,
                assessment: Some(Assessment::Blocked),
                note: Some("stuck on the induction".into()),
            }],
            tracking: None,
        },
        now,
    )
    .unwrap();
    let p = &s.state.progress.items[a];
    assert_eq!((p.read_upto, p.exercises.len(), p.last_on, p.question_open), (4, 2, Some(MON), true));
    assert_eq!(s.state.starts, [(MON, hm("20:40"))]);
    assert!(matches!(s.state.outcomes["2026-10-05-evening1"], Outcome::Closed { .. }));
    assert_eq!(s.state.notes.len(), 1);

    // The same state from the file on disk.
    let again = Store::open(Paths::under(&dir)).unwrap();
    assert_eq!(again.state, s.state);

    // Undo the close: the session is started again, the progress gone.
    let undone = s.undo(now).unwrap().unwrap();
    assert!(matches!(undone.event, Event::Closed { .. }));
    assert!(!s.state.progress.items.contains_key(a) || s.state.progress.items[a].read_upto == 0);
    assert!(matches!(s.state.outcomes["2026-10-05-evening1"], Outcome::Started { .. }));
    // A second undo goes one further back, never undoing the undo.
    assert!(matches!(s.undo(now).unwrap().unwrap().event, Event::Started { .. }));
    assert_eq!(Store::open(Paths::under(&dir)).unwrap().state, s.state);

    // A line cut by a crash is skipped.
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new().append(true).open(dir.join("data/journal.jsonl")).unwrap();
    f.write_all(b"{\"seq\":99,\"at\":\"2026-10").unwrap();
    assert_eq!(Store::open(Paths::under(&dir)).unwrap().state, s.state);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn every_kind_of_part_moves_progress() {
    let mut entries = Vec::new();
    let mut seq = 0;
    let mut push = |ev: Event| {
        seq += 1;
        entries.push(store::Entry { seq, at: at(MON, "22:00"), event: ev });
    };
    push(Event::Chore { chore: Chore { id: "c1".into(), title: "x".into(), domain: None, file: None, minutes: 30, due: None, done: false } });
    push(Event::Project { project: Project { id: "argos".into(), name: "ARGOS".into(), domain: None, due: at(MON.add(20), "18:00"), steps: vec![Step { name: "spec".into(), hours: 4.0, ..Step::default() }], archived: false } });
    let part = |task: &str, done: bool| PartReport { task: task.into(), minutes: 30, done, ..PartReport::default() };
    push(Event::Closed {
        session: "2026-10-05-evening1".into(),
        at: at(MON, "22:00"),
        minutes: 0,
        parts: vec![
            part("review1:X/a.md", true),
            part("exam:X/93.md#2", true),
            part("prepare:uid-1", true),
            part("campaign:jobs:2026-10-05", true),
            part("interview:jobs:Company F", true),
            part("chore:c1", true),
            part("project:argos:spec", false),
            part("read:X/notes.md", true),
            part("ask:X/b.md", true),
        ],
        tracking: None,
    });
    push(Event::Missed { session: "2026-10-06-evening1".into() });
    push(Event::Skipped { session: "2026-10-07-evening1".into() });
    let st: State = store::reduce(&entries);
    assert_eq!(st.progress.items["X/a.md"].reviews_done, [MON]);
    assert_eq!(st.progress.items["X/93.md"].subjects_done, 2);
    assert_eq!(st.progress.prepared, ["uid-1"]);
    assert_eq!(st.progress.campaign_days, [("jobs".to_string(), MON)]);
    assert_eq!(st.progress.interviews_prepared, [("jobs".to_string(), "Company F".to_string())]);
    assert!(st.chores[0].done);
    assert_eq!(st.projects[0].steps[0].spent_minutes, 30);
    assert!(st.progress.items["X/notes.md"].done);
    assert_eq!(st.missed_streak, 2);
}

#[test]
fn the_pace_is_measured_from_closed_sessions() {
    let mut entries = Vec::new();
    for (i, (actual, planned)) in [(90, 75), (80, 75), (100, 75)].into_iter().enumerate() {
        let mut pages = BTreeMap::new();
        pages.insert(format!("A&C/Ch/1{i}_S.md"), 10u32);
        entries.push(store::Entry {
            seq: i as u64 + 1,
            at: at(MON.add(i as i32), "22:00"),
            event: Event::Closed {
                session: format!("{}-evening1", MON.add(i as i32)),
                at: at(MON.add(i as i32), "22:00"),
                minutes: actual,
                parts: vec![PartReport { task: format!("study:A&C/Ch/1{i}_S.md"), minutes: actual, planned, ..PartReport::default() }],
                tracking: Some(store::Tracking { pages, ..store::Tracking::default() }),
            },
        });
    }
    let st = store::reduce(&entries);
    let f = st.factor("A&C").unwrap();
    assert!((f - 270.0 / 225.0).abs() < 1e-3, "{f}");
    assert_eq!(st.factor("OC"), None);
    assert!((st.minutes_per_page("A&C").unwrap() - 9.0).abs() < 1e-3);
    // Free reading is kept for the next close, never as done.
    let mut e2 = entries.clone();
    e2.push(store::Entry { seq: 9, at: at(MON, "18:00"), event: Event::FreeReading { item: "OC/x.md".into(), upto: 2, pages: 3, minutes: 12 } });
    let st = store::reduce(&e2);
    assert_eq!(st.free_reading["OC/x.md"], (MON, 2));
    assert!(st.progress.items.get("OC/x.md").is_none());
}

// ─── Quick add ───────────────────────────────────────────────────────────────

fn cx<'a>(domains: &'a [String], campaigns: &'a [Campaign], projects: &'a [(String, String, Option<String>)], lang: Lang) -> Context<'a> {
    Context { today: MON, lang, domains, projects, campaigns }
}

#[test]
fn quick_add_understands_or_says_what_is_missing() {
    let domains: Vec<String> = ["A&C", "L&MC", "OC", "ACL"].map(String::from).to_vec();
    let projects = vec![("argos".to_string(), "ARGOS".to_string(), Some("ACL".to_string()))];
    let campaigns = vec![Campaign {
        id: "jobs".into(),
        name: "Alternance".into(),
        start: MON,
        end: MON.add(27),
        school_day_minutes: 30,
        free_day_minutes: 120,
        weekly_target: 8,
        rows: Vec::new(),
        closed: false,
    }];
    let c = cx(&domains, &campaigns, &projects, Lang::Fr);
    let p = |l: &str| ajout::parse(l, &c);

    let u = p("examen L&MC 18/12").unwrap();
    assert_eq!(u.sentence, "Examen L&MC, ven. 18 déc.");
    let Action::Deadline(d) = u.action else { panic!() };
    assert_eq!((d.kind, d.domain.as_deref(), d.at.date), (DeadlineKind::Exam, Some("L&MC"), Date::ymd(2026, 12, 18)));

    let Action::Deadline(d) = p("cc oc 12/11 14h").unwrap().action else { panic!() };
    assert_eq!((d.kind, d.domain.as_deref(), d.at), (DeadlineKind::Cc, Some("OC"), at(Date::ymd(2026, 11, 12), "14:00")));

    let u = p("rendu ARGOS 12/11 30h").unwrap();
    let Action::Deadline(d) = u.action else { panic!() };
    assert_eq!((d.kind, d.hours, d.domain.as_deref()), (DeadlineKind::Due, Some(30.0), Some("ACL")));
    assert!(u.sentence.contains("30 h de travail"), "{}", u.sentence);
    let Action::Deadline(d) = p("rendu ARGOS 12/11 14h 30h").unwrap().action else { panic!() };
    assert_eq!((d.at.time, d.hours), (hm("14:00"), Some(30.0)));

    let Action::Busy(b) = p("indispo sam 14h-18h").unwrap().action else { panic!() };
    assert_eq!((b.start, b.end), (at(MON.add(5), "14:00"), at(MON.add(5), "18:00")));

    let Action::Chore(t) = p("tâche relire TD3 A&C 45m").unwrap().action else { panic!() };
    assert_eq!((t.title.as_str(), t.domain.as_deref(), t.minutes), ("relire TD3", Some("A&C"), 45));

    let u = p("candidature Entreprise F").unwrap();
    assert_eq!(u.action, Action::Apply { campaign: "jobs".into(), company: "Entreprise F".into() });

    assert!(matches!(p("libre 1h30 école").unwrap().action, Action::Free { minutes: 90, place: boussole::journee::Place::School }));

    // Dates: a passed day of the year means next year; weekdays come next.
    let Action::Deadline(d) = p("examen OC 02/10").unwrap().action else { panic!() };
    assert_eq!(d.at.date, Date::ymd(2027, 10, 2));
    let Action::Busy(b) = p("indispo lun 9h-10h").unwrap().action else { panic!() };
    assert_eq!(b.start.date, MON, "today is Monday");

    // Never a guess.
    assert_eq!(p("examen 18/12"), Err(Unclear::Missing("domain")));
    assert_eq!(p("examen L&MC"), Err(Unclear::Missing("date")));
    assert_eq!(p("examen L&MC 18/12 salle"), Err(Unclear::Extra("salle".into())));
    assert_eq!(p("indispo sam"), Err(Unclear::Missing("time")));
    assert_eq!(p("indispo sam 18h-14h"), Err(Unclear::Extra("18h-14h".into())));
    assert_eq!(p("tâche relire"), Err(Unclear::Missing("duration")));
    assert!(matches!(p("réunion demain"), Err(Unclear::Kind(_))));
    assert_eq!(ajout::parse("candidature X", &cx(&domains, &[], &projects, Lang::Fr)), Err(Unclear::NoCampaign));
    assert_eq!(ajout::explain(&Unclear::Missing("date"), Lang::Fr), "Il manque la date.");

    let en = cx(&domains, &campaigns, &projects, Lang::En);
    assert_eq!(ajout::parse("exam L&MC 18/12", &en).unwrap().sentence, "L&MC exam, Fri Dec 18.");
}

// ─── Alerts ──────────────────────────────────────────────────────────────────

fn plan_and_state() -> (Fx, Plan) {
    let fx = Fx::new("alerts");
    let p = fx.plan(at(MON, "06:00"));
    (fx, p)
}

#[test]
fn alerts_fall_at_the_right_time_and_never_pile_up() {
    let (fx, p) = plan_and_state();
    let st = State::default();
    let s = &fx.settings;
    let sent = BTreeSet::new();
    let eve = p.sessions.iter().find(|x| x.date == MON).unwrap();
    assert_eq!(eve.start, hm("20:30"));

    let all = alertes::planned(&p, &st, s, MON);
    let kinds: Vec<(Kind, String)> = all.iter().filter(|a| a.at.date == MON).map(|a| (a.kind, a.at.time.to_string())).collect();
    // Start, reminder, then the recap of Tuesday once Monday's session ends.
    assert_eq!(kinds[0], (Kind::Start, "20:30".into()));
    assert_eq!(kinds[1], (Kind::Reminder, "20:45".into()));
    assert!(kinds.contains(&(Kind::Recap, eve.end.to_string())));

    // Nothing before its time; the start at 20:30; the next wake is the reminder.
    assert!(alertes::due(&p, &st, s, &sent, at(MON, "20:29")).is_empty());
    let due = alertes::due(&p, &st, s, &sent, at(MON, "20:30"));
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].kind, Kind::Start);
    let mut sent: BTreeSet<String> = due.iter().map(|a| a.key.clone()).collect();
    assert_eq!(alertes::next(&p, &st, s, &sent, at(MON, "20:30")), Some(at(MON, "20:45")));

    // Started: no reminder.
    let mut started = State::default();
    started.outcomes.insert(eve.id.clone(), Outcome::Started { at: at(MON, "20:35") });
    assert!(alertes::due(&p, &started, s, &sent, at(MON, "20:46")).iter().all(|a| a.kind != Kind::Reminder));

    // Postponed to 21:00: a new start then.
    let mut later = State::default();
    later.outcomes.insert(eve.id.clone(), Outcome::Postponed { to: at(MON, "21:00") });
    let due = alertes::due(&p, &later, s, &sent, at(MON, "21:00"));
    assert_eq!((due.len(), due[0].kind, due[0].at), (1, Kind::Start, at(MON, "21:00")));

    // Waking at 20:52 after sleep: one alert, not the start and its reminder.
    sent.clear();
    let due = alertes::due(&p, &st, s, &sent, at(MON, "20:52"));
    assert_eq!(due.len(), 1, "{due:?}");
    // Waking after the session: nothing, it goes to the check-in.
    let late = Local::new(MON, eve.end.plus(5));
    assert!(alertes::due(&p, &st, s, &sent, late).iter().all(|a| a.kind == Kind::Recap));
    let gone = alertes::expired(&p, &st, s, &sent, late);
    assert!(gone.iter().any(|k| k.starts_with("start:")));
    // Nothing at night; the next wake is the morning.
    assert!(alertes::due(&p, &st, s, &sent, at(MON, "23:30")).is_empty());
    let all_sent: BTreeSet<String> = alertes::planned(&p, &st, s, MON).into_iter().filter(|a| a.at.date == MON).map(|a| a.key).collect();
    let next = alertes::next(&p, &st, s, &all_sent, at(MON, "23:30")).unwrap();
    assert!(next.date == MON.add(1) && next.time >= hm("06:00"), "{next}");
}

// ─── khal ────────────────────────────────────────────────────────────────────

#[test]
fn khal_files_one_uid_each_rewritten_only_when_they_change() {
    let (_, p) = plan_and_state();
    let tz = Tz::named("Europe/Paris").unwrap();
    let files = khal::study_files(&p.sessions, &tz, Lang::Fr);
    assert!(!files.is_empty());
    for (name, text) in &files {
        assert!(name.starts_with("boussole-") && name.ends_with(".ics"));
        assert_eq!(text.matches("BEGIN:VEVENT").count(), 1);
        assert!(text.lines().all(|l| l.len() <= 76), "folded");
    }
    let monday = &files["boussole-2026-10-05-evening1.ics"];
    assert!(monday.contains("DTSTART:20261005T183000Z"), "{monday}");

    let dir = scratch("khal");
    std::fs::write(dir.join("mine.ics"), "not Boussole's").unwrap();
    std::fs::write(dir.join("boussole-old.ics"), "stale").unwrap();
    assert!(khal::sync(&dir, &files).unwrap());
    assert!(!khal::sync(&dir, &files).unwrap(), "nothing changed the second time");
    assert!(dir.join("mine.ics").exists() && !dir.join("boussole-old.ics").exists());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn personal_events_from_khal_list() {
    let cfg = khal::read_config(
        "[calendars]\n[[personal]]\npath = ~/x\n[[etude]]\npath = ~/y\n[locale]\ndateformat = %d/%m/%Y\ndatetimeformat = %d/%m/%Y %H:%M\n",
    );
    assert_eq!(cfg.calendars, ["personal", "etude"]);
    let args = khal::list_args(&cfg, MON, 120);
    assert!(args.windows(2).any(|w| w == ["-d", "etude"]));
    assert!(!args.contains(&"cours".to_string()), "an undeclared calendar is not excluded");
    assert!(!args.contains(&"--once".to_string()));
    assert_eq!(&args[args.len() - 2..], ["05/10/2026", "120d"]);
    let out = "[]\n[{\"start\": \"07/10/2026 21:00\", \"end\": \"07/10/2026 22:00\", \"title\": \"Appel\", \"all-day\": \"False\", \"uid\": \"p1\"}]\n\
               [{\"start\": \"10/10/2026\", \"end\": \"10/10/2026\", \"title\": \"Mariage\", \"all-day\": \"True\", \"uid\": \"p2\"}]\n\
               [{\"start\": \"14/10/2026 21:00\", \"end\": \"14/10/2026 22:00\", \"title\": \"Appel\", \"all-day\": \"False\", \"uid\": \"p1\"}]\n";
    let busy = khal::parse_list(out, &cfg);
    assert_eq!(busy.len(), 3, "a weekly event twice");
    assert_eq!((busy[0].start, busy[0].end), (at(MON.add(2), "21:00"), at(MON.add(2), "22:00")));
    assert_eq!((busy[1].start, busy[1].end), (at(MON.add(5), "00:00"), at(MON.add(6), "00:00")));
    assert_eq!(khal::format("%d/%m/%Y %H:%M", Local::new(MON, Hm::new(9, 5))), "05/10/2026 09:05");
}
