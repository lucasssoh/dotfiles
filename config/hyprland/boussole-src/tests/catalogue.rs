mod common;

use std::collections::BTreeMap;
use std::path::Path;

use boussole::catalogue::{Catalogue, Ignore, Inclusion, ItemKind};
use boussole::model::Domain;

#[test]
fn reads_the_structure_and_ignores_the_rest() {
    let root = common::tree("catalogue");
    let c = Catalogue::scan(&root, &Ignore::default());
    let ids: Vec<&str> = c.items.iter().map(|i| i.id.as_str()).collect();
    assert_eq!(
        ids,
        [
            "ALGO/Ch1/00_Carte_du_cours.md",
            "ALGO/Ch1/10_Bloc/11_A.md",
            "ALGO/Ch1/10_Bloc/12_B.md",
            "ALGO/Ch1/20_Bloc/21_C.md",
            "ALGO/Ch1/90_Exercices/91_Synthese.md",
            "ALGO/Ch1/90_Exercices/93_Sujets_type_examen.md",
            "LOGIC/Lambda/00_Carte_du_cours.md",
            "LOGIC/Lambda/10_Syntaxe/11_Termes.md",
            "LOGIC/Lambda/10_Syntaxe/12_Substitution.md",
            "LOGIC/Lambda/90_Exercices/93_Sujet_type_examen.md",
            "NET/cours-intro.pdf",
            "NET/notes-cm1.md",
            "NET/TD/00_Sommaire.md",
            "NET/TD/10_Perf/Exo_01_First.md",
            "NET/TD/10_Perf/Exo_02_Second.md",
        ],
        "index, roadmap, References/ and hidden folders left out; natural order"
    );
    assert_eq!(c.domains(), ["ALGO", "LOGIC", "NET"]);

    let get = |s: &str| c.items.iter().find(|i| i.id.ends_with(s)).unwrap();
    let a = get("11_A.md");
    assert_eq!(a.kind, ItemKind::Sheet);
    assert_eq!(a.chapter.as_deref(), Some("Ch1"));
    assert_eq!(a.sections.iter().map(|s| s.num).collect::<Vec<_>>(), [1, 2, 3, 4]);
    assert_eq!(a.exercises_section, Some(5));
    assert_eq!(a.exercises, 3);
    assert!(!a.starred);
    let b = get("12_B.md");
    assert!(b.starred);
    assert_eq!(b.star_note.as_deref(), Some("the proof to know"));
    assert_eq!(get("00_Carte_du_cours.md").kind, ItemKind::Map);
    assert_eq!((get("91_Synthese.md").kind, get("91_Synthese.md").exercises), (ItemKind::Synthesis, 2));
    assert_eq!((get("93_Sujets_type_examen.md").kind, get("93_Sujets_type_examen.md").subjects), (ItemKind::ExamPractice, 2));
    assert_eq!(get("LOGIC/Lambda/90_Exercices/93_Sujet_type_examen.md").subjects, 1);
    assert_eq!(get("Exo_01_First.md").kind, ItemKind::TdExercise);
    assert_eq!(get("cours-intro.pdf").kind, ItemKind::Pdf);
    assert_eq!(get("notes-cm1.md").kind, ItemKind::Notes);
    assert_eq!(get("notes-cm1.md").title, "Notes du CM 1");
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn order_and_stars_set_by_hand_win() {
    let root = common::tree("order");
    let c = Catalogue::scan(&root, &Ignore::default());
    let mut d = Domain { id: "ALGO".into(), ..Domain::default() };
    d.order = vec!["ALGO/Ch1/20_Bloc/21_C.md".into()];
    d.stars.insert("ALGO/Ch1/10_Bloc/12_B.md".into(), false);
    d.stars.insert("ALGO/Ch1/10_Bloc/11_A.md".into(), true);
    let o = c.ordered(&d);
    assert_eq!(o[0].id, "ALGO/Ch1/20_Bloc/21_C.md");
    assert_eq!(o[1].id, "ALGO/Ch1/00_Carte_du_cours.md");
    assert!(o.iter().find(|i| i.id.ends_with("11_A.md")).unwrap().starred);
    assert!(!o.iter().find(|i| i.id.ends_with("12_B.md")).unwrap().starred);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn a_new_file_waits_for_a_decision() {
    let root = common::tree("newfile");
    let c = Catalogue::scan(&root, &Ignore::default());
    let decisions: BTreeMap<String, Inclusion> = c.items.iter().map(|i| (i.id.clone(), Inclusion::Planned)).collect();
    assert!(c.undecided(&decisions).is_empty());
    common::write(&root, "ALGO/Ch1/20_Bloc/22_D.md", "# D\n\n## 1. Formal\n\n## 2. Exercices\n\n### Exercice 1\n");
    common::write(&root, "NET/td3.pdf", "%PDF");
    let c = Catalogue::scan(&root, &Ignore::default());
    let new: Vec<&str> = c.undecided(&decisions).iter().map(|i| i.id.as_str()).collect();
    assert_eq!(new, ["ALGO/Ch1/20_Bloc/22_D.md", "NET/td3.pdf"]);
    let _ = std::fs::remove_dir_all(root);
}

/// The real course folder, read only, when it is there.
#[test]
fn real_course_folder() {
    let root = Path::new(&std::env::var("HOME").unwrap_or_default()).join("courses/mim-m1");
    if !root.is_dir() {
        eprintln!("no {}, skipped", root.display());
        return;
    }
    let c = Catalogue::scan(&root, &Ignore::default());
    for d in ["A&C", "ACL", "Anglais", "L&MC", "OC", "RESEAUX"] {
        assert!(c.domains().contains(&d), "{d} missing");
    }
    assert!(!c.domains().contains(&"boussole-maquette"));
    let ac: Vec<_> = c.items.iter().filter(|i| i.id.starts_with("A&C/Cours_03_Approximation/")).collect();
    assert_eq!(ac.iter().filter(|i| i.kind == ItemKind::Sheet).count(), 16);
    let starred: Vec<&str> = ac.iter().filter(|i| i.starred).map(|i| i.id.rsplit('/').next().unwrap()).collect();
    assert_eq!(starred, ["14_Methode_de_preuve.md", "32_Analyse_2_moins_1_sur_m.md"]);
    let ls = c.get("A&C/Cours_03_Approximation/30_List_Scheduling/31_Algorithme_LS.md").unwrap();
    assert_eq!(ls.exercises, 3);
    assert_eq!(ls.sections.first().map(|s| s.num), Some(1));
    assert_eq!(c.get("A&C/Cours_03_Approximation/90_Exercices/93_Sujets_type_examen.md").unwrap().subjects, 2);
    assert!(c.get("A&C/00_Index.md").is_none() && c.get("A&C/roadmap.md").is_none());
    assert!(c.items.iter().all(|i| !i.id.contains("/References/") && !i.id.contains("/_outils/")));
    assert_eq!(c.get("RESEAUX/TD/30_IPv4_CIDR_plan_adressage/Exo_16_CIDR_reseau_broadcast_plage.md").unwrap().kind, ItemKind::TdExercise);
}
