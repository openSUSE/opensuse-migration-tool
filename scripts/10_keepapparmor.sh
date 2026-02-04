#!/bin/bash

# SELinux is the new default but some people prefer AppArmor
# https://code.opensuse.org/leap/features/issue/182
# https://en.opensuse.org/SDB:AppArmor#Switching_from_SELinux_to_AppArmor_for_Leap_16.0_and_Tumbleweed

set -euo pipefail

# Elevated permissions check unless DRYRUN is set
if [ -z "${DRYRUN:-}" ]; then
    if [ "$EUID" -ne 0 ]; then
        exec sudo "$0" "$@"
    fi
        # Requires elevated permissions or test will always fail
        test -w / || { echo "Please run the tool inside 'transactional-update shell' on Immutable systems."; exit 1; }
fi

UPDATE_BOOTLOADER=$(command -v update-bootloader)

if [ -z "$UPDATE_BOOTLOADER" ]; then
    # It was not found in the PATH; this is a critical dependency.
    echo -e "No update-bootloader found in PATH. Exiting.\n" >&2
    exit 1
fi

log() {
    echo "[MIGRATION] $1"
}

error_exit() {
    echo "[MIGRATION][ERROR] $1" >&2
    exit 1
}

# Ensure update-bootloader is available (Leap 16+)
if ! command -v update-bootloader >/dev/null 2>&1; then
    log "update-bootloader not found, installing it"
    $DRYRUN zypper --non-interactive install --force-resolution update-bootloader \
        || error_exit "Failed to install update-bootloader"
fi

# Check if we have security=apparmor as boot param
if [[ "${1:-}" == "--check" ]]; then
    if ! $UPDATE_BOOTLOADER --get-option security | grep apparmor &>/dev/null; then
        exit 0
    else
        exit 1
    fi
fi

log "Drop any SELinux boot options"
$DRYRUN update-bootloader --del-option "security=selinux"
$DRYRUN update-bootloader --del-option "enforcing=1"
$DRYRUN update-bootloader --del-option "selinux=1"
log "Adding AppArmor boot options"
$DRYRUN update-bootloader --add-option "security=apparmor"

if rpm -q patterns-base-apparmor &>/dev/null; then
    log "Package patterns-base-apparmor is already installed. Skipping."
    exit 0

else
    log "Installing packages: patterns-base-apparmor"
    if $DRYRUN zypper --non-interactive install --force-resolution patterns-base-apparmor; then
        log "Installation completed successfully."
    else
        error_exit "Package installation failed. Please check zypper logs or try again manually."
    fi
fi
