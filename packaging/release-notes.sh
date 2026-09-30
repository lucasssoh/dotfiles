#!/usr/bin/env bash
# Prints a release's section of CHANGELOG.md, without its heading.
#
#   packaging/release-notes.sh v1.0.0
set -euo pipefail

version="${1:?usage: release-notes.sh <tag>}"
version="${version#v}"
awk -v v="$version" '
    /^## / { on = (index($0, "## " v " ") == 1); next }
    on
' "$(dirname "$0")/../CHANGELOG.md"
