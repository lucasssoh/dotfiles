//! `boussole <command>`: a client of the service's socket. Everything the
//! drawer will do can be done from here, so nothing needs an agent or a
//! hand-edited JSON file.

use std::io::{self, BufRead, BufReader, IsTerminal, Write};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::Duration;

use serde_json::{json, Value};

use crate::store::Paths;

pub const HELP: &str = "\
boussole                       what comes next
boussole today | week [DAYS]   the plan, with courses (● counted, ○ optional)
boussole start|skip|done [ID]  the next session, or the one given
boussole later [ID] HH:MM      later today, at a precise time
boussole add LINE…             quick add, shown before it is kept (-y keeps it)
    examen L&MC 18/12 · cc OC 12/11 14h · rendu ARGOS 12/11 30h
    indispo sam 14h-18h · tâche relire TD3 A&C 45m · candidature Entreprise F · libre 1h
boussole add --fuzzel          the same in a fuzzel line (Super+Shift+D)
boussole move ID DATE HH:MM    shows what it changes, then asks (-y keeps it)
boussole pin ID | unpin TASK   keep a session where it is
boussole undo | history        the last changes
boussole files [plan|ignore ID…|plan-all]   files waiting for a decision
boussole deadlines | deadline rm ID
boussole project add NAME DUE [SUBJECT] STEP=HOURS… | project list | project rm ID
boussole project step ID STEP done
boussole campaign add NAME FROM TO [PER-WEEK] | campaign list
boussole campaign status NAME COMPANY to-send|sent|follow-up|interview|refused|offer [DATE [HH:MM]]
boussole campaign close NAME
boussole courses DIR           the course folder (read only)
boussole calendar URL          the timetable's iCal link
boussole calendar groups [FAMILY=VALUE,…]   groups found in it, ticked with []
boussole subject list | subject set ID NAME|NAME… | subject spaced ID on|off | subject archive ID
boussole rhythm | rhythm KEY VALUE        evening_target 21:00, evening_minutes 90…
boussole period list | period add NAME FROM TO normal|free|morning-block|bonus-only|pause | period rm NAME
boussole objective pass|ranked|podium · lang en|fr · gate on|off
boussole pause [UNTIL] | resume
boussole refresh               download the timetable and rescan now
boussole gate -- COMMAND…      ask before a game starts during a session
boussole daemon                the service (boussole.service)";

fn connect(paths: &Paths) -> io::Result<UnixStream> {
    let s = UnixStream::connect(paths.socket())?;
    s.set_read_timeout(Some(Duration::from_secs(15)))?;
    Ok(s)
}

/// Sends one command, returns its reply.
pub fn request(paths: &Paths, cmd: Value) -> Result<Value, String> {
    let mut s = connect(paths).map_err(|_| "the service is not running (systemctl --user start boussole)".to_string())?;
    let mut line = cmd.to_string();
    line.push('\n');
    s.write_all(line.as_bytes()).map_err(|e| e.to_string())?;
    let name = cmd["cmd"].as_str().unwrap_or("");
    for l in BufReader::new(s).lines() {
        let l = l.map_err(|e| e.to_string())?;
        let Ok(v) = serde_json::from_str::<Value>(&l) else { continue };
        if v.get("reply").and_then(Value::as_str) == Some(name) {
            return Ok(v);
        }
    }
    Err("no answer".into())
}

fn ok(v: Value) -> Result<String, String> {
    let text = v["text"].as_str().unwrap_or("").to_string();
    if v["ok"].as_bool() == Some(true) {
        Ok(text)
    } else {
        Err(text)
    }
}

fn fr(paths: &Paths) -> bool {
    request(paths, json!({ "cmd": "settings" })).is_ok_and(|v| v["data"]["lang"] == "fr")
}

fn confirm(question: &str) -> bool {
    if !io::stdin().is_terminal() {
        return false;
    }
    print!("{question} [y/N] ");
    let _ = io::stdout().flush();
    let mut a = String::new();
    let _ = io::stdin().read_line(&mut a);
    matches!(a.trim().to_lowercase().as_str(), "y" | "yes" | "o" | "oui")
}

