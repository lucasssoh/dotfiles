#!/usr/bin/env python3
"""ccslide — decks de présentation mdp (jumeau de ccnote).

Même moteur de workspaces que ccnote, mais le fichier produit est un *deck*
mdp : en-tête de métadonnées en commentaire HTML, slides séparées par des
règles horizontales, et surtout un contenu qui tient dans le terminal.

Le dernier point est la raison d'être de ce script. mdp REFUSE de démarrer
si une seule slide dépasse la taille du terminal ; on ne le découvre donc
qu'au moment de présenter. `ccslide --check` mesure ça à la frappe.
"""

import json
import os
import re
import shutil
import sys
import textwrap
from datetime import datetime

CONFIG_DIR = os.path.expanduser("~/.config/ccslide")
CONFIG_FILE = os.path.join(CONFIG_DIR, "workspaces.json")

DECK_NAME = "deck.md"       # tes notes
IMPORT_NAME = "prof.md"     # le support du prof, une fois importé

# ============================================================
# Constantes mesurées sur mdp 1.0.19 (pas devinées)
# ============================================================
# Hauteur : mdp compte TOUTES les lignes brutes de la slide, lignes vides
# comprises, et réclame 3 lignes de plus pour son bandeau de titre et sa
# barre de pied.
#   30 lignes             -> "Need at least 33"
#   30 lignes + 1 vide    -> "Need at least 34"
#   30 lignes + 6 vides   -> "Need at least 39"
HEIGHT_OVERHEAD = 3

# Largeur : mdp ne wrappe pas. Strictement au-delà de la largeur du
# terminal il refuse de démarrer ("Need at least N columns") ; pile à la
# largeur il ne dit rien, mais la mise en page part en morceaux. D'où deux
# seuils distincts plutôt qu'une marge arbitraire.
#   60 colonnes dans un terminal de 40 -> "Need at least 60 columns"
#   40 colonnes dans un terminal de 40 -> pas d'erreur, rendu cassé

# Un cran d'indentation de liste rendu par mdp : ' +- ' ou ' |  '
# (cf. MDP_LIST_OPEN* / MDP_LIST_HEAD* dans man mdp).
LIST_INDENT = 4

# Taille de terminal supposée quand on ne peut pas la mesurer.
DEFAULT_ROWS, DEFAULT_COLS = 24, 80


# ============================================================
# Workspaces (calqué sur ccnote)
# ============================================================
def load_config():
    if not os.path.exists(CONFIG_FILE):
        default_config = {"cours": os.path.expanduser("~/cours")}
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(default_config, f, indent=4, ensure_ascii=False)
        return default_config

    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_config(config):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)


def default_workspace(config):
    """Le workspace utilisé quand le premier argument n'en nomme aucun."""
    if "cours" in config:
        return "cours"
    return next(iter(config), None)


def get_subdirs(base_path):
    if not os.path.isdir(base_path):
        return []
    return sorted(
        d for d in os.listdir(base_path)
        if os.path.isdir(os.path.join(base_path, d)) and not d.startswith(".")
    )


# ============================================================
# Analyse d'un deck
# ============================================================
def is_separator(line):
    """Une règle horizontale mdp : au moins 3 fois - ou *, espaces tolérés."""
    stripped = line.strip()
    for char in ("-", "*"):
        if stripped.count(char) >= 3 and set(stripped) <= {char, " "}:
            return True
    return False


def meta_end(lines):
    """Index de la première ligne qui suit l'en-tête de métadonnées.

    mdp accepte un bloc <!-- ... --> ou des lignes %title:/%author:/%date:,
    uniquement en tête de fichier.
    """
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].strip().startswith("<!--"):
        for j in range(i, len(lines)):
            if "-->" in lines[j]:
                return j + 1
        return len(lines)
    while i < len(lines) and lines[i].strip().startswith("%"):
        i += 1
    return i if i else 0


def split_slides(lines):
    """Découpe en slides. Retourne [(debut, fin)] en index 0, fin exclue.

    Une règle horizontale ne sépare que si elle est précédée d'une ligne
    complètement vide (cf. man mdp) — sinon elle est rendue telle quelle,
    et deux slides fusionnent en silence.
    """
    start = meta_end(lines)
    slides, current = [], start
    for i in range(start, len(lines)):
        if is_separator(lines[i]) and i > 0 and not lines[i - 1].strip():
            slides.append((current, i))
            current = i + 1
    slides.append((current, len(lines)))
    return slides


