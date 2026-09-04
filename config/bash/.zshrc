
# --- INTERACTIF ---
[[ -o interactive ]] || return

# =========================
# HISTORIQUE
# =========================
HISTSIZE=10000
SAVEHIST=20000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt APPEND_HISTORY

# =========================
# OPTIONS ZSH
# =========================
setopt AUTO_CD
setopt GLOBSTAR_SHORT
unsetopt CORRECT
setopt CHECK_JOBS
setopt INTERACTIVE_COMMENTS

# =========================
# PATH (BASE PROPRE)
# =========================
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:$PATH"
add_to_path() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        export PATH="$1:$PATH"
    fi
}
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.cargo/bin"
add_to_path "$HOME/.npm-global/bin"
add_to_path "/var/lib/snapd/snap/bin"

# =========================
# ALIAS
# =========================
[ -f ~/.bash_aliases ] && source ~/.bash_aliases

# =========================
# CONTEXTE (SSH)
# =========================
if [[ -n "$SSH_CONNECTION" ]]; then
    export PROMPT_CONTEXT="(remote)"
else
    export PROMPT_CONTEXT="•"
fi

# =========================
# OUTILS
# =========================
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# FZF
[ -f /usr/share/fzf/shell/key-bindings.zsh ] && source /usr/share/fzf/shell/key-bindings.zsh

# =========================
# NVM
# =========================
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh" --no-use
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
fi

# =========================
# AUTO NVM SWITCH (propre ZSH)
# =========================
autoload -U add-zsh-hook
load-nvmrc() {
  if [ -f .nvmrc ]; then
    echo "(nvm) Détection .nvmrc..."
    nvm use
  fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc

# =========================
# SDKMAN
# =========================
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# =========================
# PLUGINS ZSH (autosuggestions EN PREMIER)
# =========================
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#777777"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_COMPLETION_IGNORE="*fatandfurious*"
ZSH_AUTOSUGGEST_HISTORY_IGNORE="*fatandfurious*"
zstyle ':completion:*:*:-command-:*:*' ignored-patterns 'fatandfurious'
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# =========================
# VI MODE ZSH (AVANT starship et syntax-highlighting)
# =========================
bindkey -v
export KEYTIMEOUT=1

# Curseur : barre en insert, bloc en normal
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'   # bloc  → normal mode
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'   # barre → insert mode
  fi
}
zle -N zle-keymap-select

function zle-line-init {
  echo -ne '\e[5 q'     # barre par défaut au démarrage
}
zle -N zle-line-init

# =========================
# JK / KJ ESCAPE (INSERT MODE)
# =========================
jk-escape() {
  zle vi-cmd-mode
}
kj-escape() {
  zle vi-cmd-mode
}
zle -N jk-escape
zle -N kj-escape
bindkey -M viins 'jk' jk-escape
bindkey -M viins 'kj' kj-escape

# =========================
# PROMPT (APRÈS vi mode, AVANT syntax-highlighting)
# =========================
source ~/.config/bash/prompt.zsh

# =========================
# SYNTAX HIGHLIGHTING (EN DERNIER — obligatoire)
# =========================
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# =========================
# CCNOTE
# =========================
source ~/.config/ccnote/ccnote.zsh
export PATH="$HOME/.npm-global/bin:$PATH"

# Local secrets / environment
if [ -f "$HOME/.config/bash/.env.local" ]; then
    source "$HOME/.config/bash/.env.local"
fi