fn fuzzel(prompt: &str, lines: &[&str]) -> Option<String> {
    let mut child = Command::new("fuzzel")
        .args(["--dmenu", "--prompt", prompt])
        .args(if lines.is_empty() { vec!["--lines", "0"] } else { vec![] })
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .ok()?;
    child.stdin.take()?.write_all(lines.join("\n").as_bytes()).ok()?;
    let out = child.wait_with_output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (out.status.success() && !s.is_empty()).then_some(s)
}

fn settings(paths: &Paths) -> Result<Value, String> {
    Ok(request(paths, json!({ "cmd": "settings" }))?["data"].take())
}

fn set(paths: &Paths, patch: Value) -> Result<String, String> {
    ok(request(paths, json!({ "cmd": "set", "patch": patch }))?)
}

/// Runs a command line; Ok(text to print) or Err(message).
pub fn main(paths: &Paths, args: &[String]) -> Result<String, String> {
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let yes = a.contains(&"-y");
    let a: Vec<&str> = a.into_iter().filter(|x| *x != "-y").collect();
    let req = |cmd: Value| request(paths, cmd).and_then(ok);
    let sess = |i: usize| a.get(i).map(|s| json!(s)).unwrap_or(Value::Null);
    match a.as_slice() {
        [] | ["status"] => req(json!({ "cmd": "status" })),
        ["help" | "--help" | "-h"] => Ok(HELP.into()),
        ["today"] => req(json!({ "cmd": "plan", "days": 1 })),
        ["week"] => req(json!({ "cmd": "plan", "days": 7 })),
        ["week", n] => req(json!({ "cmd": "plan", "days": n.parse::<i64>().map_err(|_| "DAYS")? })),
        ["start" | "skip" | "done", ..] => req(json!({ "cmd": a[0], "session": sess(1) })),
        ["later", at] => req(json!({ "cmd": "later", "at": at })),
        ["later", id, at] => req(json!({ "cmd": "later", "session": id, "at": at })),
        ["add", "--fuzzel"] => add_fuzzel(paths),
        ["add", rest @ ..] if !rest.is_empty() => {
            let line = rest.join(" ");
            let seen = request(paths, json!({ "cmd": "add", "line": line }))?;
            let text = ok(seen.clone())?;
            // "libre" is an answer: nothing to keep.
            if seen["data"]["understood"] != true {
                return Ok(text);
            }
            if yes || confirm(&format!("{text}\n→")) {
                req(json!({ "cmd": "add", "line": line, "apply": true }))
            } else {
                Ok(text)
            }
        }
        ["move", id, date, at] => {
            let cmd = json!({ "cmd": "move", "session": id, "date": date, "at": at });
            let effect = req(cmd.clone())?;
            if yes || confirm(&format!("{effect}\n→")) {
                let mut c = cmd;
                c["apply"] = json!(true);
                req(c)
            } else {
                Ok(effect)
            }
        }
        ["pin", id] => req(json!({ "cmd": "pin", "session": id, "apply": true })),
        ["unpin", task] => req(json!({ "cmd": "unpin", "task": task })),
        ["undo"] => req(json!({ "cmd": "undo" })),
        ["history"] => req(json!({ "cmd": "history" })),
        ["files"] => req(json!({ "cmd": "files" })),
        ["files", "plan-all"] => {
            let v = request(paths, json!({ "cmd": "files" }))?;
            req(json!({ "cmd": "files", "items": v["data"], "inclusion": "planned" }))
        }
        ["files", how @ ("plan" | "ignore"), ids @ ..] if !ids.is_empty() => {
            let inclusion = if *how == "plan" { "planned" } else { "ignored" };
            req(json!({ "cmd": "files", "items": ids, "inclusion": inclusion }))
        }
        ["deadlines"] => req(json!({ "cmd": "deadlines" })),
        ["deadline", "rm", id] => req(json!({ "cmd": "deadline-remove", "id": id })),
        ["project", "list"] | ["projects"] => req(json!({ "cmd": "projects" })),
        ["project", "rm", id] => req(json!({ "cmd": "project-remove", "id": id })),
        ["project", "add", name, due, rest @ ..] => {
            let due = parse_local(due, "23:59")?;
            let (domain, steps) = match rest.first() {
                Some(d) if !d.contains('=') => (Some(d.to_string()), &rest[1..]),
                _ => (None, rest),
            };
            let steps: Vec<Value> = steps
                .iter()
                .map(|s| {
                    let (n, h) = s.rsplit_once('=').ok_or(format!("{s}: STEP=HOURS"))?;
                    let h: f32 = h.replace(',', ".").parse().map_err(|_| format!("{s}: STEP=HOURS"))?;
                    Ok(json!({ "name": n, "hours": h }))
                })
                .collect::<Result<_, String>>()?;
            if steps.is_empty() {
                return Err("STEP=HOURS…".into());
            }
            let project = json!({ "id": name.to_lowercase(), "name": name, "domain": domain, "due": due, "steps": steps });
            req(json!({ "cmd": "project", "project": project }))
        }
        ["project", "step", id, step, "done"] => {
            let v = request(paths, json!({ "cmd": "projects" }))?;
            let mut p = v["data"].as_array().and_then(|ps| ps.iter().find(|p| p["id"] == *id)).cloned().ok_or(format!("{id}?"))?;
            let s = p["steps"].as_array_mut().and_then(|ss| ss.iter_mut().find(|s| s["name"] == *step)).ok_or(format!("{step}?"))?;
            s["done"] = json!(true);
            req(json!({ "cmd": "project", "project": p }))
        }
        ["campaign", "list"] | ["campaigns"] => req(json!({ "cmd": "campaigns" })),
        ["campaign", "add", name, from, to, rest @ ..] => {
            let per_week: u32 = rest.first().map(|n| n.parse().map_err(|_| "PER-WEEK")).transpose()?.unwrap_or(8);
            let campaign = json!({
                "id": name.to_lowercase(), "name": name,
                "start": parse_date(from)?, "end": parse_date(to)?,
                "school_day_minutes": 30, "free_day_minutes": 120, "weekly_target": per_week,
            });
            req(json!({ "cmd": "campaign", "campaign": campaign }))
        }
        ["campaign", "status", name, company, status, rest @ ..] => {
            let v = request(paths, json!({ "cmd": "campaigns" }))?;
            let mut c = find_campaign(&v, name)?;
            let rows = c["rows"].as_array_mut().ok_or("rows")?;
            if !rows.iter().any(|r| r["name"] == *company) {
                rows.push(json!({ "name": company, "status": "to-send" }));
            }
            let row = rows.iter_mut().find(|r| r["name"] == *company).unwrap();
            row["status"] = json!(status);
            match (*status, rest) {
                ("sent", [d, ..]) => row["sent"] = json!(parse_date(d)?),
                ("sent", []) => row["sent"] = json!(today()),
                ("interview", [d, t, ..]) => row["interview"] = json!(parse_local(d, t)?),
                ("interview", [d]) => row["interview"] = json!(parse_local(d, "09:00")?),
                _ => {}
            }
            req(json!({ "cmd": "campaign", "campaign": c }))
        }
        ["campaign", "close", name] => {
            let v = request(paths, json!({ "cmd": "campaigns" }))?;
            let mut c = find_campaign(&v, name)?;
            c["closed"] = json!(true);
            req(json!({ "cmd": "campaign", "campaign": c }))
        }
        ["courses", dir] => {
            let p = std::fs::canonicalize(dir).map_err(|e| format!("{dir}: {e}"))?;
            set(paths, json!({ "courses": p }))
        }
        ["calendar", "groups"] => req(json!({ "cmd": "groups" })),
        ["calendar", "groups", spec] => {
            let mut groups = serde_json::Map::new();
            for pair in spec.split(',').filter(|p| !p.is_empty()) {
                let (f, v) = pair.split_once('=').ok_or("FAMILY=VALUE,…")?;
                let e = groups.entry(f.to_uppercase()).or_insert(json!([]));
                e.as_array_mut().unwrap().push(json!(v));
            }
            // The whole map replaces the old one.
            set(paths, json!({ "groups": null }))?;
            set(paths, json!({ "groups": groups }))
        }
        ["calendar", url] => set(paths, json!({ "calendar_url": url })),
        ["subject", "list"] | ["subject"] => {
            let s = settings(paths)?;
            let lines: Vec<String> = s["domains"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|d| {
                    let names: Vec<&str> = d["calendar_names"].as_array().into_iter().flatten().filter_map(Value::as_str).collect();
                    let flags = format!(
                        "{}{}",
                        if d["spaced"] == true { " spaced" } else { "" },
                        if d["archived"] == true { " archived" } else { "" }
                    );
                    format!("{}{flags} ← {}", d["id"].as_str().unwrap_or(""), names.join(" | "))
                })
                .collect();
            Ok(lines.join("\n"))
        }
        ["subject", verb, id, rest @ ..] => {
            let mut s = settings(paths)?;
            let domains = s["domains"].as_array_mut().ok_or("domains")?;
            if !domains.iter().any(|d| d["id"] == *id) {
                domains.push(json!({ "id": id, "spaced": true }));
            }
            let d = domains.iter_mut().find(|d| d["id"] == *id).unwrap();
            match (*verb, rest) {
                ("set", names) => d["calendar_names"] = json!(names.join(" ").split('|').map(str::trim).filter(|n| !n.is_empty()).collect::<Vec<_>>()),
                ("spaced", [on]) => d["spaced"] = json!(*on == "on"),
                ("archive", []) => d["archived"] = json!(true),
                ("restore", []) => d["archived"] = json!(false),
                _ => return Err(HELP.into()),
            }
            let domains = s["domains"].take();
            set(paths, json!({ "domains": domains }))
        }
        ["rhythm"] => {
            let s = settings(paths)?;
            Ok(serde_json::to_string_pretty(&s["rhythm"]).unwrap_or_default())
        }
        ["rhythm", key, value] => {
            let v: Value = serde_json::from_str(value).unwrap_or(json!(value));
            set(paths, json!({ "rhythm": { *key: v } }))
        }
        ["period", "list"] | ["period"] => {
            let s = settings(paths)?;
            let lines: Vec<String> = s["periods"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|p| format!("{}  {} → {}  {}", p["name"].as_str().unwrap_or(""), p["start"].as_str().unwrap_or(""), p["end"].as_str().unwrap_or(""), p["rule"].as_str().unwrap_or("")))
                .collect();
            Ok(lines.join("\n"))
        }
        ["period", "add", name, from, to, rule] => {
            let mut s = settings(paths)?;
            let mut periods = s["periods"].take();
            periods.as_array_mut().ok_or("periods")?.push(json!({ "name": name, "start": parse_date(from)?, "end": parse_date(to)?, "rule": rule }));
            set(paths, json!({ "periods": periods }))
        }
        ["period", "rm", name] => {
            let mut s = settings(paths)?;
            let mut periods = s["periods"].take();
            periods.as_array_mut().ok_or("periods")?.retain(|p| p["name"] != *name);
            set(paths, json!({ "periods": periods }))
        }
        ["pause"] => set(paths, json!({ "paused_until": "9999-12-31" })),
        ["pause", until] => set(paths, json!({ "paused_until": parse_date(until)? })),
        ["resume"] => set(paths, json!({ "paused_until": null })),
        ["objective", o @ ("pass" | "ranked" | "podium")] => set(paths, json!({ "objective": o })),
        ["lang", l @ ("en" | "fr")] => set(paths, json!({ "lang": l })),
        ["gate", on @ ("on" | "off")] => set(paths, json!({ "gate": *on == "on" })),
        ["refresh"] => req(json!({ "cmd": "refresh" })),
        _ => Err(HELP.into()),
    }
}

