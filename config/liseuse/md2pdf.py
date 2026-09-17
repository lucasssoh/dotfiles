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
import os
import re
import sys

CSS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "markdown.css")

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


def is_fresh(source: str, pdf: str) -> bool:
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
    return True


def render(source: str, pdf: str) -> None:
    import markdown
    from pygments.formatters import HtmlFormatter
    from weasyprint import HTML

    with open(source, encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    md = markdown.Markdown(extensions=EXTENSIONS, extension_configs=EXTENSION_CONFIGS)
    body = _drop_empty_theads(_absolutise_links(md.convert(text), source))

    with open(CSS_PATH, encoding="utf-8") as fh:
        css = fh.read()
    css += "\n" + HtmlFormatter(style="github-dark").get_style_defs(".highlight")

    # The document's own H1 is usually its real title; the filename is
    # the fallback. This lands in the PDF metadata, which is what
    # zathura puts in the window title.
    m = re.search(r"^#\s+(.+)$", text, re.M)
    title = m.group(1).strip() if m else os.path.basename(source)

    html = (
        "<!doctype html><html><head><meta charset='utf-8'>"
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


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: md2pdf.py <source.md> <cache-dir>\n")
        return 2
    source, cache_dir = argv[1], argv[2]
    pdf = cache_path(source, cache_dir)
    if not is_fresh(source, pdf):
        try:
            render(source, pdf)
        except ImportError as exc:
            sys.stderr.write("md2pdf: missing dependency (%s)\n" % exc)
            return 3
    # The only thing on stdout, so the caller can use it directly.
    print(pdf)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
