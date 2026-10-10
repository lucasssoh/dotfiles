#!/usr/bin/env bash
# gpg asks for passphrases on the bar's password card: gpg-agent's
# pinentry-program points at Sésame's. A pinentry you set yourself is your
# choice and is left alone.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

gnupg="${GNUPGHOME:-$HOME/.gnupg}"
conf="$gnupg/gpg-agent.conf"
if grep -qE '^[[:space:]]*pinentry-program[[:space:]]' "$conf" 2>/dev/null; then
    ok "gpg keeps the pinentry already set in gpg-agent.conf"
    exit 0
fi
mkdir -p "$gnupg"
chmod 700 "$gnupg"
printf 'pinentry-program %s\n' "$HOME/.local/bin/sesame-pinentry" >> "$conf"
gpgconf --reload gpg-agent 2>/dev/null || true
ok "gpg asks on the password card"
