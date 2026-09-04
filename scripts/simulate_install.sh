#!/usr/bin/env bash
# scripts/simulate_install.sh — dry-run of install_all.sh's terminal UI and
# log format, with zero real commands (no dnf, no curl, no git, no cargo,
# nothing touches the system). Every "module" below is a stub that only
# sleeps and echoes.
#
# Use this to check the ✓/⠋/○/✗ rendering (TTY and piped-to-file), the
# summary, the exit code, and the log file's shape, whenever
# scripts/lib/status.sh changes -- without any risk to the machine it runs on.
set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_DIR/scripts/lib/status.sh"
status_init

fake_module() {
    local name="$1"
    echo "Resolving dependencies for $name..."
    sleep 0.2
    echo "Downloading $name-1.2.3.tar.gz..."
    sleep 0.2
    echo "Extracting archive..."
    sleep 0.2
    echo "Linking configuration into ~/.config/$name..."
    sleep 0.2
    echo "$name installed."
}

fake_module_failing() {
    echo "Resolving dependencies for broken..."
    sleep 0.2
    echo "Downloading broken-1.0.0.tar.gz..."
    sleep 0.2
    echo "error: 404 Not Found" >&2
    return 1
}

echo -e "${BOLD}── Modules (simulated) ──${RESET}\n"

for module in fonts bash tmux wezterm nvim wireplumber mangohud nemo; do
    run_step "$module" fake_module "$module" || true
done

skip_step "nvidia" "no NVIDIA GPU on this simulated run"
run_step "hyprland" fake_module "hyprland" || true
run_step "quickshell" fake_module_failing || true
run_step "kde" fake_module "kde" || true

status_summary
exit $?
