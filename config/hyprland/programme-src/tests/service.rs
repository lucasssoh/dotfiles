mod common;

use std::collections::{BTreeMap, BTreeSet};

use common::*;

use programme::ajout::{self, Action, Context, Unclear};
use programme::alertes::{self, Kind};
use programme::khal;
use programme::model::*;
use programme::plan::Plan;
use programme::store::{self, Event, Outcome, PartReport, Paths, State, Store};
use programme::time::{Date, Hm, Local, Tz};

fn scratch(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("programme-svc-{}-{name}", std::process::id()));
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
    s.record(Event::Started { session: "2026-10-05-evening1".into(), at: at(MON, "20:40"), planned: None }, now).unwrap();
    s.record(
        Event::Closed {
            session: "2026-10-05-evening1".into(),
            at: now,
            minutes: 70,
            parts: vec![PartReport { task: "course:ALGO".into(), minutes: 70, planned: 75, done: true, note: Some("stuck on the induction".into()) }],
        },
        now,
    )
    .unwrap();
    assert_eq!(s.state.course_days["ALGO"], [(MON, 70)]);
    assert_eq!(s.state.starts, [(MON, hm("20:40"))]);
    assert!(matches!(s.state.outcomes["2026-10-05-evening1"], Outcome::Closed { .. }));
    assert_eq!(s.state.notes.len(), 1);

    // The same state from the file on disk.
    let again = Store::open(Paths::under(&dir)).unwrap();
    assert_eq!(again.state, s.state);

    // Undo the close: the session is started again, its time gone.
    let undone = s.undo(now).unwrap().unwrap();
    assert!(matches!(undone.event, Event::Closed { .. }));
    assert!(!s.state.course_days.contains_key("ALGO"));
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
    push(Event::Project { project: Project { id: "argos".into(), name: "ARGOS".into(), domain: None, due: at(MON.add(20), "18:00"), steps: vec![Step { name: "spec".into(), hours: 4.0, ..Step::default() }], archived: false, dir: None } });
    let part = |task: &str, done: bool| PartReport { task: task.into(), minutes: 30, done, ..PartReport::default() };
    push(Event::Closed {
        session: "2026-10-05-evening1".into(),
        at: at(MON, "22:00"),
        minutes: 0,
        parts: vec![
            part("course:X", true),
            part("prepare:uid-1", true),
            part("campaign:jobs:2026-10-05", true),
            part("interview:jobs:Company F", true),
            part("chore:c1", true),
            part("project:argos:spec", false),
        ],
    });
    push(Event::Missed { session: "2026-10-06-evening1".into() });
    // Two tasks of one evening said "not tonight": one session missed.
    push(Event::Skipped { session: "2026-10-07-evening1~aaaaaa".into(), tasks: vec!["read:X/notes.md".into()], planned: None });
    push(Event::Skipped { session: "2026-10-07-evening1~bbbbbb".into(), tasks: vec!["ask:X/b.md".into()], planned: None });
    let st: State = store::reduce(&entries);
    assert_eq!(st.course_days["X"], [(MON, 30)]);
    assert_eq!(st.progress.prepared, ["uid-1"]);
    assert_eq!(st.progress.campaign_days, [("jobs".to_string(), MON)]);
    assert_eq!(st.progress.interviews_prepared, [("jobs".to_string(), "Company F".to_string())]);
    assert!(st.chores[0].done);
    assert_eq!(st.projects[0].steps[0].spent_minutes, 30);
    assert_eq!(st.missed_streak, 2);
}

