/// Détection minimale de langue -- pas de crate i18n complète pour deux
/// langues et une poignée de chaînes courtes. `LC_ALL`/`LC_MESSAGES`/`LANG`
/// dans cet ordre (même priorité que la libc), premier qui existe et n'est
/// pas vide décide.
fn detect_french() -> bool {
    for var in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(v) = std::env::var(var) {
            if v.is_empty() {
                continue;
            }
            return v.to_lowercase().starts_with("fr");
        }
    }
    false
}

#[derive(Clone, Copy)]
pub struct Strings {
    pub mode_static: &'static str,
    pub mode_dynamic: &'static str,
    pub footer_hint: &'static str,
    french: bool,
}

impl Strings {
    pub fn selected_count(&self, n: usize) -> String {
        if self.french {
            format!("{n} sélectionné(s)")
        } else {
            format!("{n} selected")
        }
    }
}

pub fn load() -> Strings {
    if detect_french() {
        Strings {
            mode_static: "Statique",
            mode_dynamic: "Diaporama",
            footer_hint: "Échap fermer · ← → h l naviguer · ↓ j sélectionner · ↑ k désélectionner · Tab mode · Entrée appliquer",
            french: true,
        }
    } else {
        Strings {
            mode_static: "Static",
            mode_dynamic: "Slideshow",
            footer_hint: "Esc close · ← → h l navigate · ↓ j select · ↑ k deselect · Tab mode · Enter apply",
            french: false,
        }
    }
}
