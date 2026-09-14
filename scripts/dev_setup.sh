#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Initialisation de l'environnement de dév (DNF5 / Fedora 43) ===${NC}"

# 1. System tools (C/C++ & Build tools)
echo -e "${GREEN}[1/6] Installation des outils système essentiels...${NC}"
# On DNF5, use "group install" or list the components individually
sudo dnf install -y @development-tools @c-development
sudo dnf install -y curl wget git cmake gcc-c++ gdb clang lldb libstdc++-devel

# Libs for Manim
sudo dnf install -y fribidi-devel harfbuzz-devel pango-devel cairo-devel

# 2. Python (System wide + venv)
echo -e "${GREEN}[2/6] Configuration Python...${NC}"
sudo dnf install -y python3 python3-pip python3-devel
# Avoid installing pip packages globally on Fedora 43 (PEP 668)
# Prefer using venv for your projects instead
python3 -m pip install --user --upgrade pip 2>/dev/null || echo "Pip déjà à jour ou géré par le système."

# 3. Java (LTS 21) + Maven + SDKMAN + Lombok
echo -e "${GREEN}[3/6] Installation de Java (OpenJDK 21), Maven, SDKMAN et Lombok...${NC}"

# maven n'etait pas la, et son absence ne se voyait pas sur une machine ou il
# avait ete installe a la main une fois. Elle casse pourtant Java entier sur une
# machine neuve : nvim/lua/lsp/java.lua cherche la racine d'un projet via
# M.root_markers = { "pom.xml", "mvnw", "gradlew", ... }. Sans build tool, jdtls
# ne resout aucune dependance -- donc pas de Lombok applique, meme avec le
# javaagent correctement cable.
sudo dnf install -y java-21-openjdk-devel maven

# ── SDKMAN ──────────────────────────────────────────────────────────────
# .bashrc et .zshrc SOURCENT sdkman-init.sh depuis des mois, mais rien ne
# l'installait. La garde `[[ -s ... ]] && source` fait echouer la ligne en
# silence : pas d'erreur au demarrage du shell, juste pas de commande `sdk`.
# C'est ce qui fait qu'un `java` sur la machine de developpement est un IBM
# Semeru gere par SDKMAN alors qu'une machine fraiche n'a que l'OpenJDK de
# Fedora -- deux fournisseurs differents, sans que rien ne le signale.
#
# ATTENTION avant de toucher a ce bloc : l'installeur SDKMAN fait
# `>> "$HOME/.bashrc"` et `>> "$HOME/.zshrc"`, et ces deux fichiers sont des
# LIENS SYMBOLIQUES vers config/bash/ dans ce depot. Une redirection suit le
# lien : il ecrirait donc dans le depot lui-meme, et chaque machine neuve
# salirait l'arbre git. Ce qui l'en empeche est sa propre garde --
# `if [[ -z $(grep 'sdkman-init.sh' "$rcfile") ]]` -- et les deux fichiers
# contiennent deja cette chaine (verifie). Ne retire donc jamais la ligne
# sdkman-init.sh de .bashrc ou .zshrc en croyant faire du menage : elle est
# aussi ce qui protege le depot.
if [ ! -d "$HOME/.sdkman" ]; then
    echo "Installation de SDKMAN..."
    # Telecharger puis executer, comme pour nvm plus bas : un `curl | bash`
    # direct masque l'echec de curl derriere un bash qui sort 0 sur une
    # entree vide.
    curl -fsSL -o /tmp/sdkman-install.sh https://get.sdkman.io
    bash /tmp/sdkman-install.sh
    rm -f /tmp/sdkman-install.sh
else
    echo "SDKMAN deja present."
fi

# ── Lombok ──────────────────────────────────────────────────────────────
# Jusqu'ici Lombok n'arrivait que par un effet de bord : le paquet `jdtls` de
# Mason embarque un lombok.jar, et nvim/lua/lsp/java.lua pointait dessus par
# chemin absolu. Ca marche tant que Mason a tourne, que son arborescence ne
# bouge pas, et que l'utilisateur s'appelle lucas.
#
# On le pose donc aussi a un endroit stable et previsible, que java.lua
# utilise en repli (voir le resolveur dans ce fichier). Version epinglee
# plutot que le "latest" de projectlombok.org : une machine reinstallee dans
# six mois doit obtenir ce que celle-ci a, pas ce qui sortira entre-temps.
# Lombok touche au compilateur, c'est exactement le genre de composant ou une
# mise a jour silencieuse se paie en erreurs incomprehensibles.
LOMBOK_VERSION="1.18.48"
LOMBOK_SHA1="6858f13541bab505384f07053c5a7b539bbfd3e3"
LOMBOK_DIR="$HOME/.local/share/java"
LOMBOK_JAR="$LOMBOK_DIR/lombok.jar"

