#!/bin/bash

# SELinux is the new default but some people prefer AppArmor
# https://code.opensuse.org/leap/features/issue/182
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
    # Offer AppArmor switch only if SELinux is NOT installed
    # So minimal or existing apparmor install, do not confuse users who are on SELinux
    # and might accidentally migrate just because they see some cool option in the tool
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

log "Installing packages: patterns-base-apparmor"
$DRYRUN zypper --non-interactive install -t pattern --force-resolution apparmor

log "Drop any SELinux boot options"
$DRYRUN update-bootloader --del-option "security=selinux"
$DRYRUN update-bootloader --del-option "enforcing=1"
$DRYRUN update-bootloader --del-option "selinux=1"
log "Adding AppArmor boot options"
$DRYRUN update-bootloader --add-option "security=apparmor"
