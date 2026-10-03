//! The checkout: tags, channels, moving between versions.

use std::path::Path;
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail};

pub const DEFAULT_URL: &str = "https://github.com/lucasssoh/dotfiles.git";

/// The repository `init` clones: $COUCOU_SHELL_URL, or the public one.
pub fn url() -> String {
    std::env::var("COUCOU_SHELL_URL").unwrap_or_else(|_| DEFAULT_URL.to_string())
}

pub fn git(repo: &Path, args: &[&str]) -> Result<String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .with_context(|| format!("running git {}", args.join(" ")))?;
    if !out.status.success() {
        bail!("git {} failed: {}", args.join(" "), String::from_utf8_lossy(&out.stderr).trim());
    }
    // trim_end only: `status --porcelain` lines start with a meaningful space.
    Ok(String::from_utf8_lossy(&out.stdout).trim_end().to_string())
}

fn git_ok(repo: &Path, args: &[&str]) -> Option<String> {
    git(repo, args).ok().filter(|s| !s.is_empty())
}

/// Tracked files changed (untracked files do not block a version change).
pub fn dirty(repo: &Path) -> Result<Vec<String>> {
    Ok(git(repo, &["status", "--porcelain", "--untracked-files=no"])?
        .lines()
        .map(str::to_string)
        .collect())
}

/// Release tags, newest first (vMAJOR.MINOR.PATCH, version order).
pub fn release_tags(repo: &Path) -> Result<Vec<String>> {
    Ok(git(repo, &["tag", "--list", "v*", "--sort=-v:refname"])?
        .lines()
        .map(str::to_string)
        .collect())
}

pub fn exact_tag(repo: &Path) -> Option<String> {
    git_ok(repo, &["describe", "--tags", "--exact-match", "HEAD"])
}

pub fn head(repo: &Path) -> Result<String> {
    git(repo, &["rev-parse", "HEAD"])
}

pub fn describe(repo: &Path) -> String {
    git_ok(repo, &["describe", "--tags", "--always", "--dirty"]).unwrap_or_default()
}

pub fn branch(repo: &Path) -> Option<String> {
    git_ok(repo, &["branch", "--show-current"])
}

/// The remote's default branch (origin/HEAD), falling back to master.
pub fn default_branch(repo: &Path) -> String {
    git_ok(repo, &["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        .and_then(|r| r.strip_prefix("origin/").map(str::to_string))
        .unwrap_or_else(|| "master".to_string())
}

pub fn checkout(repo: &Path, rev: &str) -> Result<()> {
    let _hold = HyprlandHold::new();
    git(repo, &["checkout", "--quiet", rev]).map(|_| ())
}

pub fn checkout_detached(repo: &Path, rev: &str) -> Result<()> {
    let _hold = HyprlandHold::new();
    git(repo, &["checkout", "--quiet", "--detach", rev]).map(|_| ())
}

/// Fast-forward the current branch to its upstream.
pub fn fast_forward(repo: &Path) -> Result<()> {
    if git_ok(repo, &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).is_none() {
        bail!("the current branch has no upstream to follow");
    }
    let _hold = HyprlandHold::new();
    git(repo, &["merge", "--ff-only", "--quiet", "@{u}"])
        .map(|_| ())
        .context("the local branch has diverged from its upstream — rebase or merge by hand")
}


/// Hyprland reloads its config as soon as a file it watches changes, and
/// git replaces a changed file by deleting it and writing a new one. Caught
/// in that gap, Hyprland reports `hyprland.lua: No such file or directory`,
/// and the banner stays: it was watching the deleted file and never sees
/// the new one. So, while the checkout moves, autoreload is paused, then
/// Hyprland reloads once on the new files. The reload also puts the option
/// back as the config sets it, and hyprland.lua's `config.reloaded` hook
/// replays the monitor setup.
///
/// Only inside a Hyprland session (over SSH or from a TTY there is nothing
/// to pause), and only reloads if the pause took.
struct HyprlandHold {
    held: bool,
}

impl HyprlandHold {
    fn new() -> Self {
        let held = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
            && Command::new("hyprctl")
                .args(["eval", "hl.config({ misc = { disable_autoreload = true } })"])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .is_ok_and(|s| s.success());
        HyprlandHold { held }
    }
}

impl Drop for HyprlandHold {
    fn drop(&mut self) {
        if self.held {
            let _ = Command::new("hyprctl")
                .arg("reload")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
    }
}