fn find_campaign(v: &Value, name: &str) -> Result<Value, String> {
    v["data"]
        .as_array()
        .and_then(|cs| cs.iter().find(|c| c["name"].as_str().is_some_and(|n| n.eq_ignore_ascii_case(name)) || c["id"] == name))
        .cloned()
        .ok_or(format!("{name}?"))
}

fn today() -> String {
    let tz = crate::time::Tz::local();
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    tz.to_local(secs).date.to_string()
}

/// "18/12", "18/12/2026", "2026-12-18", "demain", "sam".
fn parse_date(s: &str) -> Result<String, String> {
    let today = crate::time::Date::parse(&today()).unwrap();
    if let Some(d) = crate::time::Date::parse(s) {
        return Ok(d.to_string());
    }
    let cx = crate::ajout::Context { today, lang: crate::model::Lang::En, domains: &[], projects: &[], campaigns: &[] };
    match crate::ajout::parse(&format!("indispo {s} 10h-11h"), &cx) {
        Ok(crate::ajout::Understood { action: crate::ajout::Action::Busy(b), .. }) => Ok(b.start.date.to_string()),
        _ => Err(format!("{s}: a date (18/12, 2026-12-18, demain, sam)")),
    }
}

fn parse_local(d: &str, t: &str) -> Result<String, String> {
    let t = crate::time::Hm::parse(t).ok_or(format!("{t}: HH:MM"))?;
    Ok(format!("{}T{t}", parse_date(d)?))
}

