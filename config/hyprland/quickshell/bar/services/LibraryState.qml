pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// The library's picker (Super+F): one window over everything, to find a
// document and open it in Liseuse.
//
// Its rows come from `liseuse list`: everything Liseuse indexes (~/Livres,
// sources.conf), most recent first, with the page you left each one at.
// One run per opening (~0.3 s), in the background.
//
// The search runs here, on each keystroke, over titles and file names
// (~1000 rows: a few milliseconds).
Singleton {
    id: root

    property bool shown: false
    property bool open: false
    property string screenName: ""
    // What the field starts with (`searchLibrary` over IPC).
    property string initialQuery: ""

    // Liseuse's rows ({ path, title, page }).
    property var others: []
    property bool loadingOthers: false
    // The rows as the picker searches them, rebuilt when Liseuse answers.
    property var rows: []

    readonly property string liseuse: Quickshell.env("HOME") + "/.local/bin/liseuse"

    function show(screen, query) {
        root.initialQuery = query || "";
        root.screenName = screen ? screen.name : "";
        hideTimer.stop();
        root.shown = true;
        root.open = true;
        root.reload();
    }
    function hide() {
        if (!root.open) return;
        root.open = false;
        hideTimer.restart();
    }
    function toggle(screen) {
        if (root.open) root.hide();
        else root.show(screen);
    }
    Timer { id: hideTimer; interval: 180; onTriggered: root.shown = false }

    function reload() {
        if (!lister.running) {
            root.loadingOthers = true;
            lister.buffer = [];
            lister.running = true;
        }
        root.merge();
    }

    Process {
        id: lister
        property var buffer: []
        command: [root.liseuse, "list"]
        stdout: SplitParser {
            onRead: line => lister.buffer.push(line)
        }
        onExited: {
            const out = [];
            for (const line of lister.buffer) {
                const tab = line.lastIndexOf("\t");
                if (tab < 0) continue;
                let label = line.slice(0, tab), page = "";
                const dash = label.indexOf("   —   ");
                if (dash >= 0) { page = label.slice(dash + 7); label = label.slice(0, dash); }
                // The leading format glyph and its two spaces.
                label = label.replace(/^\S+\s\s/, "");
                out.push({ path: line.slice(tab + 1), title: label, page: page });
            }
            root.others = out;
            root.loadingOthers = false;
            root.merge();
        }
    }

    function fold(s) {
        return (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[_\-./]+/g, " ");
    }

    function merge() {
        const out = [];
        let order = 0;
        {
            root.others.forEach((o, n) => {
                const home = Quickshell.env("HOME");
                const book = o.path.startsWith(home + "/Livres/");
                const where = book ? ProgrammeState.tr("Books", "Livres") : ProgrammeState.tr("Elsewhere", "Ailleurs");
                const ext = o.path.slice(o.path.lastIndexOf(".") + 1).toLowerCase();
                const row = {
                    path: o.path, id: "", course: false,
                    subject: book ? "~books" : "~other", subjectLabel: where, chapter: "",
                    group: where, title: o.title, file: o.path.slice(o.path.lastIndexOf("/") + 1), num: "",
                    kind: ext, filter: "books", kindLabel: ext.toUpperCase(),
                    state: "", detail: "", planned: false, page: o.page, recent: n,
                    sections: [], minutes: 0, task: null, order: order++
                };
                row.own = root.fold(row.title + " " + row.file);
                row.hay = root.fold(row.title + " " + o.path.replace(home + "/", ""));
                row.secHay = [];
                out.push(row);
            });
        }
        root.rows = out;
    }

    // Rows matching `query` within `filter` ("all" | "sheet" | "ex" | "pdf"
    // | "books") and `subject` ("" for all): every word must be found, in
    // the file's own title, its chapter and subject, or one section. Ranked
    // in that order (score 0, 1, 2), groups by their best row so a chapter
    // stays together; then the course's order, books by recency.
    function search(query, filter, subject) {
        const words = root.fold(query).split(" ").filter(w => w.length > 0);
        const res = [];
        for (const r of root.rows) {
            if (filter !== "all" && r.filter !== filter) continue;
            if (subject !== "" && r.subject !== subject) continue;
            if (words.length === 0) { res.push({ row: r, score: 0, section: -1 }); continue; }
            let ok = true, score = 0, section = -1;
            for (const w of words) {
                if (r.own.indexOf(w) >= 0) continue;
                if (r.hay.indexOf(w) >= 0) { score = Math.max(score, 1); continue; }
                const k = r.secHay.findIndex(h => h.indexOf(w) >= 0);
                if (k < 0) { ok = false; break; }
                score = 2;
                if (section < 0) section = k;
            }
            if (!ok) continue;
            res.push({ row: r, score: score, section: section });
        }
        if (words.length > 0) {
            const best = {};
            for (const h of res) best[h.row.group] = Math.min(best[h.row.group] ?? 9, h.score);
            const tie = (a, b) => a.row.course === b.row.course ? (a.row.course ? a.row.order - b.row.order : a.row.recent - b.row.recent) : (a.row.course ? -1 : 1);
            res.sort((a, b) => best[a.row.group] - best[b.row.group]
                || (a.row.group === b.row.group ? a.score - b.score || tie(a, b) : tie(a, b)));
        }
        return res;
    }

    // Started from the picker: opened in Liseuse.
    function activate(row, section) {
        const args = [root.liseuse, "open", row.path];
        const s = section >= 0 ? row.sections[section] : null;
        if (s && s.page) args.push("--page", String(s.page));
        else if (s) args.push("--section", s.heading || s.title);
        root.hide();
        Quickshell.execDetached(args);
    }
    function openAtStart(row) {
        root.hide();
        Quickshell.execDetached([root.liseuse, "open", row.path, "--page", "1"]);
    }
}
