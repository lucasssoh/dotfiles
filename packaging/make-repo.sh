#!/usr/bin/env bash
# Builds the dnf repository published on GitHub Pages.
#
#   packaging/make-repo.sh <rpm-dir> <out-dir>
#
# Lays the RPMs out per Fedora release (fedora/<N>/x86_64/), indexes each
# with createrepo_c and signs its repomd.xml with the gpg key in the keyring.
# <out-dir> also receives coucou-shell.repo and the public key, at the paths
# the .repo file names.
set -euo pipefail

rpms="${1:?usage: make-repo.sh <rpm-dir> <out-dir>}"
out="${2:?usage: make-repo.sh <rpm-dir> <out-dir>}"
here="$(dirname "$0")"

mkdir -p "$out/rpm"
cp "$here/coucou-shell.repo" "$out/"
cp "$here/RPM-GPG-KEY-coucou-shell" "$out/rpm/"

shopt -s nullglob
for f in "$rpms"/*.rpm; do
    [[ "$(basename "$f")" =~ \.fc([0-9]+)\.x86_64\.rpm$ ]] || continue
    mkdir -p "$out/rpm/fedora/${BASH_REMATCH[1]}/x86_64"
    cp "$f" "$out/rpm/fedora/${BASH_REMATCH[1]}/x86_64/"
done

for dir in "$out"/rpm/fedora/*/x86_64; do
    createrepo_c --quiet "$dir"
    gpg --batch --yes --detach-sign --armor "$dir/repodata/repomd.xml"
done
