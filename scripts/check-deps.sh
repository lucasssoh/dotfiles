#!/usr/bin/env python3
"""check-deps.sh — what this repo runs, versus what it installs.

Why this exists
---------------
Setting up the second machine turned up seven runtime dependencies that
nothing in this repo installed: maven, upower, python3-numpy,
python3-pillow, dbus-tools, pulseaudio-utils, inotify-tools, libnotify.
Every one of them had been installed by hand once on the first machine,
years ago, and was never written down. None of them were visible until a
Fedora "Minimal Install" arrived with none of them present.

They were found one at a time, each by its own symptom, and the symptoms
never named the cause: a bar with no audio module, a wallpaper tint that
never changed, a battery stuck at 0%. Several cost an hour. This script
turns that archaeology into a command.

What it does
------------
Scans every .sh/.py/.qml/.lua in the repo for commands actually INVOKED,
resolves each to its owning RPM, and reports the ones no install script
declares.

Invocation, not mention: an earlier version matched any word that happened
to name a binary in PATH, and drowned in false positives -- "air", "arc",
"red", "count", "rungs" are all real binaries AND ordinary English words
appearing in comments. Hence the patterns below (start of command, after a
pipe/;/&&/$(, `command -v`, a QML `command: [...]` array, `exec_cmd("`,
subprocess list form) and the stripping of comment-only lines first.

Limits, stated plainly
----------------------
  * Commands built at runtime from a variable are invisible here.
  * Non-command dependencies are out of scope by construction: a DBus
    service (upower), a Python import, a QML module, a font. bar-tint.py's
    numpy/Pillow were found by reading its imports, not by this script --
    --imports covers that case, the others still need eyes.
  * It answers "is this package name written in an install script", not
    "does the install actually succeed". A package listed but skipped by
    `--skip-unavailable` reads as declared here.

Usage
-----
  ./scripts/check-deps.sh              # gaps only (exit 1 if any)
  ./scripts/check-deps.sh --all        # every resolved command
  ./scripts/check-deps.sh --imports    # Python imports outside the stdlib
"""

import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "target", "__pycache__", "node_modules", "portfolio-content", "wallpapers"}
SCAN_EXT = (".sh", ".py", ".qml", ".lua", ".conf")

# Scripts that INSTALL things. A package named in any of these counts as
# declared. hardware.sh belongs here even though it installs nothing itself:
# it is the table setup_fedora.sh consumes, so a name in it does get installed.
DECLARING = {"install.sh", "setup_fedora.sh", "install", "install-hardware.sh",
             "dev_setup.sh", "hardware.sh", "install_all.sh"}

# Packages any Fedora system has before this repo is cloned. Listing them as
# dependencies would be noise, not rigour.
BASE = {
    "coreutils", "coreutils-common", "util-linux", "util-linux-core", "bash", "systemd",
    "systemd-udev", "glibc", "glibc-common", "grep", "sed", "gawk", "findutils", "procps-ng",
    "filesystem", "shadow-utils", "ncurses", "diffutils", "which", "less", "gzip", "tar",
    "rpm", "dnf5", "kmod", "iproute", "hostname", "openssh-clients", "sudo", "passwd",
    "cpio", "file", "gettext", "setup", "bzip2", "xz", "zstd", "python3", "python3-libs",
    "dbus-broker", "polkit", "chkconfig", "grubby", "libxcrypt", "systemd-resolved",
}

# Le \b final plus (?![=\w]) : `count=0` est une AFFECTATION de variable, pas
# un appel a /usr/bin/count (qui existe, dans llvm-test). C'etait le dernier
# faux positif shell.
INVOKE_PATTERNS = [
    re.compile(r'(?:^|[|;&]\s*|\$\(\s*|`\s*|\bexec\s+|\bsudo\s+(?:-\w+\s+)*)([a-z][a-z0-9_.-]{2,})\b(?![=\w])', re.M),
    re.compile(r'\bcommand\s+-v\s+([a-z][a-z0-9_.-]{2,})'),
    re.compile(r'\bpgrep\s+(?:-\w+\s+)*([a-z][a-z0-9_.-]{2,})'),
    re.compile(r'command\s*:\s*\[\s*"([a-z][a-z0-9_.-]{2,})"'),
    re.compile(r'exec_cmd\(\s*"([a-z][a-z0-9_.-]{2,})'),
    re.compile(r'(?:run|Popen|check_output|call)\(\s*\[\s*"([a-z][a-z0-9_.-]{2,})"'),
    re.compile(r'"(?:bash|sh)"\s*,\s*"-c"\s*,\s*"([a-z][a-z0-9_.-]{2,})'),
]
COMMENT = re.compile(r'\s*(#|--|//|\*)')
# Les docstrings Python et les blocs /* */ ne sont pas des lignes de
# commentaire ligne-a-ligne, donc COMMENT ne les attrape pas -- et la
# docstring de border-tint.py contient "specular highlight", ou `highlight`
# est un vrai binaire. On les efface avant toute analyse.
DOCSTRING = re.compile(r'(""".*?"""|\'\'\'.*?\'\'\'|/\*.*?\*/)', re.S)


