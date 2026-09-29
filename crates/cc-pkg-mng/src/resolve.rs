//! Dependency order between units.

use std::collections::BTreeSet;

use anyhow::{Result, bail};

use crate::manifest::Units;

/// `requested` plus everything they require, dependencies first.
pub fn closure(units: &Units, requested: &[String]) -> Result<Vec<String>> {
    let mut order = Vec::new();
    let mut done = BTreeSet::new();
    let mut active = Vec::new();
    for name in requested {
        visit(units, name, &mut order, &mut done, &mut active)?;
    }
    Ok(order)
}

fn visit(
    units: &Units,
    name: &str,
    order: &mut Vec<String>,
    done: &mut BTreeSet<String>,
    active: &mut Vec<String>,
) -> Result<()> {
    if done.contains(name) {
        return Ok(());
    }
    if active.iter().any(|a| a == name) {
        bail!("dependency cycle: {} -> {name}", active.join(" -> "));
    }
    let Some(unit) = units.get(name) else {
        match active.last() {
            Some(parent) => bail!("{parent} requires \"{name}\", which is not a unit"),
            None => bail!("no unit named \"{name}\" (see `cc-pkg-mng list`)"),
        }
    };
    active.push(name.to_string());
    for dep in &unit.requires {
        visit(units, dep, order, done, active)?;
    }
    active.pop();
    done.insert(name.to_string());
    order.push(name.to_string());
    Ok(())
}

/// Installed units that require `name`, directly or not.
pub fn dependents(units: &Units, installed: &BTreeSet<String>, name: &str) -> Vec<String> {
    installed
        .iter()
        .filter(|other| other.as_str() != name)
        .filter(|other| {
            closure(units, std::slice::from_ref(other))
                .map(|c| c.iter().any(|n| n == name))
                .unwrap_or(false)
        })
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Unit;

    fn units(spec: &[(&str, &[&str])]) -> Units {
        spec.iter()
            .map(|(name, deps)| {
                let text = format!(
                    "name = \"{name}\"\nlayer = \"core\"\nsummary = \"x\"\nrequires = [{}]\n",
                    deps.iter().map(|d| format!("\"{d}\"")).collect::<Vec<_>>().join(", ")
                );
                (name.to_string(), toml::from_str::<Unit>(&text).unwrap())
            })
            .collect()
    }

    #[test]
    fn dependencies_come_first() {
        let u = units(&[("bar", &["hyprland", "fonts"]), ("hyprland", &["base"]), ("fonts", &[]), ("base", &[])]);
        assert_eq!(closure(&u, &["bar".into()]).unwrap(), ["base", "hyprland", "fonts", "bar"]);
    }

    #[test]
    fn cycles_and_unknowns_are_errors() {
        let u = units(&[("a", &["b"]), ("b", &["a"])]);
        assert!(closure(&u, &["a".into()]).unwrap_err().to_string().contains("cycle"));
        let u = units(&[("a", &["ghost"])]);
        assert!(closure(&u, &["a".into()]).unwrap_err().to_string().contains("ghost"));
    }

    #[test]
    fn dependents_are_transitive() {
        let u = units(&[("bar", &["hyprland"]), ("hyprland", &["base"]), ("base", &[]), ("fonts", &[])]);
        let installed: BTreeSet<String> = ["bar", "hyprland", "base", "fonts"].map(String::from).into();
        assert_eq!(dependents(&u, &installed, "base"), ["bar", "hyprland"]);
        assert!(dependents(&u, &installed, "fonts").is_empty());
    }
}
