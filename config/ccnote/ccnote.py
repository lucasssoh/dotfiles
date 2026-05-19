#!/usr/bin/env python3
import sys
import os
import json
from datetime import datetime

CONFIG_DIR = os.path.expanduser("~/.config/ccnote")
CONFIG_FILE = os.path.join(CONFIG_DIR, "workspaces.json")

def load_config():
    """Charge les workspaces configurés."""
    if not os.path.exists(CONFIG_FILE):
        # Workspace par défaut si le fichier n'existe pas encore
        default_config = {"default": os.path.expanduser("~/notes")}
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(default_config, f, indent=4)
        return default_config
    
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def save_config(config):
    """Sauvegarde la table des workspaces."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4)

def get_subdirs(base_path):
    """Retourne les sous-dossiers d'un chemin donné."""
    if not os.path.exists(base_path):
        return []
    return [d for d in os.listdir(base_path) if os.path.isdir(os.path.join(base_path, d))]

def print_completion(config, args):
    """Gère l'autocomplétion Zsh selon le contexte."""
    # Si l'utilisateur tape '--new-workspace', on ne propose rien (il tape un chemin)
    if len(args) > 1 and args[0] == "--new-workspace":
        return

    # Si l'utilisateur a sélectionné un workspace existant, on propose ses sous-dossiers
    if len(args) > 1 and args[0] in config:
        print(" ".join(get_subdirs(config[args[0]])))
        return

    # Par défaut, on propose la liste des configurations de workspaces disponibles
    print(" ".join(config.keys()))

def create_note_template(target_dir, note_name):
    """Génère le fichier index.md s'il n'existe pas."""
    os.makedirs(target_dir, exist_ok=True)
    index_file = os.path.join(target_dir, "index.md")
    
    if not os.path.exists(index_file):
        now = datetime.now().strftime("%Y-%m-%d %H:%M")
        template = f"""---
title: {note_name}
date: {now}
tags: []
---

# {note_name}

## Sommaire
- 
"""
        with open(index_file, "w", encoding="utf-8") as f:
            f.write(template)
        print(f"New note block created : {note_name}")

def main():
    config = load_config()
    args = sys.argv[1:]

    # --- MODE AUTOCOMPLÉTION ZSH ---
    if args and args[0] == "--complete":
        print_completion(config, args[1:])
        sys.exit(0)

    # --- COMMANDE : CRÉER UN NOUVEAU WORKSPACE ---
    # Usage: ccnote --new-workspace <nom> <chemin>
    if args and args[0] == "--new-workspace":
        if len(args) < 3:
            print("[Error] Usage: ccnote --new-workspace <name> <absolute_path>")
            sys.exit(1)
        name, path = args[1], os.path.expanduser(args[2])
        config[name] = path
        save_config(config)
        print(f" Workspace saved : '{name}' -> {path}")
        os.makedirs(path, exist_ok=True)
        sys.exit(0)

    # --- PARSAGE DES ARGUMENTS STANDARDS ---
    if not args:
        # Aucun argument : on prend le workspace par défaut
        workspace_name = "default"
        note_name = ""
    elif args[0] in config:
        # Premier argument valide = nom d'un workspace
        workspace_name = args[0]
        note_name = args[1] if len(args) > 1 else ""
    else:
        # Premier argument inconnu des workspaces = note dans le workspace par défaut
        workspace_name = "default"
        note_name = args[0]

    # Détermination du dossier cible
    base_path = config.get(workspace_name)
    if not base_path:
        print(f"[ERREUR] Workspace '{workspace_name}' not configured.")
        sys.exit(1)

    target_dir = base_path if not note_name else os.path.join(base_path, note_name)

    # Initialisation si la note n'existe pas encore
    if note_name:
        create_note_template(target_dir, note_name)

    # Envoi du CWD pour le pont Shell
    print(f"__CWD__:{target_dir}")

if __name__ == "__main__":
    main()
