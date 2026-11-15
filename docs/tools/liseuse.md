# Liseuse

A reading library on `Super + F`. If a book is already open on the current workspace, it brings it back. Otherwise it opens the library: where you left off first; type to search titles and file names, and open one where you left it. Without the bar, the list comes up in fuzzel. Press `F1` inside a book for the reading manual. `liseuse open FILE --page N` (or `--section TITLE`) opens a file at a page or a heading.

| | |
|---|---|
| Installs | zathura with the mupdf, cb and djvu plugins, mupdf; the Markdown renderer (python-markdown, Pygments, WeasyPrint, MathJax); `plantuml` |
| Links | `zathurarc`, `sources.conf`, and the `liseuse` launcher into `~/.local/bin` |
| Creates | `~/Livres`, and the file associations for documents |

**Formats**: PDF, EPUB, MOBI, AZW3, FB2, CBZ/CBR, DjVu, XPS, Markdown and PlantUML (`.puml`). Markdown is rendered the way GitHub does it, with syntax highlighting, maths (`$…$`, `$$…$$`), PlantUML blocks, and links between documents that work.

| To change | Edit |
|---|---|
| Folders to look in (besides `~/Livres`) | [`sources.conf`](../../config/liseuse/sources.conf), one path per line |
| Reader keys and colours | [`zathurarc`](../../config/liseuse/zathurarc) |
| How Markdown pages look | [`markdown.css`](../../config/liseuse/markdown.css) |

In the list, the book you're currently reading comes first. Search looks at the full path as well as the title, so `md` or `dotfiles keybind` both work. Light and dark follow the desktop setting. `Space` and `Return` move forward, and `Shift` goes back: on slides they turn the page and fit the next one whole, in a book they scroll exactly one screen, so nothing is skipped. `F1` lists every key.

A book opens as a normal window. Use `Super + Shift + F` for fullscreen. While you're reading, notifications are silenced, and the screen stays on as long as a book is visible (see [Idle](../session/hyprland.md#idle)).

Office documents can be converted to a PDF, saved next to the original:

```bash
liseuse convert [FILE…]    # with no argument, pick from the documents it found
```

This needs LibreOffice, which isn't installed with Liseuse (`libreoffice-writer libreoffice-impress libreoffice-calc`).

Rendered Markdown is cached in `~/.cache/liseuse/md/`.