#[test]
fn the_old_journal_still_reads_and_loses_nothing() {
    // Lines of the planner before Programme: course files, reading, a game's pause.
    let dir = scratch("legacy");
    std::fs::create_dir_all(dir.join("data")).unwrap();
    let lines = [
        r#"{"seq":1,"logged":"2026-10-05T12:00","ev":"files","items":["A&C/x.md"],"inclusion":"planned"}"#,
        r#"{"seq":2,"logged":"2026-10-05T20:30","ev":"started","session":"2026-10-05-evening1~aaaaaa","at":"2026-10-05T20:30","planned":{"id":"2026-10-05-evening1~aaaaaa","date":"2026-10-05","start":"20:30","end":"21:45","kind":"evening","counted":true,"place":"home","shortened":false,"pinned":false,"parts":[{"task":"study:A&C/x.md","domain":"A&C","minutes":75,"work":"study","item":"A&C/x.md","sections":[1,4],"exercises":null,"timed":false}],"reasons":[]}}"#,
        r#"{"seq":3,"logged":"2026-10-05T20:50","ev":"free-reading","item":"OC/y.md","upto":2,"pages":3,"minutes":12}"#,
        r#"{"seq":4,"logged":"2026-10-05T21:50","ev":"closed","session":"2026-10-05-evening1~aaaaaa","at":"2026-10-05T21:50","minutes":70,"parts":[{"task":"study:A&C/x.md","minutes":70,"planned":75,"done":true,"read_upto":4,"exercises":{"1":"solo"},"assessment":"understood","note":null}],"tracking":{"idle_minutes":0,"game_minutes":0,"media_minutes":0,"media_for_course":null,"pages":{}}}"#,
        r#"{"seq":5,"logged":"2026-10-06T09:00","ev":"pin","pin":{"task":"read:A&C/z.md","date":"2026-10-12","start":"09:05","minutes":26,"work":{"work":"read","item":"A&C/z.md"},"domain":"A&C"}}"#,
    ];
    std::fs::write(dir.join("data/journal.jsonl"), lines.join("\n") + "\n").unwrap();
    let mut s = Store::open(Paths::under(&dir)).unwrap();
    assert_eq!(s.entries.len(), 5, "every line kept");
    assert_eq!(s.state.seq, 5);
    assert!(matches!(s.entries[0].event, Event::Legacy { .. }));
    assert!(matches!(s.state.outcomes["2026-10-05-evening1~aaaaaa"], Outcome::Closed { .. }));
    assert_eq!(s.state.course_days["A&C"], [(MON, 70)], "a session on a course file counts for its subject");
    assert_eq!(s.state.pins.len(), 1);
    assert!(s.state.pins[0].work.is_none(), "a work of the old planner, let go");
    // The next line follows on, and an undo never picks a line it cannot read.
    let seq = s.record(Event::Missed { session: "2026-10-06-evening1".into() }, at(MON.add(1), "22:00")).unwrap();
    assert_eq!(seq, 6);
    assert!(matches!(s.undo(at(MON.add(1), "22:00")).unwrap().unwrap().event, Event::Pin { .. }));
    let _ = std::fs::remove_dir_all(dir);
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
        closed: false, dir: None
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

    assert!(matches!(p("libre 1h30 école").unwrap().action, Action::Free { minutes: 90, place: programme::journee::Place::School }));

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
    let eve = p.sessions.iter().find(|x| x.date == MON && !x.parts.is_empty()).unwrap();
    assert_eq!(eve.start, hm("20:30"));
    // The evening's last task, one after the other.
    let last = p.sessions.iter().filter(|x| x.date == MON && x.counted).map(|x| x.end).max().unwrap();

    let all = alertes::planned(&p, &st, s, MON);
    let kinds: Vec<(Kind, String)> = all.iter().filter(|a| a.at.date == MON).map(|a| (a.kind, a.at.time.to_string())).collect();
    // Start, reminder, then the recap of Tuesday once Monday's session ends.
    assert_eq!(kinds[0], (Kind::Start, "20:30".into()));
    assert_eq!(kinds[1], (Kind::Reminder, "20:45".into()));
    assert!(kinds.contains(&(Kind::Recap, last.to_string())));

    // Nothing before its time; the start at 20:30; the next wake is the reminder.
    assert!(alertes::due(&p, &st, s, &sent, at(MON, "20:29")).is_empty());
    let due = alertes::due(&p, &st, s, &sent, at(MON, "20:30"));
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].kind, Kind::Start);
    let mut sent: BTreeSet<String> = due.iter().map(|a| a.key.clone()).collect();
    assert_eq!(alertes::next(&p, &st, s, &sent, at(MON, "20:30")), Some(at(MON, "20:45")));

    // Started: no reminder, and the next task of the evening keeps quiet
    // while this one is under way.
    let mut started = State::default();
    started.outcomes.insert(eve.id.clone(), Outcome::Started { at: at(MON, "20:35") });
    assert!(alertes::due(&p, &started, s, &sent, at(MON, "20:46")).iter().all(|a| a.kind != Kind::Reminder));
    assert!(alertes::due(&p, &started, s, &sent, Local::new(MON, eve.end)).iter().all(|a| a.kind == Kind::Recap));

    // Postponed to 21:00: a new start then.
    let mut later = State::default();
    later.outcomes.insert(eve.id.clone(), Outcome::Postponed { to: at(MON, "21:00") });
    let due = alertes::due(&p, &later, s, &sent, at(MON, "21:00"));
    assert_eq!((due.len(), due[0].kind, due[0].at), (1, Kind::Start, at(MON, "21:00")));

    // Waking at 20:52 after sleep: one alert, not the start and its reminder.
    sent.clear();
    let due = alertes::due(&p, &st, s, &sent, at(MON, "20:52"));
    assert_eq!(due.len(), 1, "{due:?}");
    // Waking after the evening: nothing, it goes to the check-in.
    let late = Local::new(MON, last.plus(5));
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
        assert!(name.starts_with("programme-") && name.ends_with(".ics"));
        assert_eq!(text.matches("BEGIN:VEVENT").count(), 1);
        assert!(text.lines().all(|l| l.len() <= 76), "folded");
    }
    // One file per task of the evening, the first at 20:30.
    let monday: Vec<&String> = files.iter().filter(|(n, _)| n.starts_with("programme-2026-10-05-evening1_")).map(|(_, t)| t).collect();
    assert!(monday.len() >= 2, "{monday:?}");
    assert!(monday.iter().any(|t| t.contains("DTSTART:20261005T183000Z")), "{monday:?}");

    let dir = scratch("khal");
    std::fs::write(dir.join("mine.ics"), "not Programme's").unwrap();
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

