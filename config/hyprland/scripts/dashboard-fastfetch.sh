#!/usr/bin/env bash
# Content of the pinned "dashboard-fastfetch" windowrule window (see windowrules.lua).
fastfetch
# fastfetch exits immediately once it's done rendering; we block here to
# keep the terminal (and therefore the window) open indefinitely.
read -r
