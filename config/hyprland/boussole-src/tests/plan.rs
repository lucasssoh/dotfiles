mod common;

use common::*;

use boussole::journee::{Place, SlotKind};
use boussole::model::*;
use boussole::plan::{Change, Pin, Plan, Reason, Work};
use boussole::time::Date;

/// The days of a subject's sessions.
fn course_days(p: &Plan, domain: &str) -> Vec<Date> {
    parts(p)
        .into_iter()
        .filter(|(_, _, part)| part.domain.as_deref() == Some(domain) && part.work == Work::Course)
        .map(|(d, _, _)| d)
        .collect()
}

/// Minutes of each subject's sessions before `until`.
fn minutes_before(p: &Plan, until: Date) -> std::collections::BTreeMap<String, i32> {
    let mut m = std::collections::BTreeMap::new();
    for (d, _, part) in parts(p) {
        if d < until && part.work == Work::Course {
            *m.entry(part.domain.clone().unwrap()).or_insert(0) += part.minutes;
        }
    }
    m
}

fn project(id: &str, due: Date, hours: &[f32]) -> Project {
    Project {
        id: id.into(),
        name: id.into(),
        domain: Some("NET".into()),
        due: at(due, "18:00"),
        steps: hours
            .iter()
            .enumerate()
            .map(|(i, h)| Step { name: format!("step {}", i + 1), hours: *h, ..Step::default() })
            .collect(),
        archived: false,
        dir: None,
    }
}

#[test]
fn sessions_respect_the_day() {
    let fx = Fx::new("invariants");
    let p = fx.plan(at(MON, "06:00"));
    assert!(!p.sessions.is_empty());
    for s in &p.sessions {
        assert!(s.end <= hm("22:15"), "{} ends at {}", s.id, s.end);
        let used: i32 = s.parts.iter().map(|p| p.minutes).sum();
        assert!(used <= s.end.0 - s.start.0, "{} overfull", s.id);
        let wd = s.date.weekday();
        assert!(wd != 4 && wd != 5, "{}: Friday and Saturday hold no counted session", s.id);
        if wd < 5 {
            assert!(s.end <= hm("12:00") || s.start >= hm("13:30"), "{} on the gym", s.id);
        } else {
            assert!(s.start >= hm("10:00") && s.end <= hm("19:00"), "{} outside Sunday's range", s.id);
        }
        for c in fx.courses.iter().filter(|c| c.start.date == s.date) {
            assert!(s.end <= c.start.time || s.start >= c.end.time, "{} on a course", s.id);
        }
    }
    let sundays: Vec<_> = p.sessions.iter().filter(|s| s.date == MON.add(6)).collect();
    assert_eq!(sundays.iter().map(|s| s.slot()).collect::<std::collections::BTreeSet<_>>().len(), 2, "two blocks");
    assert!(sundays.iter().all(|s| s.parts.len() <= 1), "one task per session");
    assert!(sundays.iter().all(|s| s.kind == SlotKind::Block));
    // Same input, same plan.
    assert_eq!(p, fx.plan(at(MON, "06:00")));
}

#[test]
fn a_missed_session_slides_and_nothing_is_lost() {
    let fx = Fx::new("missed");
    let p0 = fx.plan(at(MON, "06:00"));
    let monday: Vec<String> = p0.sessions.iter().filter(|s| s.date == MON).flat_map(|s| s.parts.iter().map(|p| p.task.clone())).collect();
    assert!(!monday.is_empty());
    let p1 = fx.replan(at(MON.add(1), "06:00"), &p0);
    // A subject's sessions go on: Monday's missed one is not owed.
    for task in monday.iter().filter(|t| !t.starts_with("course:")) {
        let moved = p1.changes.iter().any(|c| matches!(c, Change::Moved { task: t, from, .. } if t == task && *from == MON));
        assert!(moved, "{task} moved without a word: {:?}", p1.changes);
        assert!(first_date(&p1, task).is_some_and(|d| d > MON), "{task} lost");
    }
    // Every task of the old plan is still there, or said to be past the horizon.
    for (_, _, part) in parts(&p0) {
        let kept = first_date(&p1, &part.task).is_some();
        let said = p1.changes.iter().any(|c| matches!(c, Change::Unplaced { task, .. } if *task == part.task));
        let past_tutorial = part.task.starts_with("prepare:");
        assert!(kept || said || past_tutorial, "{} vanished", part.task);
    }
}

