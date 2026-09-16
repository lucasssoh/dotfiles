#!/usr/bin/env bash
# rust.sh — build the repo's Rust binaries, and skip the build when nothing
# changed.
#
# What this replaces, repeated three times in config/hyprland/install.sh:
#
#     BALISE_BUILD="$HOME/.cache/balise-build"
#     rm -rf "$BALISE_BUILD"; mkdir -p "$BALISE_BUILD"
#     cp -r "$REPO_DIR/balise-src/." "$BALISE_BUILD/"
#     (cd "$BALISE_BUILD" && cargo build --release)
#
# Three defects compounded there:
#
#   1. `rm -rf` destroyed cargo's fingerprint database, so its incremental
#      engine -- which is excellent, and tracks per-unit feature sets,
#      rustflags, env vars and dep-graph edges -- never once got to fire.
#   2. `cp -r` dragged balise-src/target/ along: 563 MB of stale artifacts
#      copied into the cache dir immediately before being made useless.
#   3. `cp -r` does not preserve mtimes, so even artifacts that survived
#      would have been considered dirty anyway.
#
# Net effect: ~460 crate compilations with full LTO (opt-level 3, lto = true
# in all three crates), three separate gtk4 binding builds, on EVERY run of
# `./install user`. Plus ~2 GB of duplicated build trees on disk.
#
# The fix is mostly subtraction: build in place, keep one target dir, and let
# cargo do the incremental work it was always capable of.

[ -n "${_RUST_SH_LOADED:-}" ] && return 0
_RUST_SH_LOADED=1

_rust_lib_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=./state.sh
. "$_rust_lib_dir/state.sh"
# shellcheck source=./changes.sh
. "$_rust_lib_dir/changes.sh"

# One target dir shared by all three crates. They overlap substantially
# (gtk4, gtk4-layer-shell, serde, toml appear in two or three of them) and
# cargo namespaces artifacts by a metadata hash covering package identity and
# feature set, so sharing is safe and lets them reuse compiled dependencies.
#
# Out of the repo rather than each crate's own target/: an in-tree build would
# put ~1.5 GB inside the dotfiles, and config/hyprland/install.sh runs
# `find "$REPO_DIR" -type f -name "*.sh" -exec chmod +x {} +` which would then
# walk all of it.
: "${CARGO_TARGET_ROOT:=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/cargo-target}"

# The build dirs this replaces, removed by `cc-pkg-mng clean --cargo`.
RUST_LEGACY_BUILD_DIRS=(
    "$HOME/.cache/balise-build"
    "$HOME/.cache/prisme-build"
    "$HOME/.cache/roue-build"
)

# Every Rust crate in this repo: name -> "<dir relative to repo root> <binary>…"
#
# One table, two consumers: `cc-pkg-mng build` walks it, and
# config/hyprland/install.sh calls rust_build per crate so it keeps its own
# section() narration explaining what each binary is for. A crate added here
# and nowhere else is still built by the CLI.
#
# Note prisme produces TWO binaries from one `cargo build`: wallpaper-filter
# lives in prisme-src/src/bin/ and is the native worker behind the "Filtered"
# wallpaper cache.
declare -A RUST_CRATES=(
    [balise]="config/hyprland/balise-src balise"
    [prisme]="config/hyprland/prisme-src prisme wallpaper-filter"
    [roue]="config/hyprland/roue-src roue"
)
RUST_CRATE_ORDER=(balise prisme roue)

# Fall back to plain echo when the caller has no narration helpers of its own
# (every config/*/install.sh defines info/ok/warn; a bare `bash -c` may not).
_rust_info() { if declare -F info >/dev/null; then info "$@"; else echo "[INFO]  $*"; fi; }
_rust_ok()   { if declare -F ok   >/dev/null; then ok   "$@"; else echo "[ OK ]  $*"; fi; }
_rust_warn() { if declare -F warn >/dev/null; then warn "$@"; else echo "[WARN]  $*" >&2; fi; }

_rust_bins_present() {
    local b
    for b in "$@"; do
        [ -x "$HOME/.local/bin/$b" ] || return 1
    done
    return 0
}

# rust_build <crate-dir> <binary> [binary...]
#
# <crate-dir> is absolute, or relative to the repo root. Returns 0 when the
# binaries are present and current -- whether or not anything was compiled --
# and 1 only when a build was needed and failed.
rust_build() {
    local dir="$1"; shift
    local name src
    name="$(basename "$dir")"; name="${name%-src}"

    case "$dir" in
        /*) src="$dir" ;;
        *)  src="$(dotfiles_root)/$dir" ;;
    esac

    if [ ! -f "$src/Cargo.toml" ]; then
        _rust_warn "$name: no Cargo.toml at $src — skipping."
        return 1
    fi
    if ! command -v cargo >/dev/null 2>&1; then
        _rust_warn "$name: cargo not found — skipping the build. Install a Rust toolchain and re-run."
        return 0
    fi

    # The staleness key is the source fingerprint AND the toolchain version: a
    # cargo upgrade invalidates every artifact, and a key that ignored it would
    # happily report "up to date" against binaries built by a compiler that is
    # no longer installed.
    #
    # This key only decides whether to INVOKE cargo. It is not a substitute for
    # cargo's own dependency tracking, which stays authoritative for what
    # actually gets recompiled once we do call it.
    local key
    key="$(fp_path "$src")|$(cargo --version 2>/dev/null)"

    if [ "${RUST_FORCE:-0}" != 1 ] \
       && [ "$(state_get "crate.$name.key")" = "$key" ] \
       && _rust_bins_present "$@"; then
        _rust_info "$name: up to date (no source change)."
        return 0
    fi

    _rust_info "$name: building…"
    if ! ( cd "$src" && CARGO_TARGET_DIR="$CARGO_TARGET_ROOT" cargo build --release ); then
        # No state is recorded on failure, so the next run retries. The
        # previously installed binary is deliberately left alone: a broken
        # build should not also take away the working tool you had.
        _rust_warn "$name: build failed — the previously installed binary (if any) is left in place."
        return 1
    fi

    mkdir -p "$HOME/.local/bin"
    local b
    for b in "$@"; do
        if [ ! -f "$CARGO_TARGET_ROOT/release/$b" ]; then
            _rust_warn "$name: built, but $CARGO_TARGET_ROOT/release/$b is missing — is the [[bin]] name right?"
            return 1
        fi
        install -Dm755 "$CARGO_TARGET_ROOT/release/$b" "$HOME/.local/bin/$b"
    done

    state_set "crate.$name.key" "$key"
    state_set "crate.$name.built" "$(date -Iseconds)"
    state_save

    _rust_ok "$name: built and installed ($*) to ~/.local/bin."
    return 0
}
