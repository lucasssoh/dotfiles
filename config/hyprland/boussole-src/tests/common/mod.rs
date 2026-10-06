//! A small course tree, a school week and a builder for the planner's input.

#![allow(dead_code)]

use std::path::{Path, PathBuf};

use boussole::catalogue::{Catalogue, Ignore, Inclusion};
use boussole::model::*;
use boussole::plan::{self, Input, Pin, Plan};
use boussole::time::{Date, Hm, Local};

/// Monday 5 October 2026.
pub const MON: Date = Date(20_731);

pub fn at(date: Date, hm: &str) -> Local {
    Local::new(date, Hm::parse(hm).unwrap())
}

pub fn hm(s: &str) -> Hm {
    Hm::parse(s).unwrap()
}

fn sheet(sections: u32, exercises: u32) -> String {
    let mut s = String::from("# A sheet\n\n| | |\n|---|---|\n\n");
    for n in 1..=sections {
        s += &format!("## {n}. Section {n}\n\ntext\n\n");
    }
    s += &format!("## {}. Exercices\n\n", sections + 1);
    for n in 1..=exercises {
        s += &format!("### Exercice {n} — something\n\n<details>solution</details>\n\n");
    }
    s
}

/// A course tree in a fresh temporary folder.
pub fn tree(name: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("boussole-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let files: Vec<(&str, String)> = vec![
        (
            "ALGO/Ch1/00_Carte_du_cours.md",
            "# Map\n\n```\nCh1/\n├── 10_Bloc/\n│   ├── 11_A.md     intro\n│   └── 12_B.md     ★ the proof to know\n└── 20_Bloc/\n    └── 21_C.md\n```\n".into(),
        ),
        ("ALGO/Ch1/10_Bloc/11_A.md", sheet(4, 3)),
        ("ALGO/Ch1/10_Bloc/12_B.md", sheet(4, 3)),
        ("ALGO/Ch1/20_Bloc/21_C.md", sheet(4, 2)),
        ("ALGO/Ch1/90_Exercices/91_Synthese.md", "# Synth\n\n## Exercice 1 — a\n\n## Exercice 2 — b\n".into()),
        ("ALGO/Ch1/90_Exercices/93_Sujets_type_examen.md", "# Sujets type examen\n\n# Sujet A — x\n\n### Partie 1\n\n# Sujet B — y\n".into()),
        ("ALGO/00_Index.md", "# index".into()),
        ("ALGO/roadmap.md", "# notes for agents".into()),
        ("ALGO/References/book.pdf", "%PDF".into()),
        ("ALGO/.hidden/x.md", "# hidden".into()),
        ("LOGIC/Lambda/00_Carte_du_cours.md", "# Map\n".into()),
        ("LOGIC/Lambda/10_Syntaxe/11_Termes.md", sheet(4, 3)),
        ("LOGIC/Lambda/10_Syntaxe/12_Substitution.md", sheet(4, 3)),
        ("LOGIC/Lambda/90_Exercices/93_Sujet_type_examen.md", "# Sujet type examen — λ (1 h 30)\n\n### Partie 1\n".into()),
        ("NET/cours-intro.pdf", "%PDF".into()),
        ("NET/notes-cm1.md", "# Notes du CM 1\n".into()),
        ("NET/TD/00_Sommaire.md", "# TD\n".into()),
        ("NET/TD/10_Perf/Exo_02_Second.md", "# Exercice 2 — b\n".into()),
        ("NET/TD/10_Perf/Exo_01_First.md", "# Exercice 1 — a\n".into()),
    ];
    for (path, body) in files {
        let p = root.join(path);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, body).unwrap();
    }
    root
}

pub fn write(root: &Path, path: &str, body: &str) {
    let p = root.join(path);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, body).unwrap();
}

pub fn course(date: Date, from: &str, to: &str, kind: CourseKind, domain: &str) -> Course {
    Course {
        uid: format!("{date}-{from}-{domain}"),
        start: at(date, from),
        end: at(date, to),
        kind,
        domain: Some(domain.into()),
        title: format!("{kind:?} {domain}"),
    }
}

/// A school week from `monday`:
///   Mon 08:00-10:00 CM ALGO, 13:30-15:30 TD ALGO
///   Tue 08:00-12:00 CM LOGIC
///   Wed 13:30-17:30 TP NET           (free morning)
///   Thu 08:00-10:00 CM NET, 15:45-17:45 TD LOGIC   (gap 10:00-15:45, minus 12:00-13:30)
///   Fri 08:00-12:00 CM ALGO
pub fn week(monday: Date) -> Vec<Course> {
    use CourseKind::*;
    vec![
        course(monday, "08:00", "10:00", Lecture, "ALGO"),
        course(monday, "13:30", "15:30", Tutorial, "ALGO"),
        course(monday.add(1), "08:00", "12:00", Lecture, "LOGIC"),
        course(monday.add(2), "13:30", "17:30", Lab, "NET"),
        course(monday.add(3), "08:00", "10:00", Lecture, "NET"),
        course(monday.add(3), "15:45", "17:45", Tutorial, "LOGIC"),
        course(monday.add(4), "08:00", "12:00", Lecture, "ALGO"),
    ]
}