def rendered_width(line):
    """Largeur qu'occupera la ligne une fois rendue par mdp."""
    stripped = line.strip()

    # Bloc de code : la clôture ``` disparaît, le contenu reste tel quel.
    if stripped.startswith("```"):
        return 0

    # Titre : mdp retire les # et l'espace qui suit.
    heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
    if heading:
        return len(heading.group(2))

    # Élément de liste : chaque niveau devient ' +- ' (4 colonnes).
    item = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", line)
    if item:
        depth = len(item.group(1)) // 2 + 1
        return LIST_INDENT * depth + len(item.group(3))

    return len(line.rstrip())


def lint(path, rows, cols):
    """Retourne (problèmes, stats). Un problème = dict prêt pour nvim."""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    problems = []
    max_height = rows - HEIGHT_OVERHEAD
    max_width = cols

    def add(line_no, severity, code, message):
        problems.append({
            "line": line_no,          # 1-indexé, comme nvim
            "severity": severity,     # "error" | "warn"
            "code": code,
            "message": message,
        })

    if meta_end(lines) == 0:
        add(1, "warn", "no-meta",
            "Pas d'en-tête <!-- title: --> : mdp affichera un bandeau vide")

    slides = split_slides(lines)
    in_code = False

    if len(slides) == 1 and (slides[0][1] - slides[0][0]) > max_height:
        add(1, "error", "no-separator",
            f"Aucun séparateur : le fichier entier ({slides[0][1] - slides[0][0]} "
            f"lignes) forme une seule slide. `ccslide --split` le découpe.")

    for index, (start, end) in enumerate(slides, start=1):
        height = end - start
        if height > max_height and len(slides) > 1:
            add(start + 1, "error", "slide-too-tall",
                f"Slide {index} : {height} lignes pour {max_height} "
                f"disponibles — mdp refusera de démarrer")

        # Les lignes vides en fin de slide comptent dans la hauteur.
        trailing = 0
        while end - 1 - trailing >= start and not lines[end - 1 - trailing].strip():
            trailing += 1
        if trailing > 1 and height > max_height - 3:
            add(end - trailing + 1, "warn", "trailing-blank",
                f"Slide {index} : {trailing} lignes vides en fin de slide, "
                f"elles comptent dans la hauteur")

    for i, line in enumerate(lines, start=1):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue

        width = rendered_width(line)
        if width > max_width:
            add(i, "error", "line-too-wide",
                f"{width} colonnes pour {max_width} disponibles — "
                f"mdp refusera de démarrer")
        elif width == max_width and width > 0:
            add(i, "warn", "line-at-limit",
                "Ligne pile à la largeur du terminal : mdp ne dira rien "
                "mais la mise en page se cassera")

        if in_code:
            continue

        if re.match(r"^\s*\|.*\|\s*$", line):
            add(i, "warn", "table",
                "mdp ne gère pas les tableaux, la ligne sortira brute "
                "(| a | b |)")

        if re.search(r"!\[[^\]]*\]\([^)]+\)", line):
            add(i, "warn", "image",
                "mdp n'affiche pas les images, elle deviendra une note "
                "de bas de slide")

        if (is_separator(line) and i >= 2 and lines[i - 2].strip()
                and not in_code):
            add(i, "warn", "orphan-rule",
                "Règle horizontale sans ligne vide avant : elle ne sépare "
                "rien et sera rendue telle quelle")

    stats = {
        "slides": len(slides),
        "rows": rows,
        "cols": cols,
        "max_height": max_height,
        "max_width": max_width,
    }
    return problems, stats


# ============================================================
# Découpage automatique
# ============================================================
def wrap_body(lines, max_width):
    """Reformate les lignes trop larges pour que mdp accepte de démarrer.

    Laisse intacts : les blocs de code (ce sont souvent des textes à
    copier-coller, les recouper changerait ce qu'on colle), les titres, les
    tableaux et les séparateurs.
    """
    out, in_code = [], False

    for line in lines:
        if line.strip().startswith("```"):
            in_code = not in_code
            out.append(line)
            continue

        if in_code or is_separator(line) or rendered_width(line) <= max_width:
            out.append(line)
            continue

        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("|"):
            out.append(line)
            continue

        item = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", line)
        if item:
            lead, marker, text = item.groups()
            depth = len(lead) // 2 + 1
            # mdp rend chaque niveau sur 4 colonnes (' +- ').
            room = max_width - LIST_INDENT * depth
            cont = lead + " " * (len(marker) + 1)
        else:
            text = stripped
            room = max_width
            cont = re.match(r"^(\s*)", line).group(1)

        pieces = textwrap.wrap(
            text, width=max(room, 20),
            break_long_words=False, break_on_hyphens=False) or [text]

        if item:
            out.append(f"{lead}{marker} {pieces[0]}")
            out.extend(cont + piece for piece in pieces[1:])
        else:
            out.append(cont + pieces[0])
            out.extend(cont + piece for piece in pieces[1:])

    return out


