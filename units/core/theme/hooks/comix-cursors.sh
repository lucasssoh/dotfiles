#!/usr/bin/env bash
# Comix Cursors (White, opaque) built from upstream sources.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

theme=White
if [ -d "$HOME/.icons/ComixCursors-$theme" ]; then
    info "ComixCursors-$theme already installed"
    exit 0
fi
build="$HOME/.cache/comixcursors-build"
rm -rf "$build"
git clone --quiet --depth 1 https://gitlab.com/limitland/comixcursors.git "$build"
sed -i 's/^CURSORTRANS=.*/CURSORTRANS=0/' "$build/ComixCursorsConfigs/$theme.CONFIG"
cd "$build"
MULTISIZE=true THEMENAME="$theme" ./bin/build-cursors
make THEMENAME="$theme"
make install THEMENAME="$theme"
ok "ComixCursors-$theme installed in ~/.icons"