pub fn weeks(monday: Date, n: i32) -> Vec<Course> {
    (0..n).flat_map(|w| week(monday.add(7 * w))).collect()
}

pub struct Fx {
    pub root: PathBuf,
    pub settings: Settings,
    pub domains: Vec<Domain>,
    pub catalogue: Catalogue,
    pub progress: Progress,
    pub courses: Vec<Course>,
    pub calendar: bool,
    pub busy: Vec<Busy>,
    pub deadlines: Vec<Deadline>,
    pub projects: Vec<Project>,
    pub campaigns: Vec<Campaign>,
    pub chores: Vec<Chore>,
    pub pinned: Vec<Pin>,
    pub away_today: Vec<String>,
    pub extra: Vec<boussole::journee::Extra>,
    pub learned: [Option<Hm>; 7],
    pub missed_streak: u32,
    pub spent: Vec<String>,
}

impl Fx {
    /// The tree, every structured file planned, ten school weeks.
    pub fn new(name: &str) -> Fx {
        let root = tree(name);
        let catalogue = Catalogue::scan(&root, &Ignore::default());
        let mut progress = Progress::default();
        for i in &catalogue.items {
            use boussole::catalogue::ItemKind::*;
            let plan = !matches!(i.kind, Pdf | Notes);
            progress.files.insert(i.id.clone(), if plan { Inclusion::Planned } else { Inclusion::Ignored });
        }
        let domains = ["ALGO", "LOGIC", "NET"]
            .iter()
            .map(|id| Domain { id: id.to_string(), spaced: true, ..Domain::default() })
            .collect();
        Fx {
            root,
            settings: Settings::default(),
            domains,
            catalogue,
            progress,
            courses: weeks(MON, 10),
            calendar: true,
            busy: Vec::new(),
            deadlines: Vec::new(),
            projects: Vec::new(),
            campaigns: Vec::new(),
            chores: Vec::new(),
            pinned: Vec::new(),
            away_today: Vec::new(),
            extra: Vec::new(),
            learned: [None; 7],
            missed_streak: 0,
            spent: Vec::new(),
        }
    }

    pub fn rescan(&mut self) {
        self.catalogue = Catalogue::scan(&self.root, &Ignore::default());
    }

    pub fn input<'a>(&'a self, now: Local, previous: Option<&'a Plan>) -> Input<'a> {
        Input {
            now,
            settings: &self.settings,
            domains: &self.domains,
            catalogue: &self.catalogue,
            progress: &self.progress,
            courses: &self.courses,
            calendar: self.calendar,
            busy: &self.busy,
            deadlines: &self.deadlines,
            projects: &self.projects,
            campaigns: &self.campaigns,
            chores: &self.chores,
            pinned: &self.pinned,
            away_today: &self.away_today,
            extra: &self.extra,
            learned: self.learned,
            missed_streak: self.missed_streak,
            spent: &self.spent,
            previous,
        }
    }

    pub fn plan(&self, now: Local) -> Plan {
        plan::plan(&self.input(now, None))
    }

    pub fn replan(&self, now: Local, previous: &Plan) -> Plan {
        plan::plan(&self.input(now, Some(previous)))
    }

    pub fn exam(&mut self, domain: &str, date: Date) {
        self.deadlines.push(Deadline {
            id: format!("exam-{domain}"),
            domain: Some(domain.into()),
            kind: DeadlineKind::Exam,
            at: at(date, "08:00"),
            title: format!("Exam {domain}"),
            source: Source::Manual,
            hours: None,
            spent_minutes: 0,
        });
    }

    pub fn id(&self, suffix: &str) -> String {
        self.catalogue.items.iter().find(|i| i.id.ends_with(suffix)).unwrap_or_else(|| panic!("no {suffix}")).id.clone()
    }
}

impl Drop for Fx {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

/// Every part of a plan's counted sessions, with its date.
pub fn parts(p: &Plan) -> Vec<(Date, &boussole::plan::Session, &boussole::plan::Part)> {
    p.sessions.iter().flat_map(|s| s.parts.iter().map(move |part| (s.date, s, part))).collect()
}

pub fn first_date(p: &Plan, task: &str) -> Option<Date> {
    parts(p).into_iter().find(|(_, _, part)| part.task == task).map(|(d, _, _)| d)
}
