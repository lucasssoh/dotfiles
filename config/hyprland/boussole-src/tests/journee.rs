mod common;

use common::*;

use boussole::journee::{self, Mode, Place, Slot, SlotKind};
use boussole::model::*;
use boussole::time::Date;

fn evening(fx: &Fx, date: Date) -> Slot {
    let day = journee::day(&fx.input(at(MON, "06:00"), None), date);
    day.slots.into_iter().find(|s| s.kind == SlotKind::Evening).expect("an evening")
}

fn slots(fx: &Fx, date: Date) -> Vec<(SlotKind, String, String, bool)> {
    journee::day(&fx.input(at(MON, "06:00"), None), date)
        .slots
        .into_iter()
        .map(|s| (s.kind, s.start.to_string(), s.end.to_string(), s.counted))
        .collect()
}

#[test]
fn a_school_week() {
    let fx = Fx::new("week");
    // Monday: a gap from 10:00 to the gym at noon; back at 15:30 + 45,
    // ready long before 20:30.
    assert_eq!(
        slots(&fx, MON),
        [(SlotKind::Gap, "10:00".into(), "12:00".into(), false), (SlotKind::Evening, "20:30".into(), "21:45".into(), true)]
    );
    // Wednesday: first course at 13:30, so leaving at 11:15 (gym at noon):
    // a short block after the morning routine.
    assert_eq!(
        slots(&fx, MON.add(2)),
        [(SlotKind::Morning, "08:30".into(), "09:15".into(), true), (SlotKind::Evening, "20:30".into(), "21:45".into(), true)]
    );
    // Thursday: a gap between 10:00 and 15:45, without the 12:00-13:30 gym.
    assert_eq!(
        slots(&fx, MON.add(3)),
        [
            (SlotKind::Gap, "10:00".into(), "12:00".into(), false),
            (SlotKind::Gap, "13:30".into(), "15:45".into(), false),
            (SlotKind::Evening, "20:30".into(), "21:45".into(), true),
        ]
    );
    // Friday evening is free; Saturday only offers; Sunday has two counted blocks.
    assert!(slots(&fx, MON.add(4)).is_empty());
    assert_eq!(
        slots(&fx, MON.add(5)),
        [(SlotKind::Bonus, "10:00".into(), "11:30".into(), false), (SlotKind::Bonus, "15:00".into(), "16:30".into(), false)]
    );
    assert_eq!(
        slots(&fx, MON.add(6)),
        [(SlotKind::Block, "10:00".into(), "11:30".into(), true), (SlotKind::Block, "15:00".into(), "16:30".into(), true)]
    );
}

#[test]
fn a_late_day_shortens_the_session_never_past_the_latest_end() {
    let mut fx = Fx::new("late");
    // Courses until 19:30: home 20:15, shower and dinner, 21:25 at best.
    fx.courses.push(course(MON, "17:30", "19:30", CourseKind::Lab, "NET"));
    let e = evening(&fx, MON);
    assert_eq!((e.start, e.end, e.shortened), (hm("21:25"), hm("22:15"), true));
    // Until 21:00: nothing worth a session is left.
    fx.courses.push(course(MON.add(1), "19:00", "21:00", CourseKind::Lab, "NET"));
    assert!(slots(&fx, MON.add(1)).iter().all(|s| s.0 != SlotKind::Evening));
}

#[test]
fn the_learnt_start_and_personal_events() {
    let mut fx = Fx::new("learnt");
    fx.learned[0] = Some(hm("21:00"));
    let e = evening(&fx, MON);
    assert_eq!((e.start, e.end), (hm("21:00"), hm("22:15")), "75 minutes would end at 22:15");
    // Something in the khal calendar at 21:15 cuts the session short.
    fx.learned[0] = None;
    fx.busy.push(Busy { start: at(MON, "21:15"), end: at(MON, "22:00"), title: "call".into() });
    let e = evening(&fx, MON);
    assert_eq!((e.start, e.end, e.shortened), (hm("20:30"), hm("21:15"), true));
    // A Sunday block slides past an event, inside 10:00-19:00.
    fx.busy.push(Busy { start: at(MON.add(6), "09:30"), end: at(MON.add(6), "11:00"), title: "brunch".into() });
    let sun = slots(&fx, MON.add(6));
    assert_eq!((sun[0].1.as_str(), sun[0].2.as_str()), ("11:00", "12:30"));
    assert_eq!((sun[1].1.as_str(), sun[1].2.as_str()), ("15:00", "16:30"));
}

#[test]
fn friday_offers_a_short_evening_near_an_exam() {
    let mut fx = Fx::new("friday");
    fx.exam("ALGO", MON.add(14));
    let fri = slots(&fx, MON.add(4));
    assert_eq!(fri, [(SlotKind::Short, "20:30".into(), "21:10".into(), false)]);
    let far = slots(&fx, MON.add(4).add(-21));
    assert!(far.is_empty());
}

#[test]
fn later_is_always_a_precise_time() {
    let fx = Fx::new("later");
    let e = evening(&fx, MON);
    let opts = journee::later_options(&e, hm("20:35"), 75, 20);
    let shown: Vec<(String, String)> = opts.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect();
    assert_eq!(shown, [("21:00".into(), "22:15".into()), ("21:30".into(), "22:15".into())]);
    assert!(journee::later_options(&e, hm("21:50"), 75, 20).is_empty(), "too late: the session counts as missed");
}

