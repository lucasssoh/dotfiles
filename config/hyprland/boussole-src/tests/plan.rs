mod common;

use common::*;

use boussole::catalogue::Inclusion;
use boussole::journee::{Place, SlotKind};
use boussole::model::*;
use boussole::plan::{Change, Pin, Plan, Reason, Work};
use boussole::time::Date;

fn study_parts(p: &Plan, domain: &str) -> Vec<Date> {
    parts(p)
        .into_iter()
        .filter(|(_, _, part)| part.domain.as_deref() == Some(domain) && matches!(part.work, Work::Study { .. } | Work::Read { .. }))
        .map(|(d, _, _)| d)
        .collect()
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
    assert_eq!(sundays.len(), 2);
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
    for task in &monday {
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
fn doing_more_brings_the_plan_forward() {
    let mut fx = Fx::new("ahead");
    let p0 = fx.plan(at(MON, "06:00"));
    let first = p0.sessions.iter().find(|s| s.parts.iter().any(|p| p.task.starts_with("study:"))).unwrap();
    let study = first.parts.iter().find(|p| p.task.starts_with("study:")).unwrap();
    let id = study.task.trim_start_matches("study:").to_string();
    // Done on Monday, with the next sheet of the same domain as a bonus.
    let next = fx.catalogue.ordered(&fx.domains.iter().find(|d| Some(&d.id) == study.domain.as_ref()).unwrap().clone());
    let after: Vec<String> = next.iter().skip_while(|i| i.id != id).skip(1).take(1).map(|i| i.id.clone()).collect();
    for i in std::iter::once(&id).chain(&after) {
        fx.progress.items.insert(i.clone(), ItemProgress { studied_on: Some(MON), last_on: Some(MON), ..Default::default() });
    }
    let p1 = fx.replan(at(MON.add(1), "06:00"), &p0);
    assert!(first_date(&p1, &format!("study:{id}")).is_none());
    let forward = p1.changes.iter().filter(|c| matches!(c, Change::Moved { from, to, .. } if to < from)).count();
    assert!(forward > 0, "nothing came forward: {:?}", p1.changes);
}

#[test]
fn spaced_reviews_and_redos() {
    let mut fx = Fx::new("reviews");
    let a = fx.id("11_A.md");
    let b = fx.id("12_B.md");
    let c = fx.id("21_C.md");
    let t = fx.id("11_Termes.md");
    fx.progress.items.insert(a.clone(), ItemProgress { studied_on: Some(MON.add(-2)), last_on: Some(MON.add(-2)), assessment: Some(Assessment::Understood), ..Default::default() });
    fx.progress.items.insert(b.clone(), ItemProgress { studied_on: Some(MON.add(-1)), last_on: Some(MON.add(-1)), assessment: Some(Assessment::Review), ..Default::default() });
    fx.progress.items.insert(c.clone(), ItemProgress { studied_on: Some(MON.add(-10)), last_on: Some(MON.add(-3)), reviews_done: vec![MON.add(-3)], ..Default::default() });
    let mut ex = std::collections::BTreeMap::new();
    ex.insert(1, Exercise::Solo);
    ex.insert(2, Exercise::Failed);
    ex.insert(3, Exercise::WithSolution);
    fx.progress.items.insert(
        t.clone(),
        ItemProgress { read_upto: 4, exercises: ex, studied_on: Some(MON), last_on: Some(MON), assessment: Some(Assessment::Blocked), question_open: true, ..Default::default() },
    );
    let p = fx.plan(at(MON, "06:00"));
    let d = |task: String| first_date(&p, &task).unwrap_or_else(|| panic!("{task} not planned"));
    assert!(d(format!("review1:{a}")) >= MON.add(5), "J+7");
    assert!(d(format!("review1:{b}")) >= MON.add(2), "J+3 when to review");
    assert!(d(format!("review1:{b}")) < MON.add(6));
    assert!(d(format!("review2:{c}")) >= MON.add(11), "J+21");
    assert!(d(format!("redo:{t}")) >= MON.add(3), "redo at J+3");
    let redo = parts(&p).into_iter().find(|(_, _, x)| x.task == format!("redo:{t}")).unwrap().2.work.clone();
    assert_eq!(redo, Work::Redo { item: t.clone(), exercises: vec![2, 3] }, "with the solution is not acquired on Podium");
    assert!(first_date(&p, &format!("ask:{t}")).is_some(), "blocked becomes a question");

    fx.settings.objective = Objective::Pass;
    let p = fx.plan(at(MON, "06:00"));
    let redo = parts(&p).into_iter().find(|(_, _, x)| x.task == format!("redo:{t}")).unwrap().2.work.clone();
    assert_eq!(redo, Work::Redo { item: t, exercises: vec![2] });
}

#[test]
fn a_sheet_started_comes_first_where_it_stopped() {
    let mut fx = Fx::new("started");
    let b = fx.id("12_B.md");
    let mut ex = std::collections::BTreeMap::new();
    ex.insert(1, Exercise::Solo);
    fx.progress.items.insert(b.clone(), ItemProgress { read_upto: 2, exercises: ex, last_on: Some(MON.add(-1)), ..Default::default() });
    let p = fx.plan(at(MON, "06:00"));
    let s = p.sessions.iter().find(|s| s.parts.iter().any(|x| x.task == format!("study:{b}"))).unwrap();
    assert_eq!(s.date, MON, "head of the line");
    let w = &s.parts.iter().find(|x| x.task == format!("study:{b}")).unwrap().work;
    assert!(matches!(w, Work::Study { sections: Some((3, 4)), exercises: Some((2, _)), .. }), "{w:?}");
    assert!(s.reasons.contains(&Reason::Continues));
    assert!(s.reasons.iter().any(|r| matches!(r, Reason::Starred { note: Some(n) } if n == "the proof to know")));
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
    assert!(study_parts(&p, "ALGO").iter().all(|d| *d > MON.add(7)), "sheets slide, the project does not");
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
fn a_test_is_prepared_three_days_ahead() {
    let mut fx = Fx::new("cc");
    fx.deadlines.push(Deadline {
        id: "cc-logic".into(),
        domain: Some("LOGIC".into()),
        kind: DeadlineKind::Cc,
        at: at(MON.add(10), "14:00"),
        title: "CC LOGIC".into(),
        source: Source::Manual,
        hours: None,
        spent_minutes: 0,
    });
    let p = fx.plan(at(MON, "06:00"));
    let logic = study_parts(&p, "LOGIC");
    assert!(!logic.is_empty());
    assert!(logic.iter().all(|d| *d <= MON.add(7)), "{logic:?}");
    let m = p.margins.iter().find(|m| m.deadline == "cc-logic").unwrap();
    assert!(m.sessions >= 0);
}

#[test]
fn exam_subjects_in_their_window_and_margin_kept() {
    let mut fx = Fx::new("exam");
    let exam = MON.add(35);
    fx.exam("ALGO", exam);
    let p = fx.plan(at(MON, "06:00"));
    let subjects: Vec<_> = parts(&p).into_iter().filter(|(_, _, x)| matches!(x.work, Work::ExamSubject { .. })).collect();
    assert_eq!(subjects.len(), 2, "two subjects in the ALGO file");
    for (d, s, x) in &subjects {
        assert!(*d >= MON.add(7) && *d < exam, "Podium: from four weeks before");
        assert!(x.timed && s.place == Place::Home && s.kind == SlotKind::Block);
    }
    let m = p.margins.iter().find(|m| m.domain.as_deref() == Some("ALGO")).unwrap();
    assert!(m.sessions >= 2, "Podium keeps two sessions: {}", m.sessions);
    let why = p.sessions.iter().flat_map(|s| &s.reasons).find_map(|r| match r {
        Reason::Deadline { title, margin, .. } if title == "Exam ALGO" => Some(*margin),
        _ => None,
    });
    assert_eq!(why, Some(Some(m.sessions)));

    // Too close for all the work: the margin goes negative instead of hiding it.
    fx.deadlines.clear();
    fx.exam("ALGO", MON.add(2));
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.margins[0].sessions < 0);
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
        assert!(g.parts.iter().all(|x| !x.timed));
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
    for m in missed.iter().filter(|m| !m.task.starts_with("prepare:")) {
        assert!(first_date(&p1, &m.task).is_some(), "{} lost", m.task);
        assert!(p1.changes.iter().any(|c| matches!(c, Change::Moved { task, .. } if *task == m.task)), "{} silent", m.task);
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
fn new_files_wait_to_be_confirmed() {
    let mut fx = Fx::new("newfiles");
    write(&fx.root, "ALGO/Ch1/20_Bloc/22_D.md", "# D\n\n## 1. Formal\n\n## 2. Exercices\n\n### Exercice 1\n");
    fx.rescan();
    let key = "study:ALGO/Ch1/20_Bloc/22_D.md".to_string();
    let p = fx.plan(at(MON, "06:00"));
    assert!(first_date(&p, &key).is_none(), "not before the user says so");
    fx.progress.files.insert("ALGO/Ch1/20_Bloc/22_D.md".into(), Inclusion::Planned);
    let p = fx.plan(at(MON, "06:00"));
    assert!(first_date(&p, &key).is_some());
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
    });
    let p = fx.plan(at(MON, "06:00"));
    for day in (0..12).map(|i| MON.add(i)).filter(|d| d.weekday() < 5) {
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
    assert_eq!(mornings.len(), 5);
    assert!(mornings.iter().all(|s| s.kind == SlotKind::Morning && s.start == hm("08:30")));

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
    assert_eq!(weekdays.len(), 8, "Monday to Thursday, two weeks");
    fx.settings.status = Status::Initial;
    let p = fx.plan(at(MON, "06:00"));
    assert!(p.sessions.iter().any(|s| s.date >= w && s.date <= w.add(4) && s.kind == SlotKind::Morning));
}

#[test]
fn pinned_sessions_and_a_restart() {
    let mut fx = Fx::new("pinned");
    let c = fx.id("21_C.md");
    fx.pinned.push(Pin { task: format!("study:{c}"), date: MON.add(3), start: hm("20:30"), minutes: 60, work: None, domain: None });
    let p = fx.plan(at(MON, "06:00"));
    let s = p.sessions.iter().find(|s| s.date == MON.add(3) && s.kind == SlotKind::Evening).unwrap();
    assert!(s.pinned && s.parts[0].task == format!("study:{c}") && s.reasons.contains(&Reason::Pinned));
    assert_eq!(s.start, hm("20:30"));
    fx.pinned[0].start = hm("21:00");
    let p = fx.plan(at(MON, "06:00"));
    let s = p.sessions.iter().find(|s| s.date == MON.add(3) && s.kind == SlotKind::Evening).unwrap();
    assert_eq!((s.start, s.end), (hm("21:00"), hm("21:45")), "at the time asked for");
    assert_eq!(parts(&p).iter().filter(|(_, _, x)| x.task == format!("study:{c}")).count(), 1);

    fx.missed_streak = 2;
    let p = fx.plan(at(MON, "06:00"));
    let first = &p.sessions[0];
    assert_eq!(first.end.0 - first.start.0, 10);
    assert!(matches!(first.parts[0].work, Work::Recall { .. }));
    assert!(first.reasons.contains(&Reason::Restart { missed: 2 }));
}

#[test]
fn domains_take_turns() {
    let fx = Fx::new("turns");
    let p = fx.plan(at(MON, "06:00"));
    // The domain of each new item, in the order they start (the end of a
    // sheet begun the day before keeps its place and is not a turn).
    let mut seen = std::collections::BTreeSet::new();
    let starts: Vec<String> = parts(&p)
        .into_iter()
        .filter(|(_, _, x)| x.task.starts_with("study:") || x.task.starts_with("read:"))
        .filter(|(_, _, x)| seen.insert(x.task.clone()))
        .filter_map(|(_, _, x)| x.domain.clone())
        .take(8)
        .collect();
    let repeats = starts.windows(2).filter(|w| w[0] == w[1]).count();
    assert!(repeats <= 1, "{starts:?}");
    assert_eq!(starts.iter().collect::<std::collections::BTreeSet<_>>().len(), 3, "every domain gets a turn");
    assert!(p.sessions.iter().all(|s| s.parts.is_empty() || !s.reasons.is_empty()), "every session says why");
}

#[test]
fn a_slower_domain_gets_longer_estimates() {
    let mut fx = Fx::new("pace");
    let a = fx.id("11_A.md");
    let minutes = |fx: &Fx| -> i32 {
        let p = fx.plan(at(MON, "06:00"));
        parts(&p).into_iter().filter(|(_, _, x)| x.task == format!("study:{a}")).map(|(_, _, x)| x.minutes).sum()
    };
    let normal = minutes(&fx);
    fx.settings.pace.domain_factor.insert("ALGO".into(), 1.5);
    assert!(minutes(&fx) > normal);
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
    // The timed subject has no Sunday before Thursday: said, not hidden.
    assert!(p.changes.iter().any(|c| matches!(c, Change::AtRisk { task, .. } if task.starts_with("exam:LOGIC"))));
}

#[test]
fn a_closed_session_keeps_its_slot() {
    let mut fx = Fx::new("spent");
    let p0 = fx.plan(at(MON, "06:00"));
    let first = p0.sessions.iter().find(|s| s.date == MON).unwrap().id.clone();
    fx.spent.push(first.clone());
    let p1 = fx.plan(at(MON, "21:00"));
    assert!(p1.sessions.iter().all(|s| s.id != first), "not filled again after its close");
}
