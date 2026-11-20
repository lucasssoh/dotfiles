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
zstyle ':vcs_info:git:*' formats " %F{$_prompt_grey}%b%f%u%c%m"
zstyle ':vcs_info:git:*' actionformats " %F{$_prompt_grey}%b|%a%f%u%c%m"
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' unstagedstr " %F{$_prompt_dim_red}✗%f"
zstyle ':vcs_info:*' stagedstr " %F{$_prompt_orange}●%f"

# --- Fichiers non suivis (%m) ---
# + : au moins un fichier non suivi par git. check-for-changes ne voit que
#     l'index et l'arbre de travail, les nouveaux fichiers lui échappent.
+vi-git-untracked() {
  # --directory s'arrête au premier dossier non suivi au lieu de le parcourir,
  # et head coupe dès la première ligne : rien ne dépend de la taille du dépôt.
  local untracked
  untracked=$(command git ls-files --others --exclude-standard \
                --directory --no-empty-directory 2>/dev/null | head -n 1)
  # `return 0`, jamais `return` tout court : vcs_info interrompt la chaîne
  # de hooks dès que l'un d'eux renvoie non-zéro, et un `return` nu rend
  # le statut du test au-dessus -- donc 1 quand il n'y a rien de non
  # suivi, ce qui faisait disparaître le ↑N du hook suivant.
  [[ -n "$untracked" ]] || return 0

  # Colle au marqueur précédent (✗/●) s'il y en a un, sinon s'en sépare.
  local sep=" "
  [[ -n "${hook_com[unstaged]}${hook_com[staged]}" ]] && sep=""
  hook_com[misc]+="${sep}%F{$_prompt_blue}+%f"
}

# --- Commits locaux non poussés (%m) ---
# ↑N  : N commits d'avance sur l'upstream, donc pas encore poussés.
# ↑?  : branche sans upstream, jamais poussée.
# Volontairement pas de ↓ : le retard sur le remote ne serait exact
# qu'après un fetch, et le prompt ne doit rien faire passer sur le réseau.
zstyle ':vcs_info:git*+set-message:*' hooks git-untracked git-push-status

+vi-git-push-status() {
  # Colle au marqueur précédent (✗/●/+) s'il y en a un, sinon s'en sépare.
  local sep=" "
  [[ -n "${hook_com[unstaged]}${hook_com[staged]}${hook_com[misc]}" ]] && sep=""

  local ahead
  if ! ahead=$(command git rev-list --count '@{upstream}..HEAD' 2>/dev/null); then
    hook_com[misc]+="${sep}%F{$_prompt_dim_red}↑?%f"
    return
  fi

  (( ahead > 0 )) && hook_com[misc]+="${sep}%F{$_prompt_orange}↑${ahead}%f"
  return 0   # même raison que ci-dessus : (( ahead > 0 )) faux rend 1.
}

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

_prompt_env_label=""
_prompt_env_color=""
_prompt_py_version=""

_prompt_read_py_version() {
  _prompt_py_version=""
  local cfg line
  [[ -r "$1/pyvenv.cfg" ]] || return 0
  cfg=$(< "$1/pyvenv.cfg")
  for line in ${(f)cfg}; do
    if [[ "$line" =~ '^version(_info)?[[:space:]]*=[[:space:]]*([0-9]+\.[0-9]+)' ]]; then
      _prompt_py_version=$match[2]
      break
    fi
  done
  return 0
}

