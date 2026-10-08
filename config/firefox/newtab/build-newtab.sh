#!/usr/bin/env bash
set -Eeuo pipefail

# build-newtab.sh — regenerate the coucou new-tab page from real browsing.
#
# The page (index.html) is a template with a <!--MOSTUSED--> placeholder. This
# script fills that placeholder with the sites this machine is actually used
# for, sorted by Firefox's own frecency scoring, minus the five pinned tiles,
# and writes the result where the new-tab page is served from.
#
# Run it at install time (install.sh does), or by hand whenever the list
# should be fresher.

# Pinned tiles shown as icons on top; their hosts are excluded from the
# most-used list so nothing appears twice.
PINNED_HOSTS="github.com|youtube.com|chatgpt.com|gemini.google.com|claude.ai"

# The built page lives outside the repository: it contains machine-specific
# browsing data and must not be versioned.
OUT_DIR="${NEWTAB_OUT_DIR:-$HOME/.local/share/firefox/newtab}"
TEMPLATE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/index.html"

# Same profile resolution as config/firefox/install.sh: the [Install...]
# section is authoritative, Default=1 is the fallback.
FIREFOX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
PROFILES_INI="$FIREFOX_DIR/profiles.ini"

FIREFOX_PROFILE="$(
    awk -F= -v base="$FIREFOX_DIR" '
        function print_profile() {
            if (install_default == "")
                return
            if (relative) print base "/" install_default
            else print install_default
        }

        /^\[Install/ {
            if (in_install) print_profile()
            in_install=1
            install_default=""
            relative=1
            next
        }

        /^\[/ {
            if (in_install) print_profile()
            in_install=0
        }

        in_install && /^Default=/   { install_default = $2 }
        in_install && /^IsRelative=/ { relative = ($2 == "1") }

        END { if (in_install) print_profile() }
    ' "$PROFILES_INI" 2>/dev/null | head -n1
)"

if [[ -z "$FIREFOX_PROFILE" ]]; then
    FIREFOX_PROFILE="$(
        awk -F= -v base="$FIREFOX_DIR" '
            /^\[Profile/ { in_profile=1; path=""; relative=1; default_profile=0; next }
            /^\[/ {
                if (in_profile && default_profile && path != "") {
                    if (relative) print base "/" path
                    else print path
                    exit
                }
                in_profile=0
            }
            in_profile && /^IsRelative=/ { relative = ($2 == "1") }
            in_profile && /^Path=/      { path = $2 }
            in_profile && /^Default=1$/ { default_profile = 1 }

            END {
                if (in_profile && default_profile && path != "") {
                    if (relative) print base "/" path
                    else print path
                }
            }
        ' "$PROFILES_INI" 2>/dev/null
    )"
fi

rows=""
if [[ -n "$FIREFOX_PROFILE" && -f "$FIREFOX_PROFILE/places.sqlite" ]] && \
   command -v sqlite3 >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    # A consistent snapshot beats a hot copy: .backup goes through SQLite's
    # backup API and works even while Firefox is running. When the database is
    # mid-writing it can still refuse, in which case fall back to copying the
    # WAL database files whole — a slightly older snapshot, but readable.
    if ! sqlite3 "$FIREFOX_PROFILE/places.sqlite" ".backup $tmp/places.sqlite" >/dev/null 2>&1; then
        cp -f "$FIREFOX_PROFILE/places.sqlite" "$tmp/places.sqlite"
        cp -f "$FIREFOX_PROFILE/places.sqlite-wal" "$tmp/places.sqlite-wal" 2>/dev/null || true
        cp -f "$FIREFOX_PROFILE/places.sqlite-shm" "$tmp/places.sqlite-shm" 2>/dev/null || true
    fi
    if [[ -s "$tmp/places.sqlite" ]]; then
        rows="$(
            sqlite3 -separator $'\t' "$tmp/places.sqlite" "
                SELECT COALESCE(NULLIF(title, ''), ''), url
                FROM moz_places
                WHERE hidden = 0 AND (url LIKE 'https://%' OR url LIKE 'http://%')
                ORDER BY frecency DESC, visit_count DESC
                LIMIT 60;
            " | awk -F'\t' -v pinned="$PINNED_HOSTS" '
                function escape(s) {
                    gsub(/&/, "\\&amp;", s)
                    gsub(/</, "\\&lt;", s)
                    gsub(/>/, "\\&gt;", s)
                    gsub(/"/, "\\&quot;", s)
                    return s
                }
                function host_of(u) {
                    sub(/^[a-z][a-z0-9+.-]*:\/\//, "", u)
                    sub(/\/.*/, "", u)
                    u = tolower(u)
                    sub(/^www\./, "", u)
                    sub(/:.*/, "", u)
                    return u
                }
                {
                    title = $1
                    url = $2
                    host = host_of(url)
                    if (host !~ "^[a-z0-9.-]+$") next
                    if (host == "localhost") next
                    if (host ~ pinned) next
                    if (seen[host]++) next

                    if (title == "") title = host
                    if (length(title) > 44) title = substr(title, 1, 44) "…"

                    n++
                    print "        <a href=\"" escape(url) "\">"
                    print "          <img src=\"https://www.google.com/s2/favicons?domain=" host "&amp;sz=32\" alt=\"\">"
                    print "          <span class=\"nm\">" escape(title) "</span>"
                    print "          <span class=\"url\">" escape(host) "</span>"
                    print "        </a>"
                }
            '
        )"
    fi
    rm -rf "$tmp"
fi

mkdir -p "$OUT_DIR"

# Substitute the markers with the freshly generated rows.
if [[ -z "$rows" ]]; then
    rows="      <div class=\"none\">No most-used sites yet — visit a few, then re-run the install.</div>"
fi

awk -v rows="$rows" '
    /<!--MOSTUSED-->/ { print rows; next }
    { print }
' "$TEMPLATE" > "$OUT_DIR/index.html"

printf '%s\n' "new-tab page written: $OUT_DIR/index.html"