#[test]
fn the_start_is_learnt_from_the_journal() {
    let starts = [
        (MON.add(-28), hm("20:30")),
        (MON.add(-21), hm("21:10")),
        (MON.add(-14), hm("21:00")),
        (MON.add(-7), hm("20:50")),
        (MON.add(-6), hm("19:00")),
    ];
    // The last four Mondays: 20:30, 21:10, 21:00, 20:50 → median 20:55.
    assert_eq!(journee::learn_start(&starts, 0), Some(hm("20:55")));
    assert_eq!(journee::learn_start(&starts, 1), Some(hm("19:00")));
    assert_eq!(journee::learn_start(&starts, 2), None);
}

#[test]
fn periods_pause_and_work_study() {
    let mut fx = Fx::new("periods");
    let w1 = MON.add(14);
    fx.settings.periods = vec![
        Period { name: "Autumn 1".into(), start: w1, end: w1.add(6), rule: PeriodRule::Free },
        Period { name: "Autumn 2".into(), start: w1.add(7), end: w1.add(13), rule: PeriodRule::MorningBlock },
    ];
    fx.courses.retain(|c| c.start.date < w1 || c.start.date > w1.add(13));
    fx.campaigns.push(Campaign {
        id: "jobs".into(),
        name: "Work-study".into(),
        start: MON,
        end: w1.add(13),
        school_day_minutes: 30,
        free_day_minutes: 120,
        weekly_target: 8,
        rows: Vec::new(),
        closed: false,
    });
    // Week 1: no study, a two-hour morning for applications.
    assert_eq!(slots(&fx, w1), [(SlotKind::Campaign, "08:30".into(), "10:30".into(), true)]);
    assert!(slots(&fx, w1.add(6)).is_empty(), "the break's Sunday too");
    // Week 2: a study block each morning, then 30 minutes of applications.
    assert_eq!(
        slots(&fx, w1.add(9)),
        [(SlotKind::Morning, "08:30".into(), "10:00".into(), true), (SlotKind::Campaign, "10:00".into(), "10:30".into(), true)]
    );
    assert_eq!(slots(&fx, w1.add(13)).len(), 2, "Sunday keeps its blocks");

    // A study week: a weekday gets Sunday's two blocks and its evening.
    fx.settings.periods[0].rule = PeriodRule::Study;
    fx.campaigns.clear();
    let day = slots(&fx, w1.add(1));
    let blocks = day.iter().filter(|s| s.0 == SlotKind::Block).count();
    assert_eq!(blocks, 2, "{day:?}");
    assert!(day.iter().any(|s| s.0 == SlotKind::Evening), "{day:?}");
    fx.settings.periods[0].rule = PeriodRule::Free;

    // Manual pause.
    fx.settings.paused_until = Some(MON.add(1));
    assert_eq!(journee::day(&fx.input(at(MON, "06:00"), None), MON).mode, Mode::Paused);
    assert_ne!(journee::day(&fx.input(at(MON, "06:00"), None), MON.add(2)).mode, Mode::Paused);
    fx.settings.paused_until = None;

    // A week without courses: at home in full-time studies, at the company in work-study.
    fx.settings.periods.clear();
    let empty = MON.add(42);
    fx.courses.retain(|c| c.start.date < empty || c.start.date > empty.add(6));
    let d = journee::day(&fx.input(at(MON, "06:00"), None), empty.add(1));
    assert_eq!(d.mode, Mode::Home);
    assert_eq!(d.slots.iter().map(|s| s.kind).collect::<Vec<_>>(), [SlotKind::Morning, SlotKind::Evening]);
    fx.settings.status = Status::Alternance { since: MON, work_start: hm("09:00"), work_end: hm("18:30") };
    let d = journee::day(&fx.input(at(MON, "06:00"), None), empty.add(1));
    assert_eq!(d.mode, Mode::Company);
    let s: Vec<_> = d.slots.iter().map(|s| (s.kind, s.start.to_string(), s.place)).collect();
    // Home at 19:15, shower, dinner: 20:30 still holds.
    assert_eq!(s, [(SlotKind::Evening, "20:30".into(), Place::Home)]);
}

#[test]
fn no_courses_left_means_a_pause() {
    let mut fx = Fx::new("autopause");
    let after = MON.add(70);
    let input = fx.input(at(after, "08:00"), None);
    assert!(journee::paused(&input, after), "ADE has nothing ahead: the semester is over");
    // Courses of the next semester appear: back to work.
    fx.courses.push(course(after.add(30), "08:00", "10:00", CourseKind::Lecture, "ALGO"));
    assert!(!journee::paused(&fx.input(at(after, "08:00"), None), after));
    // Without a calendar set up, nothing pauses on its own.
    fx.courses.clear();
    fx.calendar = false;
    assert!(!journee::paused(&fx.input(at(after, "08:00"), None), after));
}

#[test]
fn a_free_afternoon_is_a_real_block() {
    let mut fx = Fx::new("half-day");
    // Tuesday: courses 08:00-12:00, back at 12:45, gym until 13:30: a block
    // half an hour later, besides the evening.
    assert_eq!(
        slots(&fx, MON.add(1)),
        [(SlotKind::Block, "14:00".into(), "15:30".into(), true), (SlotKind::Evening, "20:30".into(), "21:45".into(), true)]
    );
    // Monday ends at 15:30: an afternoon at school, nothing more than the evening.
    assert!(slots(&fx, MON).iter().all(|s| s.0 != SlotKind::Block));
    fx.settings.rhythm.half_day_minutes = 0;
    assert!(slots(&fx, MON.add(1)).iter().all(|s| s.0 != SlotKind::Block), "0 turns it off");
}
