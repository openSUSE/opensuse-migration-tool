#!/bin/bash
#
# Explicitly disable SELinux when no Linux Security Module was selected.
# Newer kernels enable SELinux by default if no LSM is specified, which
# breaks migrated systems without SELinux userspace installed.
#
# https://github.com/openSUSE/opensuse-migration-tool/issues/69

set -euo pipefail

# Elevated permissions check unless DRYRUN is set
if [ -z "${DRYRUN:-}" ]; then
    if [ "$EUID" -ne 0 ]; then
        exec sudo "$0" "$@"
    fi
    test -w / || {
        echo "Please run the tool inside 'transactional-update shell' on Immutable systems."
        exit 1
    }
fi

UPDATE_BOOTLOADER=$(command -v update-bootloader)

if [ -z "$UPDATE_BOOTLOADER" ]; then
    echo -e "No update-bootloader found!\n"
    exit 0
fi

log() {
    echo "[MIGRATION] $1"
}

# --check mode:
# return 0 if no LSM is configured (script should run)
# return 1 otherwise
if [[ "${1:-}" == "--check" ]]; then
    if ! $UPDATE_BOOTLOADER --get-option security | grep -Eq '(selinux|apparmor)'; then
        exit 0
    else
        exit 1
    fi
fi

log "No security module selected, explicitly disabling SELinux"

$DRYRUN update-bootloader --del-option "security=selinux"
$DRYRUN update-bootloader --del-option "enforcing=1"
$DRYRUN update-bootloader --del-option "selinux=1"
$DRYRUN update-bootloader --add-option "selinux=0"
