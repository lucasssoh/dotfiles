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
# ---- Caching --------------------------------------------------------
# A render costs ~450ms for a document the size of the repo's README, so
# it happens once per (source, stylesheet) state and never again. The
# cache key is the mtime of BOTH the .md and markdown.css: editing the
# stylesheet has to invalidate every rendered document, or the next open
# would show a stale look with no way to tell.
# ============================================================
import hashlib
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
    if aspect >= 1.0:
        w, h = PAGE_LONG_EDGE_MM, PAGE_LONG_EDGE_MM / aspect
    else:
        w, h = PAGE_LONG_EDGE_MM * aspect, PAGE_LONG_EDGE_MM
    return "%.1fmm %.1fmm" % (w, h)


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

    Named from a hash of the absolute path so two READMEs in different
    projects cannot collide, and so the name is stable across renders --
    zathura stores its reading position against this filename, and a
    name that changed per render would lose the position every time the
    document was edited.
    """
    digest = hashlib.sha1(os.path.abspath(source).encode("utf-8")).hexdigest()[:16]
    return os.path.join(cache_dir, digest + ".pdf")


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

    md = markdown.Markdown(extensions=EXTENSIONS, extension_configs=EXTENSION_CONFIGS)
    body = _drop_empty_theads(_absolutise_links(md.convert(text), source))

    with open(CSS_PATH, encoding="utf-8") as fh:
        css = fh.read()
    # The two things markdown.css deliberately leaves open: the page
    # shape, which only the live compositor knows, and the syntax
    # palette, which has to follow the desktop. Both are appended so they
    # win over anything in the stylesheet.
    css += "\n@page { size: %s; }\n" % page_size(aspect)
    css += HtmlFormatter(style=_pygments_style(theme)).get_style_defs(".highlight")

    # The document's own H1 is usually its real title; the filename is
    # the fallback. This lands in the PDF metadata, which is what
    # zathura puts in the window title.
    m = re.search(r"^#\s+(.+)$", text, re.M)
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
