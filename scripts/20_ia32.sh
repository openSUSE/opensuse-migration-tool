#!/bin/bash

# SLES 16 disables 32bit support in kernel by default
# Things like Steam, Proton, Virtualbox will need it

set -euo pipefail

log() {
    echo "[MIGRATION] $1"
}

error_exit() {
    echo "[MIGRATION][ERROR] $1" >&2
    exit 1
}

# This is used to generate dynamic list of tasks
if [[ "${1:-}" == "--check" ]]; then
    if ! rpm -q grub2-compat-ia32 &>/dev/null; then
        exit 0
    else
        exit 1
    fi
fi

log "Installing packages: grub2-compat-ia32"
if sudo zypper --non-interactive install --force-resolution grub2-compat-ia32; then
    log "Installation completed successfully."
else
    error_exit "Package installation failed. Please check zypper logs or try again manually."
fi
