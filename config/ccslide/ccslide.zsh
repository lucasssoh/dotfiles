# --- Workflow ccslide (decks de présentation mdp) ---
# Jumeau de ccnote : même moteur de workspaces, mais produit des decks mdp.
export CCSLIDE_SCRIPT="$HOME/.config/ccslide/ccslide.py"

ccslide() {
    if [ ! -f "$CCSLIDE_SCRIPT" ]; then
        echo "[ERREUR] Le script ccslide.py est introuvable."
        return 1
    fi

    # Sous-commandes qui n'ouvrent pas d'éditeur : on laisse Python parler.
    case "$1" in
        --new-workspace|--check|--list|--split)
            python3 "$CCSLIDE_SCRIPT" "$@"
            return $?
            ;;
    esac

    local output
    output=$(python3 "$CCSLIDE_SCRIPT" "$@") || return $?

    # Aucune cible : sélecteur fzf sur tous les decks existants.
    if [[ "$output" == *"__PICK__:"* ]]; then
        local picked
        picked=$(python3 "$CCSLIDE_SCRIPT" --list \
            | fzf --delimiter='\t' --with-nth=1 \
                  --prompt='deck > ' \
                  --preview='bat --color=always --style=plain {2}' \
            | cut -f2)
        [[ -z "$picked" ]] && return 0
        pushd "${picked:h}" > /dev/null
        nvim "$picked"
        popd > /dev/null
        return 0
    fi

    if [[ "$output" == *"__CWD__:"* ]]; then
        local target_dir deck_file
        target_dir=$(echo "$output" | grep '__CWD__:'  | tail -n 1)
        target_dir="${target_dir#*__CWD__:}"
        deck_file=$(echo "$output" | grep '__FILE__:' | tail -n 1)
        deck_file="${deck_file#*__FILE__:}"

        pushd "$target_dir" > /dev/null
        if [ -f "$deck_file" ]; then
            nvim "$deck_file"
        else
            nvim .
        fi
        popd > /dev/null
    fi
}

# Présenter un deck sans passer par nvim.
ccshow() {
    local target="${1:-deck.md}"
    if [ ! -f "$target" ]; then
        echo "[ERREUR] Deck introuvable : $target"
        return 1
    fi
    python3 "$CCSLIDE_SCRIPT" --check "$target" || {
        echo -n "Présenter quand même ? [y/N] "
        read -r answer
        [[ "$answer" != [yY] ]] && return 1
    }
    mdp "$target"
}

# Autocomplétion multiniveau (mêmes conventions que ccnote)
_ccslide() {
    local -a ccslide_suggestions
    ccslide_suggestions=($(python3 "$CCSLIDE_SCRIPT" --complete ${words[2,-1]}))
    _arguments \
        "1:Workspaces ou Commandes:($ccslide_suggestions --check --list --new-workspace)" \
        "*:Séances:($ccslide_suggestions today)"
}

compdef _ccslide ccslide
