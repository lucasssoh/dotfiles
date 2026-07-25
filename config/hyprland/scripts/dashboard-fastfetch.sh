#!/usr/bin/env bash
# Contenu de la fenêtre pin windowrule "dashboard-fastfetch" (cf. windowrules.lua).
fastfetch
# fastfetch termine immédiatement une fois l'affichage fait ; on bloque
# ici pour garder le terminal (et donc la fenêtre) ouvert indéfiniment.
read -r