#[test]
fn a_session_is_one_subject_for_the_rest_of_its_slot() {
    let fx = Fx::new("course");
    let p = fx.plan(at(MON, "06:00"));
    let courses: Vec<_> = parts(&p).into_iter().filter(|(_, _, x)| x.work == Work::Course).collect();
    assert!(!courses.is_empty());
    for (_, s, x) in &courses {
        assert_eq!(x.task, format!("course:{}", x.domain.as_deref().unwrap()));
        assert_eq!(x.minutes, s.end.0 - s.start.0, "{}: the whole of what is left", s.id);
        assert!(x.minutes >= fx.settings.rhythm.min_session);
    }
}

#[test]
fn projects_are_spread_and_finished_three_days_ahead() {
    let mut fx = Fx::new("project");
    fx.settings.project_bias = 1.4;
    let due = MON.add(21);
    fx.projects.push(project("ARGOS", due, &[5.0, 5.0]));
    let p = fx.plan(at(MON, "06:00"));
    let work: Vec<(Date, i32)> = parts(&p)
        .into_iter()
        .filter(|(_, _, x)| matches!(x.work, Work::Project { .. }))
        .map(|(d, _, x)| (d, x.minutes))
        .collect();
    assert_eq!(work.iter().map(|w| w.1).sum::<i32>(), 840, "10 h × 1.4");
    assert!(work.iter().all(|w| w.0 <= due.add(-3)));
    assert!(work.first().unwrap().0 < MON.add(5), "starts early");
    assert!(work.last().unwrap().0 >= MON.add(12), "spread, not crammed");
    assert!(!p.changes.iter().any(|c| matches!(c, Change::AtRisk { .. })));

    // Too much for the time left: said, never squeezed.
    fx.projects[0] = project("ARGOS", MON.add(10), &[60.0]);
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.changes.iter().any(|c| matches!(c, Change::AtRisk { task, missing_minutes, .. } if task.starts_with("project:ARGOS") && *missing_minutes > 0)));
    assert!(course_days(&p, "ALGO").iter().all(|d| *d > MON.add(7)), "course sessions give way, the project does not");
}

#[test]
fn a_hand_in_with_hours() {
    let mut fx = Fx::new("handin");
    fx.deadlines.push(Deadline {
        id: "rendu".into(),
        domain: Some("NET".into()),
        kind: DeadlineKind::Due,
        at: at(MON.add(12), "14:00"),
        title: "TP report".into(),
        source: Source::Manual,
        hours: Some(3.0),
        spent_minutes: 60,
    });
    let p = fx.plan(at(MON, "06:00"));
    let m: i32 = parts(&p).into_iter().filter(|(_, _, x)| x.task.starts_with("project:rendu")).map(|(d, _, x)| {
        assert!(d <= MON.add(9));
        x.minutes
    }).sum();
    assert_eq!(m, 120);
}

#[test]
fn an_exam_coming_weighs_more() {
    let mut fx = Fx::new("exam");
    let even = minutes_before(&fx.plan(at(MON, "06:00")), MON.add(14));
    fx.exam("LOGIC", MON.add(12));
    let p = fx.plan(at(MON, "06:00"));
    let before = minutes_before(&p, MON.add(12));
    assert!(before["LOGIC"] > before["ALGO"] && before["LOGIC"] > before["NET"], "{before:?}");
    assert!(before["LOGIC"] > even["LOGIC"] * 12 / 14, "{even:?} → {before:?}");
    let why = p.sessions.iter().filter(|s| s.course() == Some("LOGIC")).flat_map(|s| &s.reasons).any(|r| matches!(r, Reason::Deadline { title, .. } if title == "Exam LOGIC"));
    assert!(why, "and says why");
    // Nothing for it once its last exam is over and its courses with it.
    fx.courses.retain(|c| c.domain.as_deref() != Some("LOGIC"));
    let p = fx.plan(at(MON, "06:00"));
    assert!(course_days(&p, "LOGIC").iter().all(|d| *d <= MON.add(12)), "{:?}", course_days(&p, "LOGIC"));
}

