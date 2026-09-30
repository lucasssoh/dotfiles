#!/usr/bin/env bash
# Brave launched with config/brave/brave-flags.conf, through a user .desktop override.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

have brave-browser || { info "Brave not installed: nothing to do"; exit 0; }
flags="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$REPO/config/brave/brave-flags.conf" | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/ $//')"
[ -n "$flags" ] || { warn "no flags in brave-flags.conf"; exit 0; }

# A renamed Chromium feature is silently ignored: check each name exists.
bin="$(readlink -f "$(command -v brave-browser)")"
[ "$(od -An -c -N4 "$bin" | tr -d ' ')" = "177ELF" ] || { [ -x "$(dirname "$bin")/brave" ] && bin="$(dirname "$bin")/brave"; }
if have strings; then
    for tok in $flags; do
        case "$tok" in --enable-features=*) ;; *) continue ;; esac
        IFS=',' read -ra feats <<< "${tok#--enable-features=}"
        for f in "${feats[@]}"; do
            strings -- "$bin" | grep -Fx -e "$f" -e "k$f" >/dev/null || warn "feature '$f' not found in $bin (renamed?)"
        done
    done
fi

src="$(ls /usr/share/applications/brave-browser*.desktop 2>/dev/null | head -n1)"
[ -n "$src" ] || { warn "no system brave .desktop found"; exit 0; }
dest="$HOME/.local/share/applications/$(basename "$src")"
mkdir -p "$(dirname "$dest")"
awk -v flags="$flags" '
    /^Exec=/ { line = substr($0, 6); n = index(line, " ")
               if (n == 0) print "Exec=" line " " flags
               else        print "Exec=" substr(line, 1, n - 1) " " flags substr(line, n)
               next }
    { print }' "$src" > "$dest"
update-desktop-database "$(dirname "$dest")" 2>/dev/null || true
ok "Brave flags applied ($(basename "$dest"))"
