#!/usr/bin/env bash
# zsh plugins, and zsh as the login shell.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

plugins="$HOME/.zsh"
mkdir -p "$plugins"
for repo in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
    dest="$plugins/${repo#*/}"
    [ -d "$dest" ] || git clone --quiet "https://github.com/$repo" "$dest"
done

zsh_path="$(command -v zsh)"
current="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$current" != "$zsh_path" ]; then
    # usermod rather than chsh: chsh asks for the password, which a hook
    # cannot answer.
    as_root usermod -s "$zsh_path" "$USER"
    ok "login shell: $zsh_path (from the next login)"
else
    ok "zsh is already the login shell"
fi