#[test]
fn optional_slots_offer_a_head_start() {
    let fx = Fx::new("offers");
    let p = fx.plan(at(MON, "06:00"));
    let sat: Vec<_> = p.offers.iter().filter(|o| o.date == MON.add(5)).collect();
    assert!(!sat.is_empty());
    assert!(sat.iter().all(|o| !o.counted && o.kind == SlotKind::Bonus && o.reasons == [Reason::HeadStart]));
    let gaps: Vec<_> = p.offers.iter().filter(|o| o.kind == SlotKind::Gap).collect();
    assert!(!gaps.is_empty());
    for g in gaps {
        assert_eq!(g.place, Place::School);
        assert!(g.parts.iter().filter(|x| x.work == Work::Course).count() <= 1, "one subject at most");
        assert!(!(g.start < hm("13:30") && g.end > hm("12:00")), "never the gym");
    }
}

#[test]
fn catching_up_after_days_without_the_computer() {
    let fx = Fx::new("catchup");
    let p0 = fx.plan(at(MON, "06:00"));
    let p1 = fx.replan(at(MON.add(4), "19:00"), &p0);
    assert!(p1.sessions.iter().all(|s| s.date >= MON.add(4)));
    let missed: Vec<_> = p0.sessions.iter().filter(|s| s.date < MON.add(4)).flat_map(|s| &s.parts).collect();
    for m in missed.iter().filter(|m| !m.task.starts_with("prepare:") && !m.task.starts_with("course:")) {
        assert!(first_date(&p1, &m.task).is_some(), "{} lost", m.task);
        assert!(p1.changes.iter().any(|c| matches!(c, Change::Moved { task, .. } if *task == m.task)), "{} silent", m.task);
    }    for d in ["ALGO", "LOGIC", "NET"] {
        assert!(!course_days(&p1, d).is_empty(), "{d} goes on");
    }
}

#[test]
fn tutorials_follow_the_timetable() {
    let mut fx = Fx::new("tutorials");
    let td = fx.courses.iter().find(|c| c.kind == CourseKind::Tutorial && c.start.date == MON.add(7)).unwrap().clone();
    let key = format!("prepare:{}", td.uid);
    let p = fx.plan(at(MON, "06:00"));
    let d = first_date(&p, &key).expect("prepared");
    assert!(d < td.start.date && d >= td.start.date.add(-3));
    // Cancelled in ADE: nothing to prepare any more.
    fx.courses.retain(|c| c.uid != td.uid);
    let p = fx.plan(at(MON, "06:00"));
    assert!(first_date(&p, &key).is_none());
}

#[test]
fn the_campaign_gets_its_time() {
    let mut fx = Fx::new("campaign");
    fx.campaigns.push(Campaign {
        id: "jobs".into(),
        name: "Work-study".into(),
        start: MON,
        end: MON.add(11),
        school_day_minutes: 30,
        free_day_minutes: 120,
        weekly_target: 8,
        rows: vec![Row { name: "Company F".into(), status: RowStatus::Interview, sent: Some(MON.add(-8)), interview: Some(at(MON.add(9), "10:00")) }],
        closed: false,
        dir: None,
    });
    let p = fx.plan(at(MON, "06:00"));
    // Friday evening is free, and that Friday has no gap.
    for day in (0..12).map(|i| MON.add(i)).filter(|d| d.weekday() < 4) {
        let c: Vec<_> = parts(&p).into_iter().filter(|(d, _, x)| *d == day && matches!(x.work, Work::Campaign { .. })).collect();
        assert_eq!(c.len(), 1, "{day}: 30 minutes each school day");
        assert_eq!(c[0].2.minutes, 30);
        if day.weekday() == 3 {
            assert_eq!((c[0].1.kind, c[0].1.place), (SlotKind::Gap, Place::School), "a gap at school when there is one");
        }
    }
    let prep: Vec<_> = parts(&p).into_iter().filter(|(_, _, x)| matches!(x.work, Work::Interview { .. })).collect();
    assert_eq!(prep.len(), 1);
    assert_eq!((prep[0].0, prep[0].2.minutes), (MON.add(8), 45), "the day before");
}

