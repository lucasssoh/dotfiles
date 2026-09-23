#!/usr/bin/env python3
# ============================================================
# md2pdf.py — the Markdown half of Liseuse
# ============================================================
# zathura renders PDF, EPUB, MOBI, CBZ and DjVu through mupdf, and no
# amount of configuration makes it render Markdown: mupdf has no parser
# for it. So a .md file gets turned into a PDF first, and everything
# downstream -- the dark theme, the reading position, the "en cours"
# ranking, F1, the zen bracket -- keeps working unchanged because what
# reaches zathura is an ordinary document.
#
# ---- Why this toolchain --------------------------------------------
# The target is GitHub's rendered view, because that is what these files
# were written against. GitHub's own parser (cmark-gfm) is not packaged
# for Fedora, and neither is pandoc, so the closest available stack is
# python-markdown plus the pymdown-extensions that fill in the GFM
# delta: tables, fenced code, strikethrough, task lists, autolinks,
# footnotes. Syntax highlighting is Pygments, asked for GitHub's own
# `github-dark` palette by name -- that part is not an approximation.
#
# HTML then goes to WeasyPrint rather than to a headless browser. A
# survey of the 33 markdown files on this machine found tables in 8 and
# fenced code in 6, and zero mermaid diagrams, zero images and zero task
# lists -- so nothing here needs a JavaScript engine, and Chromium would
# have cost ~200MB and a second of start-up per render to provide a
# feature none of these documents use.
#
# UML diagrams are PlantUML (```plantuml blocks) for the same reason:
# it is a JVM that writes SVG, which WeasyPrint inlines as-is, where
# mermaid would have brought the Chromium back through mmdc. See
# _Plantuml below.
#
# ---- Caching --------------------------------------------------------
# A render costs ~450ms for a document the size of the repo's README, so
# it happens once per (source, stylesheet) state and never again. The
# cache key is the mtime of BOTH the .md and markdown.css: editing the
# stylesheet has to invalidate every rendered document, or the next open
# would show a stale look with no way to tell.
# ============================================================
import hashlib
from html import escape as html_escape
import json
import os
import re
import subprocess
import sys

CSS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "markdown.css")

# Fallback shape, used only when the compositor cannot be asked (no
# Hyprland, no hyprctl, an empty monitor list). 16:10 because that is the
# commonest laptop panel, but nothing downstream depends on the value
# being right -- see page_size().
FALLBACK_ASPECT = 16 / 10

# The long edge of the generated page. Arbitrary, and it stays arbitrary:
# the page is always scaled to the window by zathura's best-fit, so this
# only fixes the ratio of physical size to font size, i.e. how much text
# lands on one screenful. 240mm against a 10.5pt body is roughly 90
# characters a line.
PAGE_LONG_EDGE_MM = 240.0


def screen_aspect() -> float:
    """Width / height of the monitor this will be read on.

    Asked of the compositor at render time rather than written down,
    because the answer is different on a 16:10 laptop, a 16:9 external, a
    4:3 projector and a rotated portrait panel -- and the same machine
    meets several of those in a day. The focused monitor is the right one
    to ask about: it is where the reader window is about to open.

    `transform` is a 0-7 rotation/flip code; the odd values are the 90
    and 270 degree rotations, where the reported width and height are of
    the unrotated panel and have to be swapped.
    """
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True,
                             text=True, timeout=2).stdout
        monitors = json.loads(out)
    except Exception:
        return FALLBACK_ASPECT
    if not monitors:
        return FALLBACK_ASPECT
    mon = next((m for m in monitors if m.get("focused")), monitors[0])
    w, h = float(mon.get("width", 0)), float(mon.get("height", 0))
    if int(mon.get("transform", 0)) % 2 == 1:
        w, h = h, w
    if w <= 0 or h <= 0:
        return FALLBACK_ASPECT
    return w / h


def page_size(aspect: float) -> str:
    """An `@page { size }` matching the screen's shape.

    Matching it is a comfort choice, not a correctness one: zathura
    best-fits whatever page shape onto whatever window, and zathurarc
    binds Space to "turn the page, then best-fit" so a mismatch would
    only mean letterboxing, never a broken page turn. Getting it close
    just means the letterbox is nearly nothing and a screenful of text is
    a whole page.
    """
    return "%.1fmm %.1fmm" % page_dims(aspect)


