#!/usr/bin/env bash
# Builds coucou-shell's RPMs from a git ref, on Fedora.
#
#   packaging/build-rpms.sh v1.0.0 [out-dir]
#
# The version is the tag without its "v"; any other ref builds as 0.0.0.
# Needs rpm-build and the spec's BuildRequires.
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
    LICENSE.md LICENSES crates config/hyprland/roue-src config/hyprland/prisme-src config/hyprland/balise-src config/hyprland/manette-src

rpmbuild -bb \
    --define "_topdir $top" \
    --define "cc_version $version" \
    "$repo/packaging/coucou-shell.spec"

cp "$top"/RPMS/*/*.rpm "$out/"
ls -1 "$out"