#[test]
fn holidays_and_pause() {
    let mut fx = Fx::new("holidays");
    let w = MON.add(14);
    fx.courses.retain(|c| c.start.date < w || c.start.date > w.add(13));
    fx.settings.periods = vec![
        Period { name: "Autumn 1".into(), start: w, end: w.add(6), rule: PeriodRule::Free },
        Period { name: "Autumn 2".into(), start: w.add(7), end: w.add(13), rule: PeriodRule::MorningBlock },
    ];
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.sessions.iter().filter(|s| s.date >= w && s.date <= w.add(6)).all(|s| s.parts.is_empty()));
    let mornings: Vec<_> = p.sessions.iter().filter(|s| s.date >= w.add(7) && s.date <= w.add(11)).collect();
    assert_eq!(mornings.iter().map(|s| s.slot()).collect::<std::collections::BTreeSet<_>>().len(), 5);
    assert!(mornings.iter().all(|s| s.kind == SlotKind::Morning && s.start >= hm("08:30")));
    assert!(mornings.iter().any(|s| s.start == hm("08:30")));

    fx.settings.periods.clear();
    fx.settings.paused_until = Some(MON.add(6));
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.paused);
    assert!(p.sessions.iter().all(|s| s.date > MON.add(6)));

    fx.settings.paused_until = None;
    let p = fx.plan(at(MON.add(75), "08:00"));
    assert!(p.paused && p.sessions.is_empty(), "nothing left in ADE: automatic pause");
}

#[test]
fn work_study_weeks() {
    let mut fx = Fx::new("company");
    let w = MON.add(7);
    fx.courses.retain(|c| c.start.date < w || c.start.date > w.add(13));
    fx.settings.status = Status::Alternance { since: MON, work_start: hm("09:00"), work_end: hm("17:30") };
    let p = fx.plan(at(MON, "06:00"));
    let weekdays: Vec<_> = p.sessions.iter().filter(|s| s.date >= w && s.date <= w.add(11) && s.date.weekday() < 5).collect();
    assert!(weekdays.iter().all(|s| s.kind == SlotKind::Evening), "no morning at the company");
    assert_eq!(weekdays.iter().map(|s| s.slot()).collect::<std::collections::BTreeSet<_>>().len(), 8, "Monday to Thursday, two weeks");
    fx.settings.status = Status::Initial;
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.sessions.iter().any(|s| s.date >= w && s.date <= w.add(4) && s.kind == SlotKind::Morning));
}

#[test]
fn pinned_sessions() {
    let mut fx = Fx::new("pinned");
    fx.pinned.push(Pin { task: "course:NET".into(), date: MON.add(3), start: hm("20:30"), minutes: 60, work: Some(Work::Course), domain: Some("NET".into()) });
    let p = fx.plan(at(MON, "06:00"));
    let s = p.sessions.iter().find(|s| s.date == MON.add(3) && s.kind == SlotKind::Evening).unwrap();
    assert!(s.pinned && s.parts[0].task == "course:NET" && s.reasons.contains(&Reason::Pinned));
    assert_eq!(s.start, hm("20:30"));
    fx.pinned[0].start = hm("21:00");
    let p = fx.plan(at(MON, "06:00"));
    let s = p.sessions.iter().find(|s| s.date == MON.add(3) && s.kind == SlotKind::Evening).unwrap();
    assert_eq!((s.start, s.end), (hm("21:00"), hm("21:45")), "at the time asked for");

    // A pin of a task gone (a course file of the old planner): let go.
    fx.pinned = vec![Pin { task: "study:ALGO/x.md".into(), date: MON.add(3), start: hm("20:30"), minutes: 60, work: None, domain: None }];
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.sessions.iter().all(|s| !s.pinned));
}

