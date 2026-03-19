# --- COULEURS & AFFICHAGE ---
alias ls='ls --color=auto --group-directories-first'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# --- NAVIGATION ---
alias ..='cd ..'
alias ...='cd ../..'
alias ll='ls -lh'
alias la='ls -lAh'
alias dots='cd ~/dotfiles' # Accès rapide à ton repo

# --- FIXES & UTILS ---
alias refresh-brave='rm ~/.config/BraveSoftware/Brave-Browser/SingletonLock'
alias g='git'

# --- GESTION HYPRLAND (SSH & DEBUG) ---
# Lecture rapide des logs de la session actuelle
alias hlog='cat ${XDG_RUNTIME_DIR}/hypr/$(ls -t ${XDG_RUNTIME_DIR}/hypr/ 2>/dev/null | head -n 1)/hyprland.log'
alias hlogf='tail -f ${XDG_RUNTIME_DIR}/hypr/$(ls -t ${XDG_RUNTIME_DIR}/hypr/ 2>/dev/null | head -n 1)/hyprland.log'

# Fonction de synchronisation SSH -> Hyprland
# À taper une fois en arrivant en SSH
hsync() {
    local hypr_dir="$XDG_RUNTIME_DIR/hypr"
    if [ -d "$hypr_dir" ]; then
        local latest_session=$(ls -t "$hypr_dir" 2>/dev/null | head -n 1)
        if [ -n "$latest_session" ]; then
            export HYPRLAND_INSTANCE_SIGNATURE="$latest_session"
            export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep wayland | head -n 1 || echo "wayland-1")
            echo "󰄬 SSH lié à $WAYLAND_DISPLAY ($HYPRLAND_INSTANCE_SIGNATURE)"
        else
            echo "󰅚 Aucune session Hyprland trouvée."
        fi
    else
        echo "󰅚 Environnement graphique non détecté."
    fi
}

# --- PATHS & ENVIRONNEMENT ---
export PATH="$HOME/.symfony5/bin:$HOME/.symfony/bin:$PATH"

# Chargement Cargo (Rust)
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

# NVM (si présent)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"