def strip_prose(txt):
    txt = DOCSTRING.sub(" ", txt)
    return "\n".join(l for l in txt.splitlines() if not COMMENT.match(l))

# La bibliotheque standard telle que l'interpreteur la connait, plutot qu'une
# liste tenue a la main -- la premiere version en oubliait `select`, qui est
# stdlib depuis toujours, et le rapport le signalait comme dependance
# manquante. sys.stdlib_module_names existe depuis Python 3.10.
STDLIB = set(sys.stdlib_module_names) | {"__future__"}


def repo_files():
    out = []
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.endswith("-src")]
        for f in files:
            if f.endswith(SCAN_EXT) or f == "install":
                out.append(os.path.join(root, f))
    return out


def path_binaries():
    b = set()
    for d in ("/usr/bin", "/usr/sbin", "/usr/local/bin"):
        if os.path.isdir(d):
            b |= set(os.listdir(d))
    return b


def owning_package(name):
    for d in ("/usr/bin", "/usr/sbin", "/usr/local/bin"):
        p = os.path.join(d, name)
        if os.path.exists(p):
            r = subprocess.run(["rpm", "-qf", "--qf", "%{NAME}", p],
                               capture_output=True, text=True)
            pkg = r.stdout.strip()
            return pkg if pkg and " " not in pkg else None
    return None


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    files = repo_files()
    bins = path_binaries()

    if mode == "--imports":
        found = {}
        for path in files:
            if not path.endswith(".py"):
                continue
            # `from X import Y` requires the `import` keyword on the SAME
            # line, otherwise any prose sentence starting with "from the ..."
            # reads as an import of a module called "the".
            for line in strip_prose(open(path, encoding="utf-8", errors="replace").read()).splitlines():
                m = re.match(r'\s*import\s+([a-zA-Z_]\w*)', line) or \
                    re.match(r'\s*from\s+([a-zA-Z_]\w*)[\w.]*\s+import\s', line)
                if m and m.group(1) not in STDLIB:
                    found.setdefault(m.group(1), set()).add(os.path.relpath(path, REPO))
        for mod, where in sorted(found.items()):
            print(f"  {mod:<16} {', '.join(sorted(where))}")
        print("\nCheck by hand that a module installs each of these "
              "(numpy -> python3-numpy, PIL -> python3-pillow).")
        return 0

    declared = ""
    for path in files:
        if os.path.basename(path) in DECLARING:
            declared += open(path, encoding="utf-8", errors="replace").read()

    used = {}
    for path in files:
        body = strip_prose(open(path, encoding="utf-8", errors="replace").read())
        for pat in INVOKE_PATTERNS:
            for name in pat.findall(body):
                if name in bins:
                    used.setdefault(name, set()).add(os.path.relpath(path, REPO))

    gaps, known = [], []
    for name, where in sorted(used.items()):
        pkg = owning_package(name)
        if not pkg or pkg in BASE:
            continue
        is_declared = (re.search(r"(?<![\w-])" + re.escape(pkg) + r"(?![\w-])", declared)
                       or re.search(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", declared))
        (known if is_declared else gaps).append((name, pkg, sorted(where)))

    if mode == "--all":
        for name, pkg, where in known:
            print(f"  OK   {name:<22} {pkg}")

    if not gaps:
        print(f"No gaps. {len(known)} command(s) outside the base packages, all declared.")
        return 0

    print(f"{len(gaps)} command(s) invoked but declared nowhere:\n")
    for name, pkg, where in gaps:
        print(f"  {name:<22} package: {pkg:<22} <- {', '.join(where[:3])}")
    print("\nAdd the package to the PKGS list in config/hyprland/install.sh, "
          "or to setup_fedora.sh, depending on which layer it belongs to.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
