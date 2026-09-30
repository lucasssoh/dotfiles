#!/usr/bin/env bash
# mdp (Markdown slides) from source: Fedora does not package it.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

if have mdp; then
    info "mdp already installed ($(command -v mdp))"
    exit 0
fi
missing=()
for p in git make gcc ncurses-devel; do rpm -q --whatprovides "$p" >/dev/null 2>&1 || missing+=("$p"); done
[ "${#missing[@]}" -eq 0 ] || as_root dnf install -y "${missing[@]}"
src="$(mktemp -d)"; trap 'rm -rf "$src"' EXIT
git clone --quiet --depth 1 https://github.com/visit1985/mdp.git "$src"
make -C "$src"
as_root make -C "$src" install
ok "mdp installed in /usr/local/bin"