mkdir -p "$LOMBOK_DIR"
if [ -f "$LOMBOK_JAR" ] && [ "$(sha1sum "$LOMBOK_JAR" | cut -d' ' -f1)" = "$LOMBOK_SHA1" ]; then
    echo "Lombok $LOMBOK_VERSION deja present et verifie."
else
    echo "Telechargement de Lombok $LOMBOK_VERSION..."
    # Maven Central plutot que projectlombok.org/downloads/lombok.jar : la
    # seconde URL sert toujours la derniere version et ne publie pas de somme
    # de controle a comparer.
    curl -fsSL -o "$LOMBOK_JAR.tmp" \
        "https://repo1.maven.org/maven2/org/projectlombok/lombok/${LOMBOK_VERSION}/lombok-${LOMBOK_VERSION}.jar"
    got="$(sha1sum "$LOMBOK_JAR.tmp" | cut -d' ' -f1)"
    if [ "$got" != "$LOMBOK_SHA1" ]; then
        rm -f "$LOMBOK_JAR.tmp"
        echo "ERREUR: sha1 de lombok.jar incorrect (attendu $LOMBOK_SHA1, obtenu $got)" >&2
        exit 1
    fi
    # mv seulement apres verification : jamais de jar a moitie telecharge a
    # l'emplacement final, ou java.lua irait le passer en -javaagent.
    mv "$LOMBOK_JAR.tmp" "$LOMBOK_JAR"
    echo "Lombok installe dans $LOMBOK_JAR"
fi

# 4. NVM & Node 22 (LTS - required for the Gemini CLI)
echo -e "${GREEN}[4/6] Configuration de Node.js via NVM...${NC}"
export NVM_DIR="$HOME/.nvm"

# Install NVM if missing
if [ ! -d "$NVM_DIR" ]; then
    echo "Installation de NVM..."
    # Download first, then run: piping curl straight into bash hides a
    # curl failure (network down, 404) behind bash happily exiting 0 on an
    # empty stdin -- the real error only surfaced later as a confusing
    # "nvm: command not found".
    curl -fsSL -o /tmp/nvm-install.sh https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh
    PROFILE=/dev/null bash /tmp/nvm-install.sh
    rm -f /tmp/nvm-install.sh
fi

# Must be loaded before the rest of the script can run
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Force Node 22 -- Node 18 causes dependency (Engine) errors with Gemini
echo "Installation et activation de Node 22 (LTS)..."
nvm install 22 --silent
nvm alias default 22
nvm use default --delete-prefix --silent

# 4.5. Google Gemini CLI
echo -e "${GREEN}[4.5/6] Installation du Gemini CLI...${NC}"

# 1. Permanently clean up .npmrc (avoids NVM/Prefix conflicts)
[ -f "$HOME/.npmrc" ] && sed -i '/prefix=/d' "$HOME/.npmrc"

# 2. Global install tied to the active Node version
# Check whether gemini responds first, otherwise install it
if ! command -v gemini &>/dev/null; then
    echo "Installation de @google/gemini-cli via npm..."
    npm install -g @google/gemini-cli
else
    echo "Gemini CLI déjà présent ($(node -v))."
fi

# 5. Docker (DNF5-compatible install)
echo -e "${GREEN}[5/6] Configuration de Docker...${NC}"
if ! command -v docker &> /dev/null; then
    # Fedora 43 sometimes needs the repo defined explicitly
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER
    echo -e "${BLUE}INFO: Docker installé. Déconnecte-toi et reconnecte-toi pour le groupe 'docker'.${NC}"
else
    echo "Docker déjà présent."
fi

# 6. Code quality / clean code tools
echo -e "${GREEN}[6/6] Installation des linters (Black / Flake8)...${NC}"
# Use pipx where possible to isolate Python CLI tools
sudo dnf install -y pipx
pipx ensurepath
pipx install black 2>/dev/null || true
pipx install flake8 2>/dev/null || true

echo -e "${BLUE}=== Environment ready ! ===${NC}"