#[test]
fn subjects_take_turns() {
    let fx = Fx::new("turns");
    let p = fx.plan(at(MON, "06:00"));
    let order: Vec<&str> = p.sessions.iter().filter_map(|s| s.course()).take(9).collect();
    let repeats = order.windows(2).filter(|w| w[0] == w[1]).count();
    assert_eq!(repeats, 0, "{order:?}");
    assert_eq!(order.iter().collect::<std::collections::BTreeSet<_>>().len(), 3, "every subject gets a turn");
    assert!(p.sessions.iter().filter(|s| s.course().is_some()).all(|s| !s.reasons.is_empty()), "every session says why");
    // Even shares, four weeks ahead, with nothing to tell them apart.
    let m = minutes_before(&p, MON.add(28));
    let (lo, hi) = (m.values().min().unwrap(), m.values().max().unwrap());
    assert!((hi - lo) * 4 <= *hi, "{m:?}");
}

#[test]
fn the_last_days_count_in_the_shares() {
    let mut fx = Fx::new("history");
    let first = |fx: &Fx| fx.plan(at(MON, "06:00")).sessions.iter().find_map(|s| s.course().map(String::from)).unwrap();
    let was = first(&fx);
    // Hours of it last week: another subject goes first.
    fx.done.insert(was.clone(), vec![(MON.add(-2), 180), (MON.add(-1), 90)]);
    assert_ne!(first(&fx), was);
}

#[test]
fn a_tutorial_tomorrow_takes_tonight_even_against_an_exam() {
    let mut fx = Fx::new("forced");
    fx.exam("LOGIC", MON.add(3));
    let td = course(MON.add(1), "13:30", "15:30", CourseKind::Tutorial, "ALGO");
    fx.courses.push(td.clone());
    let p = fx.plan(at(MON, "06:00"));
    assert_eq!(first_date(&p, &format!("prepare:{}", td.uid)), Some(MON), "tonight is the only slot before it");
    assert!(!p.changes.iter().any(|c| matches!(c, Change::AtRisk { task, .. } if task.starts_with("prepare:"))));
}

#[test]
fn a_closed_session_keeps_its_slot() {
    let mut fx = Fx::new("spent");
    let p0 = fx.plan(at(MON, "06:00"));
    let first = p0.sessions.iter().find(|s| s.date == MON && !s.parts.is_empty()).unwrap().clone();
    fx.spent.push(first.id.clone());
    fx.away_today.push(first.parts[0].task.clone());
    let p1 = fx.plan(at(MON, "20:00"));
    assert!(p1.sessions.iter().all(|s| s.id != first.id), "not filled again after its close");
    assert!(p1.sessions.iter().filter(|s| s.date == MON).all(|s| s.parts.iter().all(|x| x.task != first.parts[0].task)), "its task not again today");
}

#[test]
fn a_subject_said_behind_gets_more_time() {
    let mut fx = Fx::new("level");
    let before = minutes_before(&fx.plan(at(MON, "06:00")), MON.add(28));
    fx.domains.iter_mut().find(|d| d.id == "NET").unwrap().level = Level::Behind;
    let p = fx.plan(at(MON, "06:00"));
    let after = minutes_before(&p, MON.add(28));
    assert!(after["NET"] > before["NET"] && after["NET"] > after["ALGO"], "{before:?} → {after:?}");
    assert!(p.sessions.iter().any(|s| s.reasons.contains(&Reason::SaidBehind { domain: "NET".into() })), "and says why");
}

#[test]
fn a_subject_where_tutorials_are_enough_has_no_sessions() {
    let mut fx = Fx::new("td-only");
    fx.domains.iter_mut().find(|d| d.id == "ALGO").unwrap().level = Level::TdOnly;
    let p = fx.plan(at(MON, "06:00"));
    assert!(course_days(&p, "ALGO").is_empty());
    let prep = parts(&p).into_iter().any(|(_, _, x)| x.domain.as_deref() == Some("ALGO") && matches!(x.work, Work::Prepare { .. }));
    assert!(prep, "its tutorials are still prepared");
}