def page_dims(aspect: float) -> tuple:
    """(width, height) of the page in mm; see page_size()."""
    if aspect >= 1.0:
        return PAGE_LONG_EDGE_MM, PAGE_LONG_EDGE_MM / aspect
    return PAGE_LONG_EDGE_MM * aspect, PAGE_LONG_EDGE_MM


def desktop_is_dark() -> bool:
    """The desktop's own light/dark choice.

    Read from the same gsettings key quickshell's AppearanceState.qml
    reads and writes, so Liseuse follows the bar's toggle rather than
    keeping a second switch of its own. Anything that is not exactly
    'prefer-dark' means light -- the same two-state reading that file
    documents, and the safe one for a value a future GNOME might add.

    Dark on failure: this reader is dark by default and a document that
    stays dark when gsettings is missing is far less jarring than one
    that flashes white.
    """
    try:
        out = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface",
                              "color-scheme"], capture_output=True, text=True,
                             timeout=2).stdout
    except Exception:
        return True
    return "prefer-dark" in out

# The GFM delta over plain CommonMark, plus the two niceties (toc,
# attr_list) that documents written for GitHub tend to assume.
EXTENSIONS = [
    "tables",
    "fenced_code",
    "footnotes",
    "attr_list",
    "md_in_html",
    "sane_lists",
    "toc",
    "pymdownx.tasklist",
    "pymdownx.tilde",       # ~~strikethrough~~
    "pymdownx.magiclink",   # bare URLs become links, as on GitHub
    "pymdownx.highlight",
    "pymdownx.superfences",
]
EXTENSION_CONFIGS = {
    "pymdownx.highlight": {
        # Classes rather than inline styles, so the Pygments stylesheet
        # below is what colors the code and a change there needs no
        # re-parse of the markdown.
        "noclasses": False,
        "pygments_style": "github-dark",
        "linenums": False,
    },
    "pymdownx.tasklist": {"custom_checkbox": False},
}

# ---- PlantUML --------------------------------------------------------
# A ```plantuml (or ```uml) block becomes an inline SVG. The fence
# formatter does NOT run plantuml itself: it hands back a placeholder and
# queues the source, and render() then sends every diagram of the
# document through ONE `plantuml -pipe`. The JVM start-up is the whole
# cost of a diagram, so one process per block would make a course's
# notes with ten diagrams take ten times as long to open.
#
# The palette is markdown.css's, so a UML class box looks like the rest
# of the page instead of PlantUML's default yellow, and follows the
# light/dark toggle like the code does. It goes in through `-config`
# rather than being pasted into each diagram: pasted lines shifted every
# error's line number by their own count. A diagram's own skinparams
# come after the config and still win.
_UML_PALETTE = {
    "dark":  {"fg": "#e5e5ea", "line": "#8e8e93", "fill": "#2c2c2e", "note": "#141416"},
    "light": {"fg": "#1c1c1e", "line": "#636366", "fill": "#ececf0", "note": "#f7f7f9"},
}
_UML_CONFIG = """skinparam backgroundColor transparent
skinparam defaultFontName sans-serif
skinparam defaultFontColor {fg}
skinparam ArrowColor {line}
skinparam ArrowFontColor {fg}
skinparam BorderColor {line}
<style>
element {{ BackGroundColor {fill}; LineColor {line}; FontColor {fg}; }}
note {{ BackGroundColor {note}; }}
</style>
"""
# Characters base64 never produces, so no SVG can contain it -- and
# -nometadata drops the base64 copy of the source PlantUML would
# otherwise embed in every SVG anyway.
_UML_DELIM = "@@liseuse-uml@@"
_UML_SLOT = re.compile(r"<!--liseuse-uml:(\d+)-->")
_UML_START = re.compile(r"^\s*@start\w*", re.M)
# On a syntax error PlantUML still writes an SVG -- a picture of the
# source with its own upgrade nag on top -- and says what went wrong
# only on stderr, as "ERROR / <0-based line> / <message>", once per
# failed diagram and in order. A real diagram is told apart by the
# data-diagram-type attribute its <svg> carries and the error one lacks.
# A .puml file opened on its own: no markdown around it, one diagram
# per page, each drawn as large as the page allows. A file may hold
# several @startuml...@enduml; the text between them is ignored, as
# plantuml itself does.
PUML_EXTENSIONS = (".puml", ".plantuml", ".pu", ".iuml")
_UML_BLOCK = re.compile(r"^\s*@start\w*.*?^\s*@end\w*[^\n]*", re.M | re.S)
_UML_ERROR = re.compile(r"^ERROR\n(\d+)\n(.*)$", re.M)


