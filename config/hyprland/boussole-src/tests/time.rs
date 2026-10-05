use boussole::i18n;
use boussole::model::Lang;
use boussole::time::{Date, Hm, Local, Tz};

#[test]
fn civil_dates() {
    let d = Date::ymd(2026, 10, 5);
    assert_eq!(d.0, 20_731);
    assert_eq!(d.parts(), (2026, 10, 5));
    assert_eq!(d.weekday(), 0, "a Monday");
    assert_eq!(Date::ymd(2024, 2, 29).add(1), Date::ymd(2024, 3, 1));
    assert_eq!(Date::ymd(1969, 12, 31).0, -1);
    assert_eq!(d.add(6).monday(), d);
    assert_eq!(d.iso_week(), 41);
    assert_eq!(Date::ymd(2026, 10, 19).iso_week(), 43, "first week of the autumn break");
    assert_eq!(Date::parse("2026-02-30"), None);
    assert_eq!(Date::parse("2026-10-05"), Some(d));
    assert_eq!(d.to_string(), "2026-10-05");
}

#[test]
fn times_of_day() {
    assert_eq!(Hm::parse("20:30"), Some(Hm::new(20, 30)));
    assert_eq!(Hm::parse("14h"), Some(Hm::new(14, 0)));
    assert_eq!(Hm::parse("25:00"), None);
    assert_eq!(Hm::new(20, 31).ceil(5), Hm::new(20, 35));
    assert_eq!(Hm::new(20, 35).ceil(30), Hm::new(21, 0));
    let l = Local::parse("2026-10-05T20:30").unwrap();
    assert_eq!(l.plus(240).to_string(), "2026-10-06T00:30");
    let json = serde_json::to_string(&l).unwrap();
    assert_eq!(json, "\"2026-10-05T20:30\"");
    assert_eq!(serde_json::from_str::<Local>(&json).unwrap(), l);
}

#[test]
fn paris_summer_and_winter_time() {
    let Some(tz) = Tz::named("Europe/Paris") else {
        eprintln!("no tzdata, skipped");
        return;
    };
    let utc = |d: Date, h: i64, m: i64| d.0 as i64 * 86_400 + h * 3600 + m * 60;
    // ADE's 06:00Z on a Friday in October is 08:00 in Paris.
    let oral = tz.to_local(utc(Date::ymd(2026, 10, 9), 6, 0));
    assert_eq!(oral, Local::new(Date::ymd(2026, 10, 9), Hm::new(8, 0)));
    // After the last Sunday of October, 07:15Z is 08:15.
    let winter = tz.to_local(utc(Date::ymd(2026, 11, 6), 9, 15));
    assert_eq!(winter.time, Hm::new(10, 15));
    // The switches: 2026-03-29 01:00Z and 2026-10-25 01:00Z.
    assert_eq!(tz.offset(utc(Date::ymd(2026, 3, 29), 0, 59)), 3600);
    assert_eq!(tz.offset(utc(Date::ymd(2026, 3, 29), 1, 0)), 7200);
    assert_eq!(tz.offset(utc(Date::ymd(2026, 10, 25), 0, 59)), 7200);
    assert_eq!(tz.offset(utc(Date::ymd(2026, 10, 25), 1, 0)), 3600);
    // Far beyond the TZif table, the POSIX rule takes over.
    assert_eq!(tz.offset(utc(Date::ymd(2061, 7, 1), 12, 0)), 7200);
    let l = Local::new(Date::ymd(2026, 12, 18), Hm::new(13, 30));
    assert_eq!(tz.to_local(tz.to_utc(l)), l);
}

#[test]
fn dates_follow_the_language() {
    let d = Date::ymd(2026, 10, 5);
    assert_eq!(i18n::date(d, Lang::En), "Mon Oct 5");
    assert_eq!(i18n::date(d, Lang::Fr), "lun. 5 oct.");
}
