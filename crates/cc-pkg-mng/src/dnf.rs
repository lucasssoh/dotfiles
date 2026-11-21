//! Reading dnf5's output back: why a transaction failed, how much it
//! downloads, what `--allowerasing` would remove.

/// Why a dnf transaction failed.
#[derive(Debug, PartialEq)]
pub enum Problem {
    /// "No match for argument": packages the repositories don't have.
    NotFound(Vec<String>),
    /// The transaction can't be resolved; dnf's own problem lines.
    /// `erasing` when dnf says `--allowerasing` would get past it.
    Conflict { lines: Vec<String>, erasing: bool },
    /// A repository or a package could not be downloaded.
    Network(Vec<String>),
    /// A signature or key check failed.
    Key(Vec<String>),
    Other(Vec<String>),
}

pub fn classify(output: &[String]) -> Problem {
    let missing: Vec<String> = output
        .iter()
        .filter_map(|l| {
            let l = l.trim();
            l.strip_prefix("No match for argument:")
                .or_else(|| l.strip_prefix("Failed to resolve the transaction: No match for argument:"))
                .map(|p| p.trim().to_string())
        })
        .collect();
    if !missing.is_empty() {
        return Problem::NotFound(missing);
    }
    let has = |needles: &[&str]| -> Vec<String> {
        output
            .iter()
            .filter(|l| needles.iter().any(|n| l.contains(n)))
            .map(|l| l.trim().to_string())
            .take(4)
            .collect()
    };
    let problems = problem_lines(output);
    if !problems.is_empty() {
        let erasing = output.iter().any(|l| l.contains("--allowerasing"));
        return Problem::Conflict { lines: problems, erasing };
    }
    let key = has(&["GPG check FAILED", "Signing key not found", "is not signed", "public key", "OpenPGP check"]);
    if !key.is_empty() {
        return Problem::Key(key);
    }
    let net = has(&["Curl error", "Cannot download", "Failed to download", "Librepo error", "Could not resolve host", "timed out"]);
    if !net.is_empty() {
        return Problem::Network(net);
    }
    Problem::Other(output.iter().rev().take(4).rev().map(|l| l.trim().to_string()).collect())
}

/// dnf's `Problem: …` / `Problem 2: …` lines and the ` - …` lines under
/// them, at most 8.
fn problem_lines(output: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let mut inside = false;
    for l in output {
        let t = l.trim();
        if t.starts_with("Problem") && t.contains(':') {
            inside = true;
            out.push(t.to_string());
        } else if inside && t.starts_with("- ") {
            out.push(format!("  {}", &t[2..]));
        } else if inside {
            inside = false;
        }
    }
    out.truncate(8);
    out
}

/// "Need to download 48 MiB." → "48 MiB"; None when nothing is fetched.
pub fn download_size(output: &[String]) -> Option<String> {
    output.iter().find_map(|l| {
        let i = l.find("Need to download ")?;
        let rest = &l[i + "Need to download ".len()..];
        let size = rest.split('.').next()?.trim();
        (!size.is_empty() && !size.starts_with('0')).then(|| size.to_string())
    })
}

/// The packages a transaction would remove, from dnf's table.
pub fn removals(output: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let mut inside = false;
    for l in output {
        let t = l.trim_end();
        if !t.starts_with(' ') {
            inside = matches!(t.trim(), "Removing:" | "Removing dependent packages:" | "Removing unused dependencies:");
            continue;
        }
        if inside
            && let Some(name) = t.split_whitespace().next()
                && !out.iter().any(|n| n == name) {
                    out.push(name.to_string());
                }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(s: &str) -> Vec<String> {
        s.lines().map(str::to_string).collect()
    }

    #[test]
    fn not_published() {
        let out = lines("Updating and loading repositories:\nNo match for argument: roue-2.6.0\nNo match for argument: prisme-2.6.0");
        assert_eq!(classify(&out), Problem::NotFound(vec!["roue-2.6.0".into(), "prisme-2.6.0".into()]));
    }

    #[test]
    fn conflict_with_hint() {
        let out = lines(
            "Failed to resolve the transaction:\n\
             Problem: cannot install both satty-1:0.22.0-3.coucou.fc45.x86_64 from coucou-shell and satty-0.22.0-1.fc45.x86_64 from terra\n  \
             - package rocm-hip-6.4 requires rocm-libc++, but none of the providers can be installed\n\
             You can try to add to command line:\n  --allowerasing to allow removing of installed packages to resolve problems",
        );
        match classify(&out) {
            Problem::Conflict { lines, erasing } => {
                assert!(erasing);
                assert_eq!(lines.len(), 2);
                assert!(lines[1].starts_with("  package rocm-hip"));
            }
            p => panic!("{p:?}"),
        }
    }

    #[test]
    fn network_and_size() {
        assert!(matches!(classify(&lines("Curl error (6): Couldn't resolve host name")), Problem::Network(_)));
        assert_eq!(download_size(&lines("Total size of inbound packages is 48 MiB. Need to download 48 MiB.")), Some("48 MiB".into()));
        assert_eq!(download_size(&lines("Need to download 0 B.")), None);
    }

    #[test]
    fn removed_packages() {
        let out = lines(
            "Package   Arch   Version   Repository   Size\n\
             Upgrading:\n satty  x86_64  1:0.22.0-3  coucou-shell  2 MiB\n\
             Removing:\n rocm-hip  x86_64  6.4  @System  1 GiB\n\
             Removing dependent packages:\n rocm-runtime  x86_64  6.4  @System  1 MiB\n\
             Transaction Summary:",
        );
        assert_eq!(removals(&out), vec!["rocm-hip".to_string(), "rocm-runtime".to_string()]);
    }
}