#[test]
fn a_task_goes_before_the_subject_of_its_evening() {
    let mut fx = Fx::new("chore");
    fx.chores.push(Chore { id: "c1".into(), title: "send the form".into(), domain: None, file: None, minutes: 20, due: None, done: false });
    let p = fx.plan(at(MON, "06:00"));
    let d = first_date(&p, "chore:c1").expect("placed");
    assert_eq!(d, MON, "as soon as it can be");
    let evening: Vec<_> = p.sessions.iter().filter(|s| s.date == MON && s.counted && !s.parts.is_empty()).collect();
    assert!(evening.iter().any(|s| s.course().is_some()), "the rest of the evening to a subject");
}

#[test]
fn the_campaign_takes_daytime_before_the_evening() {
    let mut fx = Fx::new("campaign-day");
    fx.campaigns.push(Campaign {
        id: "jobs".into(),
        name: "Work-study".into(),
        start: MON,
        end: MON.add(6),
        school_day_minutes: 30,
        free_day_minutes: 120,
        weekly_target: 8,
        rows: Vec::new(),
        closed: false, dir: None
    });
    let p = fx.plan(at(MON, "06:00"));
    let kind = |day: Date| {
        parts(&p).into_iter().find(|(d, _, x)| *d == day && matches!(x.work, Work::Campaign { .. })).map(|(_, s, _)| s.kind)
    };
    assert_eq!(kind(MON.add(1)), Some(SlotKind::Block), "Tuesday's free afternoon");
    assert_eq!(kind(MON.add(2)), Some(SlotKind::Morning), "Wednesday's morning");
    assert_eq!(kind(MON), Some(SlotKind::Gap), "a gap at school still comes first");
    assert_eq!(kind(MON.add(3)), Some(SlotKind::Gap));
}

#[test]
fn not_tonight_is_for_one_task_and_the_others_stay() {
    let mut fx = Fx::new("one-thing");
    let p0 = fx.plan(at(MON, "06:00"));
    let tonight: Vec<_> = p0.sessions.iter().filter(|s| s.date == MON && s.kind == SlotKind::Evening && !s.parts.is_empty()).collect();
    assert!(tonight.len() >= 2, "an evening of several tasks, one session each");
    assert!(tonight.iter().all(|s| s.parts.len() == 1));
    assert!(tonight.windows(2).all(|w| w[0].end <= w[1].start), "one after the other");
    let skipped = tonight[0].parts[0].task.clone();
    fx.away_today.push(skipped.clone());
    let p1 = fx.plan(at(MON, "20:00"));
    let still: Vec<_> = p1.sessions.iter().filter(|s| s.date == MON && !s.parts.is_empty()).collect();
    assert!(!still.is_empty(), "the rest of the evening stays");
    assert!(still.iter().all(|s| s.parts[0].task != skipped), "and that task waits for another day");
}

#[test]
fn time_found_on_the_spot_is_a_session() {
    let mut fx = Fx::new("extra");
    fx.extra.push(boussole::journee::Extra { date: MON, start: hm("17:00"), minutes: 60, place: Place::Home });
    let p = fx.plan(at(MON, "16:55"));
    let found: Vec<_> = p.sessions.iter().filter(|s| s.date == MON && s.kind == SlotKind::Extra).collect();
    assert!(!found.is_empty() && found[0].start == hm("17:00"), "{found:?}");
    assert!(found.iter().all(|s| s.end <= hm("18:00") && s.counted));
}

#[test]
fn later_until_moves_the_evening_past_it_or_off_tonight() {
    let mut fx = Fx::new("away");
    let now = at(MON, "20:00");
    let before = fx.plan(now);
    let tonight = |p: &Plan| p.sessions.iter().filter(|s| s.date == MON && s.counted && !s.parts.is_empty() && s.start >= hm("18:00")).map(|s| s.start).collect::<Vec<_>>();
    assert!(!tonight(&before).is_empty(), "an evening session at first");

    fx.busy.push(Busy { start: now, end: at(MON, "21:00"), title: String::new() });
    let later = fx.plan(now);
    assert!(tonight(&later).iter().all(|t| *t >= hm("21:00")), "{:?}", tonight(&later));

    fx.busy[0].end = at(MON.add(1), "00:00");
    let off = fx.plan(now);
    assert!(tonight(&off).is_empty(), "nothing tonight: {:?}", tonight(&off));
}