class _Plantuml:
    def __init__(self, theme: str):
        self.config = _UML_CONFIG.format(**_UML_PALETTE.get(theme, _UML_PALETTE["dark"]))
        self.sources = []   # what plantuml gets
        self.written = []   # what the document says
        self.offsets = []   # lines added in front, to report the document's line numbers

    def fence(self, source, language, class_name, options, md, **kwargs):
        self.written.append(source)
        # Bare diagrams (no @startuml) are accepted, as on most renderers.
        if _UML_START.search(source):
            self.sources.append(source)
            self.offsets.append(0)
        else:
            self.sources.append("@startuml\n%s\n@enduml" % source)
            self.offsets.append(1)
        return '<div class="uml"><!--liseuse-uml:%d--></div>' % (len(self.sources) - 1)

    def fill(self, html: str) -> str:
        if not self.sources:
            return html
        svgs, errors = self._run()
        errors = iter(errors)

        def repl(m):
            i = int(m.group(1))
            svg = svgs[i] if i < len(svgs) else ""
            if "data-diagram-type" in svg:
                # PlantUML pins the size twice over: an inline
                # style="width:..px;height:..px", which beats any stylesheet
                # (a tall diagram then ran off the bottom of the page), and
                # preserveAspectRatio="none", which stretches the drawing to
                # whatever box it lands in. Both go; the width/height
                # attributes stay as the natural size, and the default
                # ratio (centred, uniform scale) lets markdown.css size the
                # box freely -- a whole page, for a .puml.
                svg = svg[svg.index("<svg"):]
                head, rest = svg.split(">", 1)
                head = re.sub(r' (?:style|preserveAspectRatio)="[^"]*"', "", head)
                return head + ">" + rest
            # plantuml missing, dead, or the diagram does not parse: its
            # source, readable, with the reason on top rather than a hole
            # in the page.
            err = next(errors, None) if svg else None
            if err:
                line = int(err[0]) + 1 - self.offsets[i]
                why = "PlantUML, line %d: %s" % (line, err[1])
            else:
                why = "PlantUML did not render this diagram"
            return '<p class="uml-error">%s</p><pre><code>%s</code></pre>' % (
                html_escape(why), html_escape(self.written[i]))

        return _UML_SLOT.sub(repl, html)

    def _run(self):
        import tempfile

        with tempfile.NamedTemporaryFile("w", suffix=".puml", encoding="utf-8") as cfg:
            cfg.write(self.config)
            cfg.flush()
            try:
                proc = subprocess.run(
                    ["plantuml", "-tsvg", "-nometadata", "-config", cfg.name,
                     "-pipe", "-pipedelimitor", _UML_DELIM],
                    input="\n".join(self.sources), capture_output=True,
                    text=True, timeout=60)
            except Exception as exc:
                sys.stderr.write("md2pdf: plantuml unavailable (%s)\n" % exc)
                return [], []
        return proc.stdout.split(_UML_DELIM), _UML_ERROR.findall(proc.stderr)


# Relative links between documents -- `[Installation](docs/installation.md)`
# -- are the backbone of a docs/ directory, and a PDF viewer has no
# notion of "the markdown file next to this one". Rewriting them to
# absolute file:// URIs is what lets zathura's link-follow hand them
# back to the desktop, where liseuse is registered as the handler for
# text/markdown and opens the target as a new reading session.
#
# Anchors (#section) and absolute URLs are left exactly as they are.
_LINK = re.compile(r'(?<=href=")([^"#][^"]*\.(?:md|markdown))(#[^"]*)?(?=")', re.I)


# `| | |` over `|---|---|` is a common GitHub idiom for a table that is
# a list of label/value pairs and wants no header at all. python-markdown
# faithfully emits a <thead> of empty <th>s for it, which markdown.css
# then paints as a full-width grey band -- on screen it reads as a
# rendering fault rather than as an empty row. Half the tables in this
# repo's own docs/ are written that way.
#
# The test is on the text content rather than on an exact tag shape, so
# an alignment attribute or a stray &nbsp; doesn't defeat it.
_THEAD = re.compile(r"<thead>.*?</thead>", re.S | re.I)
_TAGS = re.compile(r"<[^>]+>|&nbsp;|\s")


