#!/usr/bin/env bash
# Tools the Neovim config calls: pylatexenc (maths), plantuml-lsp.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

if have pipx; then
    pipx list --short 2>/dev/null | grep '^pylatexenc ' >/dev/null || pipx install pylatexenc
fi
if ! have plantuml-lsp && [ ! -x "$HOME/.local/bin/plantuml-lsp" ]; then
    GOBIN="$HOME/.local/bin" go install github.com/ptdewey/plantuml-lsp@latest
fi
ok "Neovim tools in place"
