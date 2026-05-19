# --- Workflow ccnote (Workspaces Multi-niveaux) ---
export CCNOTE_SCRIPT="$HOME/.config/ccnote/ccnote.py"

ccnote() {
    if [ ! -f "$CCNOTE_SCRIPT" ]; then
        echo "[ERREUR] Le script ccnote.py est introuvable."
        return 1
    fi

    # Si c'est une création de workspace, on laisse Python gérer sans ouvrir d'éditeur
    if [[ "$1" == "--new-workspace" ]]; then
        python3 "$CCNOTE_SCRIPT" "$@"
        return
    fi

    # Exécution standard
    local output=$(python3 "$CCNOTE_SCRIPT" "$@")
    
    if [[ "$output" == *"__CWD__:"* ]]; then
        local target_dir="${output#*__CWD__:}"
        target_dir=$(echo "$target_dir" | tail -n 1)
        
        # 1. On sauvegarde le dossier actuel et on switch vers le dossier de la note
        # (> /dev/null pour éviter que le terminal affiche la pile des dossiers)
        pushd "$target_dir" > /dev/null
        
        # 2. On lance Neovim (qui hérite du bon CWD, parfait pour nvim-tree et Telescope)
        if [ -f "index.md" ]; then
            nvim index.md
        else
            nvim .
        fi
        
        # 3. Dès que Neovim se ferme, on te renvoie instantanément à ton dossier de départ
        popd > /dev/null
    fi
}

# Autocomplétion intelligente multiniveau
_ccnote() {
    local -a ccnote_suggestions
    ccnote_suggestions=($(python3 "$CCNOTE_SCRIPT" --complete ${words[2,-1]}))
    _arguments "1:Workspaces ou Commandes:($ccnote_suggestions)" "*:Notes:($ccnote_suggestions)"
}

compdef _ccnote ccnote

# Autocomplétion intelligente multiniveau
_ccnote() {
    local -a ccnote_suggestions
    ccnote_suggestions=($(python3 "$CCNOTE_SCRIPT" --complete ${words[2,-1]}))
    _arguments "1:Workspaces ou Commandes:($ccnote_suggestions)" "*:Notes:($ccnote_suggestions)"
}

compdef _ccnote ccnote
