#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Initialisation de l'environnement de dév (DNF5 / Fedora 43) ===${NC}"

# 1. Outils système (C/C++ & Build tools)
echo -e "${GREEN}[1/6] Installation des outils système essentiels...${NC}"
# Sous DNF5, on utilise "group install" ou on liste les composants
sudo dnf install -y @development-tools @c-development
sudo dnf install -y curl wget git cmake gcc-c++ gdb clang lldb libstdc++-devel

# 2. Python (System wide + venv)
echo -e "${GREEN}[2/6] Configuration Python...${NC}"
sudo dnf install -y python3 python3-pip python3-devel
# On évite d'installer des packages pip en global sur Fedora 43 (PEP 668)
# On privilégie l'utilisation de venv pour tes projets
python3 -m pip install --user --upgrade pip 2>/dev/null || echo "Pip déjà à jour ou géré par le système."

# 3. Java (LTS 21)
echo -e "${GREEN}[3/6] Installation de Java (OpenJDK 21)...${NC}"
sudo dnf install -y java-21-openjdk-devel

# 4. NVM (Node Version Manager)
echo -e "${GREEN}[4/6] Installation de NVM...${NC}"
if [ ! -d "$HOME/.nvm" ]; then
    # PROFILE=/dev/null empêche l'installeur de toucher à ton .bashrc
    PROFILE=/dev/null curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    
    # Chargement manuel UNIQUEMENT pour la durée du script
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
else
    echo "NVM déjà présent."
fi

# 4.5. Google Gemini CLI
echo -e "${GREEN}[4.5/6] Installation du Gemini CLI...${NC}"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if [ -d "$NVM_DIR" ]; then
    # 1. Nettoyage du .npmrc (toujours nécessaire)
    [ -f "$HOME/.npmrc" ] && sed -i '/prefix=/d' "$HOME/.npmrc"

    # 2. Garantie d'avoir Node (Correction de la syntaxe nvm)
    # On essaie d'utiliser la version courante, sinon on installe la LTS
    if ! nvm use default --delete-prefix &>/dev/null; then
        echo "Configuration de Node LTS..."
        nvm install --lts
        nvm alias default 'lts/*'
        nvm use default
    fi

    # 3. Installation
    if ! command -v gemini &>/dev/null; then
        echo "Installation de @google/gemini-cli..."
        npm install -g @google/gemini-cli
    else
        echo "Gemini CLI déjà présent ($(gemini --version 2>/dev/null | head -n 1))."
    fi
else
    echo -e "${BLUE}WARN: NVM non détecté.${NC}"
fi

# 5. Docker (Installation DNF5 compatible)
echo -e "${GREEN}[5/6] Configuration de Docker...${NC}"
if ! command -v docker &> /dev/null; then
    # Fedora 43 a parfois besoin de définir explicitement le repo
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER
    echo -e "${BLUE}INFO: Docker installé. Déconnecte-toi et reconnecte-toi pour le groupe 'docker'.${NC}"
else
    echo "Docker déjà présent."
fi

# 6. Outils Qualité & Clean Code
echo -e "${GREEN}[6/6] Installation des linters (Black / Flake8)...${NC}"
# Utilisation de pipx si possible pour isoler les outils CLI Python
sudo dnf install -y pipx
pipx ensurepath
pipx install black 2>/dev/null || true
pipx install flake8 2>/dev/null || true

echo -e "${BLUE}=== Environment ready ! ===${NC}"
