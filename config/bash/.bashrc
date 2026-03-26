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


# --- LOGIQUE DE CONTEXTE (SSH vs LOCAL) ---
# Cette variable sera lue par ton starship.toml
if [ -n "$SSH_CONNECTION" ]; then
    export PROMPT_CONTEXT="(remote)"
else
    export PROMPT_CONTEXT="•"
fi

# --- OUTILS DE PERFORMANCE ---
# On vérifie que zoxide est installé avant l'eval pour éviter les erreurs au login
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# FZF (Recherche floue)
[ -f /usr/share/fzf/shell/key-bindings.bash ] && source /usr/share/fzf/shell/key-bindings.bash


# --- LANGUAGES & RUNTIMES ---

# 1. NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # On charge NVM sans activer de version par défaut (gain de performance au login)
    \. "$NVM_DIR/nvm.sh" --no-use
    # On charge les complétions bash pour nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
fi

# 2. Python / Pipx (Pour tes linters/formatters)
add_to_path "$HOME/.local/bin" # Pour s'assurer que les binaires pipx sont vus

# 3. Fonction nvm_auto_switch (Bonus L3/Projets)
# Charge la version de node spécifiée dans un fichier .nvmrc s'il existe
cd() {
    builtin cd "$@" && \
    if [ -f ".nvmrc" ] && [ -s ".nvmrc" ]; then
        echo -e "\033[0;34m(nvm) Détection .nvmrc...\033[0m"
        nvm use
    fi
}

# --- STYLE ---
command -v starship >/dev/null && eval "$(starship init bash)"
