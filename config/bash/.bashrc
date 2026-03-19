# --- INTERACTIF ---
[[ $- != *i* ]] && return

# --- HISTORIQUE ---
export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend

# --- OPTIONS BASH ---
shopt -s autocd globstar checkwinsize

# --- FONCTIONS SYSTÈME ---
# Ajoute au PATH proprement (sans doublons)
add_to_path() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        export PATH="$1:$PATH"
    fi
}

# --- ALIAS ---
[ -f ~/.bash_aliases ] && . ~/.bash_aliases

# --- GESTION DU PATH ---
# 1. On repart sur une base saine, absolue et standard pour Fedora
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin"

# 2. On ajoute tes dossiers personnels via la fonction (qui évite les doublons)
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.cargo/bin"
# Dans ton ~/.bashrc, sous les autres add_to_path
add_to_path "/var/lib/snapd/snap/bin"

# --- OUTILS DE PERFORMANCE ---
# On vérifie que zoxide est installé avant l'eval pour éviter les erreurs au login
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# FZF (Recherche floue)
[ -f /usr/share/fzf/shell/key-bindings.bash ] && source /usr/share/fzf/shell/key-bindings.bash

# --- STYLE ---
command -v starship >/dev/null && eval "$(starship init bash)"