def split_body(body, max_height):
    """Découpe un corps de markdown en blocs qui tiennent dans max_height.

    Deux passes : d'abord aux titres (la structure voulue par l'auteur),
    puis, pour les blocs encore trop hauts, en reculant jusqu'à la dernière
    ligne vide — on coupe donc entre deux paragraphes, pas au milieu d'une
    phrase.
    """
    def flush(acc, out):
        while acc and not acc[0].strip():
            acc.pop(0)
        while acc and not acc[-1].strip():
            acc.pop()
        if acc:
            out.append(list(acc))

    # Passe 1 : aux titres et aux séparateurs déjà présents.
    blocks, current = [], []
    for line in body:
        if is_separator(line):
            flush(current, blocks)
            current = []
        elif re.match(r"^#{1,3}\s+", line) and any(l.strip() for l in current):
            flush(current, blocks)
            current = [line]
        else:
            current.append(line)
    flush(current, blocks)

    # Passe 2 : les blocs encore trop hauts.
    result = []
    for block in blocks:
        if len(block) <= max_height:
            result.append(block)
            continue

        title = block[0] if re.match(r"^#{1,6}\s+", block[0]) else None
        rest = block[1:] if title else block
        # Un titre de rappel et sa ligne vide coûtent 2 lignes par morceau.
        room = max_height - (2 if title else 0)

        pieces, chunk = [], []
        for line in rest:
            chunk.append(line)
            if len(chunk) >= room:
                # Reculer jusqu'à la dernière respiration, sans remonter
                # au-delà de la moitié du morceau (sinon on émiette).
                cut = len(chunk)
                for k in range(len(chunk) - 1, len(chunk) // 2, -1):
                    if not chunk[k].strip():
                        cut = k
                        break
                pieces.append(chunk[:cut])
                chunk = chunk[cut:]
        if any(l.strip() for l in chunk):
            pieces.append(chunk)

        for i, piece in enumerate(pieces, start=1):
            while piece and not piece[0].strip():
                piece.pop(0)
            while piece and not piece[-1].strip():
                piece.pop()
            if not piece:
                continue
            if title:
                head = f"{title} ({i})" if len(pieces) > 1 else title
                result.append([head, ""] + piece)
            else:
                result.append(piece)

    return result


def split_deck(path, rows, cols, title=None):
    """Réécrit le fichier en slides qui tiennent. Sauvegarde en .bak."""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    end = meta_end(lines)
    header = lines[:end]
    body = lines[end:]
    # -2 : dans le fichier assemblé, chaque slide est encadrée d'une ligne
    # vide avant et après son séparateur, et mdp les compte.
    max_height = rows - HEIGHT_OVERHEAD - 2

    body = wrap_body(body, cols)
    blocks = split_body(body, max_height)
    if not blocks:
        print("[Erreur] Rien à découper.", file=sys.stderr)
        return 1

    if not header:
        header = [
            "<!--",
            f"title: {title or os.path.basename(os.path.dirname(path)) or 'Deck'}",
            f"footer: {datetime.now().strftime('%d/%m/%Y')}",
            "-->",
        ]

    out = list(header) + [""]
    for i, block in enumerate(blocks):
        if i:
            out += ["", "---", ""]
        out += block

    shutil.copyfile(path, path + ".bak")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    print(f"{len(blocks)} slides pour {rows}x{cols} — sauvegarde : "
          f"{os.path.basename(path)}.bak")
    return 0


# ============================================================
# Création
# ============================================================
TEMPLATE = """<!--
title: {title}
footer: {course}
footer: {date}
-->

# {title}

{course} — {date}

---

## \
"""


def create_deck(target_dir, deck_title, course):
    os.makedirs(target_dir, exist_ok=True)
    deck_file = os.path.join(target_dir, DECK_NAME)

    if not os.path.exists(deck_file):
        content = TEMPLATE.format(
            title=deck_title,
            course=course,
            date=datetime.now().strftime("%d/%m/%Y"),
        )
        with open(deck_file, "w", encoding="utf-8") as f:
            f.write(content + "\n")
        print(f"Nouveau deck : {deck_title}")

    return deck_file


def find_decks(config):
    """Tous les decks de tous les workspaces, pour le sélecteur fzf."""
    found = []
    for base in config.values():
        base = os.path.expanduser(base)
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            if DECK_NAME in files:
                full = os.path.join(root, DECK_NAME)
                found.append((os.path.relpath(root, base), full))
    return sorted(found)


# ============================================================
# Complétion zsh
# ============================================================
def print_completion(config, args):
    if args and args[0] in ("--new-workspace", "--check"):
        return

    if args and args[0] in config:
        base = os.path.expanduser(config[args[0]])
        path = os.path.join(base, *args[1:-1]) if len(args) > 2 else base
        print(" ".join(get_subdirs(path)))
        return

    base = config.get(default_workspace(config) or "", "")
    suggestions = list(config.keys()) + get_subdirs(os.path.expanduser(base))
    print(" ".join(dict.fromkeys(suggestions)))


# ============================================================
# Point d'entrée
# ============================================================
def terminal_size():
    try:
        size = shutil.get_terminal_size()
        if size.lines > 1 and size.columns > 1:
            return size.lines, size.columns
    except OSError:
        pass
    return DEFAULT_ROWS, DEFAULT_COLS


def cmd_check(args):
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]

    rows, cols = terminal_size()
    for flag, setter in (("--rows", "rows"), ("--cols", "cols")):
        if flag in args:
            i = args.index(flag)
            value = int(args[i + 1])
            rows, cols = (value, cols) if setter == "rows" else (rows, value)
            del args[i:i + 2]

    if not args:
        print("[Erreur] Usage: ccslide --check <fichier.md>", file=sys.stderr)
        return 2

    path = os.path.expanduser(args[0])
    if not os.path.isfile(path):
        print(f"[Erreur] Fichier introuvable : {path}", file=sys.stderr)
        return 2

    problems, stats = lint(path, rows, cols)

    if as_json:
        json.dump({"problems": problems, "stats": stats}, sys.stdout,
                  ensure_ascii=False)
        print()
        return 0

    if not problems:
        print(f"OK — {stats['slides']} slides tiennent dans "
              f"{stats['rows']}x{stats['cols']}")
        return 0

    for p in problems:
        mark = "ERREUR" if p["severity"] == "error" else " warn "
        print(f"{path}:{p['line']}: [{mark}] {p['message']}")

    errors = sum(1 for p in problems if p["severity"] == "error")
    return 1 if errors else 0


