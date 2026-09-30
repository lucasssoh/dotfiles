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
    git(repo, &["checkout", "--quiet", rev]).map(|_| ())
}

pub fn checkout_detached(repo: &Path, rev: &str) -> Result<()> {
    git(repo, &["checkout", "--quiet", "--detach", rev]).map(|_| ())
}

/// Fast-forward the current branch to its upstream.
pub fn fast_forward(repo: &Path) -> Result<()> {
    if git_ok(repo, &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).is_none() {
        bail!("the current branch has no upstream to follow");
    }
    git(repo, &["merge", "--ff-only", "--quiet", "@{u}"])
        .map(|_| ())
        .context("the local branch has diverged from its upstream — rebase or merge by hand")
}
