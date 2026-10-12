use boussole::bibliotheque::read_pdf;

#[test]
fn slides_without_outline_take_each_page_first_line() {
    let out = "\u{1e}Algorithme de Dantzig\n(principe)\n\u{c}Principe de l'algorithme\n• primal\n\u{c}Exemple numérique\n\u{c}Exemple numérique\nsuite\n\u{c}x = 0\n\u{c}";
    let o = read_pdf(out, 7);
    assert_eq!(o.mtime, 7);
    assert_eq!(o.title.as_deref(), Some("Algorithme de Dantzig (principe)"));
    let h: Vec<(&str, u32)> = o.headings.iter().map(|h| (h.1.as_str(), h.2)).collect();
    assert_eq!(h, vec![("Principe de l'algorithme", 2), ("Exemple numérique", 3)]);
}

#[test]
fn an_outline_wins_over_page_lines() {
    let out = "+\t\"1. Intro\"\t#page=2&zoom=0\n|\t\t\"1.1 Detail\"\t#page=3\n\u{1e}Book\n\u{c}Other\n";
    let o = read_pdf(out, 0);
    let h: Vec<(usize, &str, u32)> = o.headings.iter().map(|h| (h.0, h.1.as_str(), h.2)).collect();
    assert_eq!(h, vec![(1, "1. Intro", 2), (2, "1.1 Detail", 3)]);
}
