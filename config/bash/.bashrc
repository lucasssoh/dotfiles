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
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.cargo/bin"

# --- OUTILS DE PERFORMANCE ---
eval "$(zoxide init bash)"
# FZF (Recherche floue)
[ -f /usr/share/fzf/shell/key-bindings.bash ] && source /usr/share/fzf/shell/key-bindings.bash

# --- STYLE ---
eval "$(starship init bash)"