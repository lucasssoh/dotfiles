#!/usr/bin/env bash
# satty now comes from the coucou-shell repo, with the frosted toolbars.
# Machines installed earlier have the mineiro/satty COPR and its build:
# the COPR goes, and satty is replaced by ours. Run again, it finds nothing
# to do.
. "$(dirname "$(readlink -f "$0")")/../../../lib/hook.sh"

repo_url="https://lucasssoh.github.io/dotfiles/coucou-shell.repo"
copr_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:mineiro:satty.repo"

if [ -e "$copr_file" ]; then
    as_root dnf copr remove -y mineiro/satty
    ok "mineiro/satty COPR removed"
fi
if ! grep metadata_expire /etc/yum.repos.d/coucou-shell.repo >/dev/null 2>&1; then
    as_root dnf config-manager addrepo --overwrite --from-repofile="$repo_url"
    ok "coucou-shell repo added"
fi

ours() { rpm -q --qf '%{RELEASE}\n' satty 2>/dev/null | grep '\.coucou' >/dev/null; }

# A satty not ours (the COPR's): replaced. A missing one is installed by
# the unit's own packages.
if rpm -q satty >/dev/null 2>&1 && ! ours; then
    as_root dnf upgrade -y --refresh satty
fi
if ours; then
    ok "satty is coucou-shell's build"
else
    warn "satty is not coucou-shell's build yet: is a release with it published?"
fi