def _drop_empty_theads(html: str) -> str:
    def repl(m):
        return "" if not _TAGS.sub("", m.group(0)) else m.group(0)

    return _THEAD.sub(repl, html)


def _absolutise_links(html: str, source: str) -> str:
    base = os.path.dirname(os.path.abspath(source))

    def repl(m):
        target, anchor = m.group(1), m.group(2) or ""
        if "://" in target:
            return m.group(0)
        return "file://" + os.path.normpath(os.path.join(base, target)) + anchor

    return _LINK.sub(repl, html)


def cache_path(source: str, cache_dir: str) -> str:
    """Where the rendered PDF for `source` lives.

    A hash of the absolute path, as a DIRECTORY, with the document's own
    name inside it. The hash is what keeps two READMEs in different
    projects apart and what keeps the path stable across renders --
    zathura stores the reading position against this filename, so a name
    that moved per render would lose the position on every edit.

    But the hash used to be the filename itself, and that leaked: zathura
    titles its window after the basename it was handed, so the bar (see
    quickshell ActiveWindow.qml, which reads that title) showed
    "[3/9] 0ee726627caaadcc" for a markdown document. Pushing the hash
    into a directory keeps every property it had and gives the window a
    name a human wrote.
    """
    digest = hashlib.sha1(os.path.abspath(source).encode("utf-8")).hexdigest()[:16]
    stem = os.path.splitext(os.path.basename(source))[0]
    return os.path.join(cache_dir, digest, stem + ".pdf")


def meta_path(pdf: str) -> str:
    return os.path.splitext(pdf)[0] + ".meta"


def render_key(theme: str, aspect: float) -> str:
    """Everything outside the source file that changes the output.

    Kept in a sidecar rather than folded into the PDF's filename, and
    that is the whole point: zathura records the reading position against
    the filename, so a name that moved when the desktop switched to light
    would drop you back at page 1 every time you flipped the theme.
    Aspect is rounded because a monitor that reports 1.60000001 is the
    same screen as one reporting 1.6, and re-rendering on that is waste.
    """
    return "%s %.3f" % (theme, aspect)


def is_fresh(source: str, pdf: str, key: str) -> bool:
    try:
        out = os.stat(pdf).st_mtime
    except OSError:
        return False
    try:
        if os.stat(source).st_mtime > out:
            return False
        if os.stat(CSS_PATH).st_mtime > out:
            return False
    except OSError:
        return False
    # The theme and the screen shape are not files, so they cannot be
    # compared by mtime; the last render wrote what it used.
    try:
        with open(meta_path(pdf), encoding="utf-8") as fh:
            if fh.read().strip() != key:
                return False
    except OSError:
        return False
    return True


# Dark is GitHub's own palette, shipped under that name. Light is NOT:
# Pygments has `github-dark` and no `github-light` (checked against
# get_all_styles(); assuming the symmetry cost one crash), so the light
# side is Pygments' own baseline, which is a close enough relative --
# grey comments, red strings, bold keywords on an almost-white ground.
#
# The fallbacks exist because a style name is a runtime lookup against
# whatever Pygments happens to ship, and a missing one raises rather than
# degrades. A document rendering with plain-looking code beats a document
# that does not render.
_STYLES = {"dark": ("github-dark", "monokai", "native"),
           "light": ("default", "friendly", "bw")}


def _pygments_style(theme: str) -> str:
    from pygments.styles import get_style_by_name

    for name in _STYLES.get(theme, _STYLES["dark"]):
        try:
            get_style_by_name(name)
            return name
        except Exception:
            continue
    return "default"