_prompt_detect_env() {
  local label="" color="" name=""
  _prompt_env_label=""
  _prompt_env_color=""

  if [[ -n "${CONDA_PREFIX:-}" ]]; then
    name="${CONDA_DEFAULT_ENV:-${CONDA_PREFIX:t}}"
    label="py ${name}·conda"
    color="$_prompt_green"
  elif [[ -n "${VIRTUAL_ENV:-}" ]]; then
    name="${VIRTUAL_ENV:t}"
    [[ "$name" == "bin" ]] && name="${VIRTUAL_ENV:h:t}"
    _prompt_read_py_version "$VIRTUAL_ENV"
    label="py"
    [[ -n "$_prompt_py_version" ]] && label+=" $_prompt_py_version"
    if [[ -n "${POETRY_ACTIVE:-}" ]]; then
      name="poetry"
    elif [[ -n "${UV_PROJECT_ENVIRONMENT:-}" ]]; then
      name="uv"
    fi
    label+="·${name}"
    color="$_prompt_green"
  elif [[ -n "${PYENV_VERSION:-}" ]]; then
    label="py ${PYENV_VERSION}·pyenv"
    color="$_prompt_blue"
  elif [[ -n "${NVM_BIN:-}" ]]; then
    name="${${NVM_BIN:h}:t}"
    label="node ${name#v}·nvm"
    color="$_prompt_blue"
  elif [[ -n "${FNM_MULTISHELL_PATH:-}" ]]; then
    name="${${FNM_MULTISHELL_PATH:A}:h:t}"
    label="node ${name#v}·fnm"
    color="$_prompt_blue"
  elif [[ -n "${RUSTUP_TOOLCHAIN:-}" ]]; then
    label="rs ${RUSTUP_TOOLCHAIN}·rustup"
    color="$_prompt_blue"
  elif [[ -n "${RBENV_VERSION:-}" ]]; then
    label="rb ${RBENV_VERSION}·rbenv"
    color="$_prompt_blue"
  elif [[ -n "${GEM_HOME:-}" && "$GEM_HOME" == *rvm* ]]; then
    label="rb ${GEM_HOME:t}·rvm"
    color="$_prompt_blue"
  elif [[ -n "${JAVA_HOME:-}" && -n "${SDKMAN_CANDIDATES_DIR:-}" && "$JAVA_HOME" == "${SDKMAN_CANDIDATES_DIR}/java/"* ]]; then
    label="java ${JAVA_HOME:t}·sdk"
    color="$_prompt_blue"
  elif [[ -n "${MISE_ENV:-}" ]]; then
    label="mise ${MISE_ENV}"
    color="$_prompt_blue"
  fi

  label=${label//\%/%%}
  _prompt_env_label="$label"
  _prompt_env_color="$color"
}

# --- Durée de commande (affichée si >= 2s, comme cmd_duration.min_time) ---
_prompt_cmd_start=0
_prompt_cmd_duration=""
_prompt_had_cmd=0

# Format HHhMMmSSs, en omettant les unités de tête nulles :
#   3.4s / 12.0s          (moins d'une minute, la précision reste utile)
#   3m07s                 (moins d'une heure)
#   2h05m09s              (au-delà)
_prompt_format_duration() {
  local LC_NUMERIC=C   # locale fr : sinon printf écrit "2,4s" au lieu de "2.4s"
  local -F elapsed=$1
  local -i total h m sec
  (( total = elapsed ))
  (( h = total / 3600, m = total % 3600 / 60, sec = total % 60 ))

  if (( h > 0 )); then
    printf '%dh%02dm%02ds' $h $m $sec
  elif (( m > 0 )); then
    printf '%dm%02ds' $m $sec
  else
    printf '%.1fs' $elapsed
  fi
}

_prompt_preexec() {
  _prompt_cmd_start=$EPOCHREALTIME
}
add-zsh-hook preexec _prompt_preexec

_prompt_precmd() {
  local exit=$?

  vcs_info
  _prompt_detect_env

  _prompt_cmd_duration=""
  if (( _prompt_cmd_start > 0 )); then
    local elapsed=$(( EPOCHREALTIME - _prompt_cmd_start ))
    (( elapsed >= 2 )) && _prompt_cmd_duration=" $(_prompt_format_duration $elapsed)"
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
  if [[ -n "$_prompt_env_label" ]]; then
    project_seg="%F{$_prompt_env_color}${_prompt_env_label}%f "
  elif [[ -n "$_prompt_project_label" ]]; then
    project_seg="%F{$_prompt_grey}${_prompt_project_label} %f"
  fi

  PROMPT="
${sep}%F{$ctx_color}${ctx}%f ${project_seg}%B%3~%b\${vcs_info_msg_0_}%F{$_prompt_orange}\${_prompt_cmd_duration}%f
%F{$char_color}\$%f "
}
add-zsh-hook precmd _prompt_precmd
