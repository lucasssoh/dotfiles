# =========================
# PROMPT NATIF ZSH (remplace Starship)
# Même logique que starship.toml : contexte, chemin, git, durée, statut —
# mais sobre : pas de pills/fonds colorés, couleurs discrètes.
# =========================

zmodload zsh/datetime
autoload -Uz vcs_info
autoload -Uz add-zsh-hook
setopt PROMPT_SUBST

# --- Palette (reprise de starship.toml) ---
_prompt_orange="#ffb400"
_prompt_red="#b0151a"
_prompt_dim_red="#a06060"
_prompt_green="#028902"
_prompt_blue="#0082c9"
_prompt_grey="243"
_prompt_dim_grey="237"

# --- Git (vcs_info) ---
zstyle ':vcs_info:git:*' formats " %F{$_prompt_grey}%b%f%u%c"
zstyle ':vcs_info:git:*' actionformats " %F{$_prompt_grey}%b|%a%f%u%c"
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' unstagedstr " %F{$_prompt_dim_red}✗%f"
zstyle ':vcs_info:*' stagedstr " %F{$_prompt_orange}●%f"

# --- Projet (langage/framework du dossier courant) ---
# Détecté via des fichiers manifestes de projet (Cargo.toml, package.json...),
# jamais via de simples fichiers isolés (*.py, *.rs...) qui ne font pas un projet.
_prompt_project_label=""

_prompt_detect_project() {
  local label=""

  if [[ -f Cargo.toml ]]; then
    label="rust"
  elif [[ -f go.mod ]]; then
    label="go"
  elif [[ -f package.json ]]; then
    if grep -q '"next"' package.json 2>/dev/null; then
      label="next"
    elif grep -q '"nuxt"' package.json 2>/dev/null; then
      label="nuxt"
    elif grep -q '"react"' package.json 2>/dev/null; then
      label="react"
    elif grep -q '"vue"' package.json 2>/dev/null; then
      label="vue"
    elif grep -q '"svelte"' package.json 2>/dev/null; then
      label="svelte"
    elif grep -q '"@angular/core"' package.json 2>/dev/null; then
      label="angular"
    else
      label="node"
    fi
  elif [[ -f pyproject.toml || -f setup.py || -f Pipfile ]]; then
    label="py"
  elif [[ -f Gemfile ]]; then
    label="ruby"
  elif [[ -f composer.json ]]; then
    label="php"
  elif [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]]; then
    label="java"
  else
    local dotnet=(*.csproj(N) *.sln(N))
    (( ${#dotnet} )) && label="dotnet"
  fi

  _prompt_project_label="$label"
}
add-zsh-hook chpwd _prompt_detect_project
_prompt_detect_project

# --- Durée de commande (affichée si >= 2s, comme cmd_duration.min_time) ---
_prompt_cmd_start=0
_prompt_cmd_duration=""
_prompt_had_cmd=0

_prompt_preexec() {
  _prompt_cmd_start=$EPOCHREALTIME
}
add-zsh-hook preexec _prompt_preexec

_prompt_precmd() {
  local exit=$?

  vcs_info

  _prompt_cmd_duration=""
  if (( _prompt_cmd_start > 0 )); then
    local elapsed=$(( EPOCHREALTIME - _prompt_cmd_start ))
    (( elapsed >= 2 )) && _prompt_cmd_duration=$(printf ' %.1fs' $elapsed)
    _prompt_cmd_start=0
  fi

  # Contexte local vs distant (même logique que $PROMPT_CONTEXT)
  local ctx="${PROMPT_CONTEXT:-•}"
  local ctx_color="$_prompt_grey"
  [[ -n "$SSH_CONNECTION" ]] && ctx_color="$_prompt_blue"

  # Couleur du caractère selon le code de sortie de la dernière commande
  local char_color="$_prompt_grey"
  (( exit != 0 )) && char_color="$_prompt_red"

  # Séparateur horodaté marquant la fin de la commande précédente
  local sep=""
  (( _prompt_had_cmd )) && sep="%F{$_prompt_dim_grey}───%f %F{$_prompt_grey}$(strftime '%H:%M:%S' $EPOCHSECONDS)%f
"
  _prompt_had_cmd=1

  local project_seg=""
  [[ -n "$_prompt_project_label" ]] && project_seg="%F{$_prompt_grey}${_prompt_project_label} %f"

  PROMPT="
${sep}%F{$ctx_color}${ctx}%f ${project_seg}%B%3~%b\${vcs_info_msg_0_}%F{$_prompt_orange}\${_prompt_cmd_duration}%f
%F{$char_color}\$%f "
}
add-zsh-hook precmd _prompt_precmd
