#!/usr/bin/env bash
# The coucou theme in Firefox: userChrome.css and userContent.css linked into
# the profile's chrome/ (the policy turns on legacy profile stylesheets).
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

have firefox || { info "Firefox not installed: nothing to do"; exit 0; }

# Recent installs keep profiles under XDG, older ones under ~/.mozilla.
ini=""
for dir in "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox" "$HOME/.mozilla/firefox"; do
    [ -f "$dir/profiles.ini" ] && { ini="$dir/profiles.ini"; break; }
done
[ -n "$ini" ] || { warn "no Firefox profile yet: launch Firefox once, then run $0"; exit 0; }
base="$(dirname "$ini")"

# The profile this installation opens ([Install...] Default=), else Default=1.
profile="$(awk -F= -v base="$base" '
    function out(p, rel) { print (rel ? base "/" p : p); exit }
    /^\[/        { sec = $0; rel = 1 }
    /^IsRelative=/ { rel = ($2 == "1") }
    sec ~ /^\[Install/ && /^Default=/ { out($2, 1) }
' "$ini")"
if [ -z "$profile" ]; then
    profile="$(awk -F= -v base="$base" '
        /^\[/ { if (dflt && path != "") exit; sec = $0; path = ""; rel = 1; dflt = 0 }
        sec ~ /^\[Profile/ && /^Path=/       { path = $2 }
        sec ~ /^\[Profile/ && /^IsRelative=/ { rel = ($2 == "1") }
        sec ~ /^\[Profile/ && /^Default=1$/  { dflt = 1 }
        END { if (dflt && path != "") print (rel ? base "/" path : path) }
    ' "$ini")"
fi
[ -n "$profile" ] && [ -d "$profile" ] || { warn "no default Firefox profile found in $ini"; exit 0; }

mkdir -p "$profile/chrome"
for css in userChrome.css userContent.css; do
    src="$REPO/config/firefox/chrome/$css" dest="$profile/chrome/$css"
    [ "$(readlink "$dest" 2>/dev/null)" = "$src" ] && continue
    # A file of the user's own is kept aside, never overwritten.
    if [ -e "$dest" ] || [ -L "$dest" ]; then mv "$dest" "$dest.bak.$(date +%s)"; fi
    ln -s "$src" "$dest"
done
ok "Firefox theme linked into $(basename "$profile")"
pgrep -x firefox >/dev/null 2>&1 && warn "Firefox is running: quit it completely and relaunch for the theme to show"
exit 0