def main():
    config = load_config()
    args = sys.argv[1:]

    if args and args[0] == "--complete":
        print_completion(config, args[1:])
        return 0

    if args and args[0] == "--check":
        return cmd_check(args[1:])

    if args and args[0] == "--split":
        rest = args[1:]
        rows, cols = terminal_size()
        for flag in ("--rows", "--cols"):
            if flag in rest:
                i = rest.index(flag)
                value = int(rest[i + 1])
                rows, cols = (value, cols) if flag == "--rows" else (rows, value)
                del rest[i:i + 2]
        if not rest:
            print("[Erreur] Usage: ccslide --split <fichier.md>", file=sys.stderr)
            return 2
        target = os.path.expanduser(rest[0])
        if not os.path.isfile(target):
            print(f"[Erreur] Fichier introuvable : {target}", file=sys.stderr)
            return 2
        return split_deck(target, rows, cols)

    if args and args[0] == "--list":
        for rel, full in find_decks(config):
            print(f"{rel}\t{full}")
        return 0

    if args and args[0] == "--new-workspace":
        if len(args) < 3:
            print("[Erreur] Usage: ccslide --new-workspace <nom> <chemin>",
                  file=sys.stderr)
            return 1
        name, path = args[1], os.path.expanduser(args[2])
        config[name] = path
        save_config(config)
        os.makedirs(path, exist_ok=True)
        print(f"Workspace enregistré : '{name}' -> {path}")
        return 0

    # --- Résolution workspace / chemin du deck ---
    if args and args[0] in config:
        workspace_name, segments = args[0], args[1:]
    else:
        workspace_name, segments = default_workspace(config), args

    if not workspace_name:
        print("[Erreur] Aucun workspace configuré.", file=sys.stderr)
        return 1

    base_path = os.path.expanduser(config[workspace_name])

    # `ccslide <ue> today` -> séance datée du jour, sans avoir à la nommer.
    if segments and segments[-1] == "today":
        segments = list(segments[:-1]) + [datetime.now().strftime("%Y-%m-%d")]

    if not segments:
        # Pas de cible : le shell prendra le relais avec fzf.
        print(f"__PICK__:{workspace_name}")
        return 0

    target_dir = os.path.join(base_path, *segments)
    course = segments[0] if len(segments) > 1 else workspace_name
    deck_file = create_deck(target_dir, segments[-1], course)

    print(f"__CWD__:{target_dir}")
    print(f"__FILE__:{deck_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
