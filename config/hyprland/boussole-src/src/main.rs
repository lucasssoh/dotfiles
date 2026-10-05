//! `boussole`: the service (`boussole daemon`), its command line, and
//! `preview`, which plans from a course folder and an iCal file without
//! touching anything.

use std::collections::BTreeMap;
use std::path::PathBuf;

use boussole::store::Paths;
use boussole::{ade, cli, daemon};
use boussole::catalogue::{Catalogue, Ignore, Inclusion, ItemKind};
use boussole::i18n;
use boussole::model::{Domain, Lang, Progress, Settings};
use boussole::plan::{self, Input};
use boussole::time::{Local, Tz};

const USAGE: &str = "usage: boussole preview --courses DIR [--ics FILE] [--groups TD=1,TP=1,GROUPE=B]
                        [--now YYYY-MM-DDTHH:MM] [--days N] [--lang en|fr] [--why]";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let paths = Paths::from_env();
    let result = match args.first().map(String::as_str) {
        Some("--version" | "-V") => Ok(format!("boussole {}", env!("CARGO_PKG_VERSION"))),
        Some("preview") => preview(&args[1..]).map(|_| String::new()),
        Some("daemon") => daemon::run(paths).map(|_| String::new()).map_err(|e| e.to_string()),
        Some("gate") => {
            let rest: Vec<String> = args[1..].iter().skip_while(|a| *a == "--").cloned().collect();
            Err(cli::gate(&paths, &rest).to_string())
        }
        _ => cli::main(&paths, &args),
    };
    match result {
        Ok(text) if text.is_empty() => {}
        Ok(text) => println!("{text}"),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1);
        }
    }
}

fn preview(args: &[String]) -> Result<(), String> {
    let mut opts: BTreeMap<&str, String> = BTreeMap::new();
    let mut i = 0;
    while i < args.len() {
        let key = args[i].trim_start_matches("--");
        if key == "why" {
            opts.insert("why", String::new());
            i += 1;
            continue;
        }
        let value = args.get(i + 1).ok_or(format!("--{key} needs a value\n{USAGE}"))?;
        opts.insert(
            match key {
                "courses" => "courses",
                "ics" => "ics",
                "groups" => "groups",
                "now" => "now",
                "days" => "days",
                "lang" => "lang",
                _ => return Err(format!("unknown option --{key}\n{USAGE}")),
            },
            value.clone(),
        );
        i += 2;
    }
    let tz = Tz::local();
    let now = match opts.get("now") {
        Some(n) => Local::parse(n).ok_or("--now: YYYY-MM-DDTHH:MM")?,
        None => {
            let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
            tz.to_local(secs as i64)
        }
    };
    let lang = if opts.get("lang").map(String::as_str) == Some("fr") { Lang::Fr } else { Lang::En };
    let days: i32 = opts.get("days").and_then(|d| d.parse().ok()).unwrap_or(7);

    let root = PathBuf::from(opts.get("courses").ok_or(USAGE)?);
    let catalogue = Catalogue::scan(&root, &Ignore::default());
    let ids = catalogue.domains();

    let mut events = Vec::new();
    if let Some(path) = opts.get("ics") {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
        events = ade::parse(&text, &tz)?;
    }
    // Calendar names suggested from the feed, as the first run would.
    let mut domains: Vec<Domain> = ids
        .iter()
        .map(|id| Domain { id: id.to_string(), spaced: true, ..Domain::default() })
        .collect();
    for e in &events {
        let name = ade::read_title(&e.summary).name;
        if let Some(id) = ade::suggest_domain(&name, &ids) {
            let d = domains.iter_mut().find(|d| d.id == id).unwrap();
            if !d.calendar_names.contains(&name) {
                d.calendar_names.push(name);
            }
        }
    }
    let mut selection = ade::Selection::new();
    for pair in opts.get("groups").map(String::as_str).unwrap_or("").split(',').filter(|p| !p.is_empty()) {
        let (fam, val) = pair.split_once('=').ok_or("--groups: FAMILY=VALUE,…")?;
        selection.entry(fam.to_uppercase()).or_insert_with(Vec::new).push(val.to_string());
    }
    let (courses, deadlines) = ade::timetable(&events, &selection, &domains, &tz);

    // Structured material planned, the rest left to decide.
    let mut progress = Progress::default();
    for item in &catalogue.items {
        if !matches!(item.kind, ItemKind::Pdf | ItemKind::Notes) {
            progress.files.insert(item.id.clone(), Inclusion::Planned);
        }
    }
    let settings = Settings { lang, ..Settings::default() };
    let input = Input {
        now,
        settings: &settings,
        domains: &domains,
        catalogue: &catalogue,
        progress: &progress,
        courses: &courses,
        calendar: !events.is_empty(),
        busy: &[],
        deadlines: &deadlines,
        projects: &[],
        campaigns: &[],
        chores: &[],
        pinned: &[],
        learned: [None; 7],
        missed_streak: 0,
        spent: &[],
        previous: None,
    };
    let p = plan::plan(&input);

    println!("{} files, {} domains, {} courses, {} exams", catalogue.items.len(), domains.len(), courses.len(), deadlines.len());
    for d in &domains {
        println!("  {:8} ← {}", d.id, d.calendar_names.join(" | "));
    }
    for dl in &deadlines {
        println!("  exam: {} · {}", i18n::local(dl.at, lang), dl.title);
    }
    if p.paused {
        println!("paused");
    }
    let end = now.date.add(days);
    for day in (0..days).map(|i| now.date.add(i)) {
        let mut lines = Vec::new();
        for c in courses.iter().filter(|c| c.start.date == day) {
            lines.push((c.start.time, format!("{}–{}  {}", c.start.time, c.end.time, c.title)));
        }
        for s in p.sessions.iter().chain(&p.offers).filter(|s| s.date == day && s.date < end) {
            let tag = if s.counted { "●" } else { "○" };
            let parts: Vec<String> = s
                .parts
                .iter()
                .map(|p| format!("{}{} ({}′)", p.domain.as_deref().map(|d| format!("{d} ")).unwrap_or_default(), i18n::work(&p.work, lang), p.minutes))
                .collect();
            let what = if parts.is_empty() { "—".to_string() } else { parts.join(" + ") };
            let mut line = format!("{}–{} {tag} {:?}  {what}", s.start, s.end, s.kind);
            if opts.contains_key("why") {
                for r in &s.reasons {
                    line.push_str(&format!("\n                  · {}", i18n::reason(r, lang)));
                }
            }
            lines.push((s.start, line));
        }
        lines.sort_by_key(|l| l.0);
        println!("\n{}", i18n::date(day, lang));
        for (_, l) in lines {
            println!("  {l}");
        }
    }
    if !p.margins.is_empty() {
        println!();
        for m in &p.margins {
            println!("margin before {} ({}): {}", m.title, i18n::date(m.date, lang), m.sessions);
        }
    }
    for c in &p.changes {
        println!("{}", i18n::change(c, lang));
    }
    Ok(())
}