/// Super+Shift+D: a line in fuzzel, then what was understood, to confirm.
fn add_fuzzel(paths: &Paths) -> Result<String, String> {
    let fr = fr(paths);
    let Some(line) = fuzzel("Boussole › ", &[]) else { return Ok(String::new()) };
    let seen = request(paths, json!({ "cmd": "add", "line": line }))?;
    let text = seen["text"].as_str().unwrap_or("").to_string();
    if seen["ok"] != true {
        // Never a guess: say what is missing, and let the form take over.
        notify("Boussole", &text);
        return Err(text);
    }
    if seen["data"]["understood"] != true {
        notify("Boussole", &text);
        return Ok(text);
    }
    let keep = if fr { "✓ Valider" } else { "✓ Keep" };
    let cancel = if fr { "✗ Annuler" } else { "✗ Cancel" };
    let first = format!("{keep} · {text}");
    match fuzzel("› ", &[&first, cancel]) {
        Some(c) if c == first => {
            let done = request(paths, json!({ "cmd": "add", "line": line, "apply": true })).and_then(ok)?;
            notify("Boussole", &done);
            Ok(done)
        }
        _ => Ok(String::new()),
    }
}

fn notify(title: &str, body: &str) {
    let _ = Command::new("notify-send").args(["-a", "Boussole", title, body]).stdout(Stdio::null()).status();
}