#[test]
fn not_tonight_can_be_taken_back() {
    let mut entries = Vec::new();
    let push = |entries: &mut Vec<store::Entry>, event: Event| {
        let seq = entries.len() as u64 + 1;
        entries.push(store::Entry { seq, at: at(MON, "20:00"), event });
    };
    push(&mut entries, Event::Skipped { session: "2026-10-05-evening1~aaaaaa".into(), tasks: vec!["read:X/a.md".into()], planned: None });
    let st = store::reduce(&entries);
    assert_eq!(st.skipped.len(), 1);
    push(&mut entries, Event::Undo { of: 1 });
    let st = store::reduce(&entries);
    assert!(st.skipped.is_empty() && st.outcomes.is_empty() && st.missed_streak == 0, "as if never said");
}

#[test]
fn later_until_holds_its_time_and_back_frees_the_rest() {
    let mut entries = Vec::new();
    let push = |entries: &mut Vec<store::Entry>, logged: Local, event: Event| {
        let seq = entries.len() as u64 + 1;
        entries.push(store::Entry { seq, at: logged, event });
    };
    push(&mut entries, at(MON, "20:00"), Event::Away { until: at(MON.add(1), "00:00") });
    let st = store::reduce(&entries);
    assert_eq!(st.away.len(), 1);
    assert_eq!((st.away[0].start, st.away[0].end), (at(MON, "20:00"), at(MON.add(1), "00:00")));
    assert!(st.outcomes.is_empty() && st.missed_streak == 0, "said, not missed");
    push(&mut entries, at(MON, "21:10"), Event::Back { at: at(MON, "21:10") });
    let st = store::reduce(&entries);
    assert_eq!(st.away[0].end, at(MON, "21:10"), "the time before stays taken");
}

// ─── A session's command and window ──────────────────────────────────────────

#[test]
fn a_subject_runs_its_command_on_its_folder() {
    let mut d = Domain { id: "A&C".into(), ..Domain::default() };
    assert_eq!(d.launch_args(Some(std::path::Path::new("/c"))), None, "no command, nothing opened");
    d.launch = Some(BOUSSOLE_LAUNCH.into());
    assert_eq!(d.launch_args(Some(std::path::Path::new("/home/me/courses"))).unwrap(), ["boussole", "open", "/home/me/courses/A&C", "--resume"]);
    d.launch = Some(r#"liseuse "{folder}/00 Index.md""#.into());
    assert_eq!(d.launch_args(Some(std::path::Path::new("/c"))).unwrap(), ["liseuse", "/c/A&C/00 Index.md"]);
    d.launch = Some("  ".into());
    assert_eq!(d.launch_args(None), None);
}

#[test]
fn only_boussole_in_firefox_counts() {
    use programme::seance::{is_course_window, Watch};
    assert!(is_course_window("org.mozilla.firefox", "Boussole — Mozilla Firefox"));
    assert!(!is_course_window("org.mozilla.firefox", "YouTube — Mozilla Firefox"));
    assert!(!is_course_window("brave-browser", "Boussole"));
    let mut w = Watch { session: "s".into(), watched: true, ..Watch::default() };
    w.set_counting(true, 1000);
    w.set_counting(false, 1600);
    w.set_counting(false, 1700);
    w.set_counting(true, 2000);
    assert_eq!(w.effective(2300), 900, "ten minutes, then five");
}
