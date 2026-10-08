#!/usr/bin/env bash
set -Eeuo pipefail

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/link.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/lib/pkg.sh"

BLUE="\e[34m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }

pkg_ensure firefox "$(pkg_pick sqlite sqlite sqlite3)"

# Resolve the repository root from this script instead of relying on the
# current working directory. This keeps the installer working whether it is
# invoked from the repository root or directly via its absolute/relative path.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Firefox validates policies.json against its own schema and silently drops
# the offending policy on failure, with no error anywhere: an invalid Status
# value in Preferences has no symptom except a theme that never loads. Check
# the file here, where a failure can still be reported.
POLICIES="$DOTFILES_DIR/config/firefox/policies.json"
if command -v jq >/dev/null 2>&1; then
    if ! jq -e . "$POLICIES" >/dev/null; then
        warn "policies.json is not valid JSON: $POLICIES"
        exit 1
    fi

    # Status must be one of default | locked | user | clear, or Firefox
    # rejects every entry in Preferences, valid ones included.
    bad_status="$(
        jq -r '
            .policies.Preferences // {}
            | to_entries[]
            | select(.value | type == "object")
            | select(.value.Status != null)
            | select(.value.Status | IN("default", "locked", "user", "clear") | not)
            | "\(.key)=\(.value.Status)"
        ' "$POLICIES"
    )"
    if [ -n "$bad_status" ]; then
        warn "invalid Preferences Status — Firefox would drop the whole policy:"
        warn "  $bad_status"
        exit 1
    fi
else
    warn "jq not available; policies.json not validated."
fi

# Firefox policies are machine-wide and therefore live in /etc/firefox.
# Keep the repository file as the source of truth and let the system path
# point to it, so policy changes are immediately reflected without copying
# files around.
sudo_maybe mkdir -p /etc/firefox/policies
sudo_maybe ln -sf \
    "$DOTFILES_DIR/config/firefox/policies.json" \
    /etc/firefox/policies/policies.json

# MOZ_ENABLE_WAYLAND is managed through environment.d rather than being
# exported from this script, because the setting must survive the install
# process and apply to future Firefox launches.
mkdir -p ~/.config/environment.d
safe_link \
    "$DOTFILES_DIR/config/firefox/firefox.conf" \
    ~/.config/environment.d/firefox.conf

# Firefox stores its profiles under the XDG configuration directory on this
# system. Respect XDG_CONFIG_HOME when explicitly set, otherwise fall back
# to ~/.config.
FIREFOX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
PROFILES_INI="$FIREFOX_DIR/profiles.ini"

if [[ -f "$PROFILES_INI" ]]; then
    # Firefox can have several profiles and several Firefox installations.
    # The [Install...] section identifies which profile belongs to a specific
    # Firefox installation. Prefer that association over Default=1, because
    # Default=1 only marks a profile in the general profile list.
    #
    # The value of Default= in [Install...] is a profile path. With
    # IsRelative=1, it is relative to FIREFOX_DIR; absolute paths are preserved
    # as-is.
    FIREFOX_PROFILE="$(
        awk -F= -v base="$FIREFOX_DIR" '
            function print_profile() {
                if (install_default == "")
                    return

                if (relative)
                    print base "/" install_default
                else
                    print install_default
            }

            /^\[Install/ {
                if (in_install)
                    print_profile()

                in_install=1
                install_default=""
                relative=1
                next
            }

            /^\[/ {
                if (in_install)
                    print_profile()

                in_install=0
            }

            in_install && /^Default=/ {
                install_default=$2
            }

            in_install && /^IsRelative=/ {
                relative=($2 == "1")
            }

            END {
                if (in_install)
                    print_profile()
            }
        ' "$PROFILES_INI" | head -n1
    )"

    # Fall back to the profile explicitly marked Default=1 when no
    # installation-specific default could be determined.
    if [[ -z "$FIREFOX_PROFILE" ]]; then
        FIREFOX_PROFILE="$(
            awk -F= -v base="$FIREFOX_DIR" '
                /^\[Profile/ {
                    in_profile=1
                    path=""
                    relative=1
                    default_profile=0
                    next
                }

                /^\[/ {
                    if (in_profile && default_profile && path != "") {
                        if (relative)
                            print base "/" path
                        else
                            print path
                        exit
                    }
                    in_profile=0
                }

                in_profile && /^IsRelative=/ {
                    relative=($2 == "1")
                }

                in_profile && /^Path=/ {
                    path=$2
                }

                in_profile && /^Default=1$/ {
                    default_profile=1
                }

                END {
                    if (in_profile && default_profile && path != "") {
                        if (relative)
                            print base "/" path
                        else
                            print path
                    }
                }
            ' "$PROFILES_INI"
        )"
    fi

    if [[ -n "$FIREFOX_PROFILE" && -d "$FIREFOX_PROFILE" ]]; then
        # userChrome.css is loaded from the chrome/ directory inside the
        # Firefox profile. Keep the stylesheet in the coucou-shell repository
        # and deploy it through safe_link(), which makes the operation
        # idempotent, records it in the link ledger, and backs up a pre-existing
        # real file instead of deleting it.
        FIREFOX_CHROME="$FIREFOX_PROFILE/chrome"
        mkdir -p "$FIREFOX_CHROME"

safe_link \
            "$DOTFILES_DIR/config/firefox/chrome/userChrome.css" \
            "$FIREFOX_PROFILE/chrome/userChrome.css"

        # The new-tab page (coucou's own) is served through New Tab Override,
        # an add-on installed by policy. The add-on reads the page to open from
        # managed storage: a native manifest in the profile's managed-storage
        # directory, written fresh on every install so the file:// URL it
        # points at always matches where this machine's page is built.
        NEWTAB_OUT="${NEWTAB_OUT_DIR:-$HOME/.local/share/firefox/newtab}"
        NEWTAB_OUT_DIR="$NEWTAB_OUT" \
            "$DOTFILES_DIR/config/firefox/newtab/build-newtab.sh"

        mkdir -p "$FIREFOX_PROFILE/managed-storage"
        cat > "$FIREFOX_PROFILE/managed-storage/newtaboverride@agenedia.com.json" <<EOF
{
  "name": "newtaboverride@agenedia.com",
  "description": "coucou-shell: open the local new-tab page",
  "type": "storage",
  "data": {
    "type": "custom_url",
    "url": "file://$NEWTAB_OUT/index.html",
    "focus_website": true
  }
}
EOF
    else
        info "Firefox default profile not found; userChrome.css and the new-tab page are skipped."
    fi
else
    # Firefox may not have created its profile metadata yet. Do not create a
    # fake profile here; simply leave userChrome.css for a later installer run.
    info "Firefox profiles.ini not found; userChrome.css skipped."
fi

# Policy entries and userChrome.css are both restart-required: a running
# instance keeps the old state until it is fully quit, which is the one thing
# a fresh install cannot do by itself.
if pgrep -x firefox >/dev/null 2>&1; then
    warn "Firefox is running: quit it completely and relaunch for the policy and theme to take effect."
fi

ok "Firefox configured."