/// fuzzel's `launch-prefix=boussole gate --`: everything goes through here;
/// only games are asked about, and only during a session. If the service is
/// not there, nothing is ever in the way.
pub fn gate(paths: &Paths, cmd: &[String]) -> io::Error {
    let Some((prog, args)) = cmd.split_first() else {
        return io::Error::new(io::ErrorKind::InvalidInput, "boussole gate -- COMMAND…");
    };
    let launch = || Command::new(prog).args(args).exec();
    let Ok(reply) = request(paths, json!({ "cmd": "gate" })) else { return launch() };
    let data = &reply["data"];
    if data["locked"] != true {
        return launch();
    }
    let words: Vec<String> = data["match"].as_array().into_iter().flatten().filter_map(Value::as_str).map(str::to_lowercase).collect();
    let is_game = cmd.iter().any(|a| {
        let base = a.rsplit('/').next().unwrap_or(a).to_lowercase();
        words.iter().any(|w| base.starts_with(w.as_str()) || a.to_lowercase().starts_with(&format!("{w}:")))
    });
    if !is_game {
        return launch();
    }
    let fr = fr(paths);
    let text = reply["text"].as_str().unwrap_or("");
    let go = if fr { "Lancer quand même" } else { "Launch anyway" };
    let back = if fr { "Retour à la séance" } else { "Back to the session" };
    let prompt = if fr { format!("{text}, lancer quand même ? ") } else { format!("{text}, launch anyway? ") };
    match fuzzel(&prompt, &[back, go]) {
        Some(c) if c == go => {
            // No reproach: the session just waits.
            let _ = request(paths, json!({ "cmd": "pause-session", "session": data["session"] }));
            launch()
        }
        _ => io::Error::new(io::ErrorKind::Interrupted, "not launched"),
    }
}
