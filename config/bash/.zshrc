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
# STARSHIP
# =========================
command -v starship >/dev/null && eval "$(starship init zsh)"

# =========================
# SDKMAN
# =========================
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
# Plugins Zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#777777"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
