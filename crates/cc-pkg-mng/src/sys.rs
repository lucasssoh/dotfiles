//! Queries against the machine: packages, COPRs, services, files. Read-only.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result};
use sha2::{Digest, Sha256};

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

/// `~/x` → `$HOME/x`.
pub fn expand(p: &str) -> PathBuf {
    match p.strip_prefix("~/") {
        Some(rest) => home().join(rest),
        None if p == "~" => home(),
        None => PathBuf::from(p),
    }
}

/// `$HOME/x` → `~/x`, for display.
pub fn tilde(p: &Path) -> String {
    match p.strip_prefix(home()) {
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => p.display().to_string(),
    }
}

pub fn now() -> String {
    humantime::format_rfc3339_seconds(std::time::SystemTime::now()).to_string()
}

/// Packages (or provides) that no installed package satisfies, in one rpm call.
pub fn rpm_missing(names: &[String]) -> Result<BTreeSet<String>> {
    if names.is_empty() {
        return Ok(BTreeSet::new());
    }
    let out = Command::new("rpm")
        .arg("-q")
        .arg("--whatprovides")
        .args(names)
        .env("LC_ALL", "C")
        .stderr(Stdio::null())
        .output()
        .context("running rpm")?;
    // One line per argument, in order; a missing one reads
    // "no package provides NAME".
    let text = String::from_utf8_lossy(&out.stdout);
    Ok(text
        .lines()
        .filter_map(|l| l.strip_prefix("no package provides "))
        .map(|n| n.trim().to_string())
        .collect())
}

/// `owner/project` → is its repo file present?
pub fn copr_enabled(copr: &str) -> bool {
    let Some((owner, project)) = copr.split_once('/') else { return false };
    Path::new(&format!("/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:{owner}:{project}.repo")).exists()
}

pub fn service_enabled(name: &str, user: bool) -> bool {
    let mut cmd = Command::new("systemctl");
    if user {
        cmd.arg("--user");
    }
    cmd.arg("is-enabled").arg(name).stderr(Stdio::null());
    matches!(cmd.output(), Ok(o) if String::from_utf8_lossy(&o.stdout).trim() == "enabled")
}

pub fn on_path(bin: &str) -> bool {
    std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).any(|d| d.join(bin).is_file()))
        .unwrap_or(false)
}

/// Directories never walked when fingerprinting or comparing.
const SKIP: &[&str] = &["target", "node_modules", "__pycache__", ".git"];

/// Every regular file and symlink under `p` (or `p` itself), sorted.
pub fn walk(p: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    fn rec(p: &Path, out: &mut Vec<PathBuf>) {
        let Ok(meta) = std::fs::symlink_metadata(p) else { return };
        if meta.is_dir() {
            let Ok(entries) = std::fs::read_dir(p) else { return };
            let mut children: Vec<PathBuf> = entries.filter_map(|e| e.ok().map(|e| e.path())).collect();
            children.sort();
            for c in children {
                if c.file_name().is_some_and(|n| SKIP.iter().any(|s| n == *s)) {
                    continue;
                }
                rec(&c, out);
            }
        } else {
            out.push(p.to_path_buf());
        }
    }
    rec(p, &mut out);
    out
}

/// Content fingerprint of a set of repo paths: names, file contents, and
/// symlink targets (never followed, so a dangling one cannot break it).
pub fn fingerprint(repo: &Path, paths: &[PathBuf]) -> String {
    let mut h = Sha256::new();
    for root in paths {
        for f in walk(root) {
            let rel = f.strip_prefix(repo).unwrap_or(&f);
            h.update(rel.to_string_lossy().as_bytes());
            h.update([0]);
            match std::fs::read_link(&f) {
                Ok(target) => h.update(target.to_string_lossy().as_bytes()),
                Err(_) => {
                    if let Ok(bytes) = std::fs::read(&f) {
                        h.update(&bytes);
                    }
                }
            }
            h.update([0]);
        }
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Does `dst` hold exactly what `src` holds (file, or directory tree)?
pub fn same_content(src: &Path, dst: &Path) -> bool {
    if src.is_dir() {
        let files = walk(src);
        !files.is_empty()
            && files.iter().all(|f| {
                let rel = f.strip_prefix(src).unwrap();
                same_file(f, &dst.join(rel))
            })
    } else {
        same_file(src, dst)
    }
}

fn same_file(a: &Path, b: &Path) -> bool {
    match (std::fs::read(a), std::fs::read(b)) {
        (Ok(x), Ok(y)) => x == y,
        _ => false,
    }
}

pub fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p).map(|m| m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}
