#!/usr/bin/env bash
# Builds coucou-shell's RPMs from a git ref, on Fedora.
#
#   packaging/build-rpms.sh v1.0.0 [out-dir]
#
# The version is the tag without its "v"; any other ref builds as 0.0.0.
# Needs rpm-build, curl and both specs' BuildRequires (coucou-shell.spec,
# satty/satty.spec).
set -euo pipefail

ref="${1:?usage: build-rpms.sh <tag> [out-dir]}"
out="$(realpath -m "${2:-rpms}")"
repo="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
version="${ref#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || version="0.0.0"

top="$(mktemp -d)"
trap 'rm -rf "$top"' EXIT
mkdir -p "$top/SOURCES" "$out"

git -C "$repo" archive --format=tar.gz --prefix="coucou-shell-$version/" \
    -o "$top/SOURCES/coucou-shell-$version.tar.gz" "$ref" \
    LICENSE.md LICENSES crates config/hyprland/roue-src config/hyprland/prisme-src config/hyprland/balise-src config/hyprland/manette-src config/hyprland/pouls-src config/hyprland/programme-src config/hyprland/sesame-src

rpmbuild -bb \
    --define "_topdir $top" \
    --define "cc_version $version" \
    "$repo/packaging/coucou-shell.spec"

# satty: upstream's tarball, checked against its pinned sha256, plus our
# patch. Its version is its own, not the release's.
satty="$repo/packaging/satty"
satty_version="$(rpmspec -q --srpm --qf '%{version}\n' "$satty/satty.spec")"
curl -fsSL -o "$top/SOURCES/Satty-$satty_version.tar.gz" \
    "https://github.com/Satty-org/Satty/archive/v$satty_version/Satty-$satty_version.tar.gz"
(cd "$top/SOURCES" && sha256sum --check --quiet "$satty/satty.sha256")
cp "$satty/satty-glass.patch" "$top/SOURCES/"
rpmbuild -bb --define "_topdir $top" "$satty/satty.spec"

cp "$top"/RPMS/*/*.rpm "$out/"
ls -1 "$out"
