#!/bin/bash

# SELinux is the new default manual switch
# might be needed for people migrating from 15.X

# https://en.opensuse.org/SDB:AppArmor#Switching_from_SELinux_to_AppArmor_for_Leap_16.0_and_Tumbleweed

# Elevated permissions check unless DRYRUN is set
if [ -z "${DRYRUN:-}" ]; then
    if [ "$EUID" -ne 0 ]; then
        exec sudo "$0" "$@"
    fi
        # Requires elevated permissions or test will always fail
        test -w / || { echo "Please run the tool inside 'transactional-update shell' on Immutable systems."; exit 1; }
fi  

log() {
    echo "[MIGRATION] $1"
}

error_exit() {
    echo "[MIGRATION][ERROR] $1" >&2
    exit 1
}

if [[ "${1:-}" == "--check" ]]; then
    # Offer the option only if SELinux base pattern isn't installed yet
    if rpm -q patterns-base-selinux >/dev/null 2>&1; then
      exit 1
    else
      exit 0
    fi
fi

# Ensure update-bootloader is available (Leap 16+)
if ! command -v update-bootloader >/dev/null 2>&1; then
    log "update-bootloader not found, installing it"
    $DRYRUN zypper --non-interactive install --force-resolution update-bootloader \
        || error_exit "Failed to install update-bootloader"
fi

if rpm -q patterns-base-apparmor &>/dev/null; then
    log "Uninstalling packages: patterns-base-apparmor"
    if $DRYRUN zypper --non-interactive remove --force-resolution patterns-base-apparmor; then
        log "Uninstallation of AppArmor completed successfully."
    else
        error_exit "Package uninstallation failed. Please check zypper logs or try again manually."
    fi
fi
# user said he wants SElinux, so install SElinux pattern
log "Installing packages: patterns-base-selinux"
$DRYRUN zypper --non-interactive install -t pattern --force-resolution selinux

log "Drop AppArmor boot options"
$DRYRUN update-bootloader --del-option "security=apparmor"

log "Add any SELinux boot options"
$DRYRUN update-bootloader --add-option "security=selinux"
$DRYRUN update-bootloader --add-option "enforcing=1"
$DRYRUN update-bootloader --add-option "selinux=1"