def render(source: str, pdf: str, theme: str, aspect: float) -> None:
    import markdown
    from pygments.formatters import HtmlFormatter
    from weasyprint import HTML

    with open(source, encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    uml = _Plantuml(theme)
    configs = dict(EXTENSION_CONFIGS)
    configs["pymdownx.superfences"] = {"custom_fences": [
        {"name": lang, "class": "uml", "format": uml.fence}
        for lang in ("plantuml", "uml")
    ]}
    standalone = source.lower().endswith(PUML_EXTENSIONS)
    if standalone:
        blocks = _UML_BLOCK.findall(text) or [text]
        body = uml.fill("".join(
            '<section class="uml-page">%s</section>' % uml.fence(b, "plantuml", "uml", {}, None)
            for b in blocks))
    else:
        md = markdown.Markdown(extensions=EXTENSIONS, extension_configs=configs)
        body = uml.fill(md.convert(text))
        body = _drop_empty_theads(_absolutise_links(body, source))

    with open(CSS_PATH, encoding="utf-8") as fh:
        css = fh.read()
    # The two things markdown.css deliberately leaves open: the page
    # shape, which only the live compositor knows, and the syntax
    # palette, which has to follow the desktop. Both are appended so they
    # win over anything in the stylesheet.
    css += "\n@page { size: %s; }\n" % page_size(aspect)
    # A diagram is one image, so it cannot break across pages: taller
    # than a page, it was cut off at the bottom -- and `break-inside:
    # avoid` pushed it past its own heading first, leaving that alone on
    # an empty page. Capped at the page's text height (the @page margins
    # in markdown.css are 9% of the page WIDTH, top and bottom), less
    # room for the heading above it; the SVG keeps its ratio and shrinks.
    w, h = page_dims(aspect)
    text_h = h - 2 * 0.09 * w
    css += ".uml svg { max-height: %.1fmm; }\n" % (text_h * 0.8)
    # Alone on its page, a diagram gets the page's whole text box -- a
    # small one grows to fill it rather than sitting in a corner.
    css += ".uml-page .uml svg { width: 100%%; height: %.1fmm; max-height: none; }\n" % (text_h * 0.97)
    css += HtmlFormatter(style=_pygments_style(theme)).get_style_defs(".highlight")

    # The document's own H1 is usually its real title; the filename is
    # the fallback. This lands in the PDF metadata, which is what
    # zathura puts in the window title.
    m = None if standalone else re.search(r"^#\s+(.+)$", text, re.M)
    title = m.group(1).strip() if m else os.path.basename(source)

    # markdown.css keys its light palette off this attribute; dark is the
    # bare default, so nothing is stamped for it.
    attr = ' data-theme="light"' if theme == "light" else ""
    html = (
        f"<!doctype html><html{attr}><head><meta charset='utf-8'>"
        f"<title>{title}</title><style>{css}</style></head>"
        f"<body>{body}</body></html>"
    )

    os.makedirs(os.path.dirname(pdf), exist_ok=True)

    # A sidecar naming the source, written next to the PDF. zathura's
    # history records the path it was HANDED -- the cache file -- so
    # without this, nothing could tell that <sha1>.pdf is README.md, and
    # every markdown document would rank as "never opened" no matter how
    # far into it you were. The hash is one-way; this is the way back.
    with open(os.path.splitext(pdf)[0] + ".src", "w", encoding="utf-8") as fh:
        fh.write(os.path.abspath(source))

    # Written to a temporary name and moved into place, so a render that
    # dies halfway (or two of them racing) can never leave a truncated
    # PDF that `is_fresh` would then happily consider valid.
    tmp = pdf + ".%d.tmp" % os.getpid()
    # base_url is the source's own directory: relative image paths in the
    # markdown have to resolve against the document, not against wherever
    # this script was invoked from.
    HTML(string=html, base_url=os.path.abspath(source)).write_pdf(tmp)
    os.replace(tmp, pdf)

    # Written last, so an interrupted render leaves a key that does not
    # match and the next call redoes the work rather than trusting it.
    with open(meta_path(pdf), "w", encoding="utf-8") as fh:
        fh.write(render_key(theme, aspect))


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: md2pdf.py <source.md> <cache-dir>\n")
        return 2
    source, cache_dir = argv[1], argv[2]
    pdf = cache_path(source, cache_dir)
    theme = "dark" if desktop_is_dark() else "light"
    aspect = screen_aspect()
    if not is_fresh(source, pdf, render_key(theme, aspect)):
        try:
            render(source, pdf, theme, aspect)
        except ImportError as exc:
            sys.stderr.write("md2pdf: missing dependency (%s)\n" % exc)
            return 3
    # The only thing on stdout, so the caller can use it directly.
    print(pdf)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
