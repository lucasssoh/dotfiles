#!/usr/bin/env bash
# MathJax for Markdown maths, pinned by config/liseuse/package-lock.json.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

dir="$REPO/config/liseuse"
if [ -d "$dir/node_modules/mathjax-full" ]; then
    info "mathjax-full already installed"
    exit 0
fi
npm ci --prefix "$dir" --omit=dev --no-audit --no-fund
ok "mathjax-full installed"
