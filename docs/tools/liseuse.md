# Liseuse

A reading library, on `Super + F`.

## Open a book

`Super + F` brings back the book open on this workspace. With none, it opens the library, the last book first.

Type to search titles, file names and folders: `md` and `dotfiles keybind` both find something. `Enter` opens the book at the last page read.

Liseuse lists the books in `~/Livres` and in the folders of [`sources.conf`](../../config/liseuse/sources.conf).

From a terminal:

```bash
liseuse open FILE --page 12
liseuse open FILE --section "Title"
```

## Read

| Key | Does |
|---|---|
| `Space`, `Return` | Forward: the next slide, or one screen of a book |
| `Shift + Space`, `Shift + Return` | Back |
| `Super + Shift + F` | Fullscreen |
| `F1` | Every key |

Light and dark follow the desktop. While a book is visible, notifications keep quiet and the screen stays on.

## Formats

PDF, EPUB, MOBI, AZW3, FB2, CBZ/CBR, DjVu, XPS, Markdown and PlantUML (`.puml`).

Markdown is rendered as on GitHub, with syntax highlighting, maths (`$…$`, `$$…$$`), PlantUML blocks and links between documents.

## Convert an office document

To a PDF, saved next to the original:

```bash
liseuse convert [FILE…]    # with no argument, pick from the documents it found
```

This needs LibreOffice: `sudo dnf install libreoffice-writer libreoffice-impress libreoffice-calc`.

## Settings

| To change | Edit |
|---|---|
| The folders to look in, besides `~/Livres` | [`sources.conf`](../../config/liseuse/sources.conf), one path per line |
| The reader's keys and colours | [`zathurarc`](../../config/liseuse/zathurarc) |
| How Markdown pages look | [`markdown.css`](../../config/liseuse/markdown.css) |
