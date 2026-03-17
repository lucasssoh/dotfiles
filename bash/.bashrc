# --- INTERACTIF ---
# Si on n'est pas dans un shell interactif, on ne fait rien
[[ $- != *i* ]] && return

# --- HISTORIQUE ---
export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend

# --- OPTIONS BASH ---
shopt -s autocd      # cd automatique si on tape un nom de dossier
shopt -s globstar    # support des ** (recherche récursive)
shopt -s checkwinsize # vérifie la taille de la fenêtre après chaque commande

# --- ALIAS ---
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# --- OUTILS DE PERFORMANCE ---
# Zoxide (cd intelligent)
eval "$(zoxide init bash)"

# FZF (Recherche floue pour CTRL+R)
source /usr/share/fzf/shell/key-bindings.bash 2>/dev/null

# --- STYLE (À LA FIN) ---
eval "$(starship init bash)"
