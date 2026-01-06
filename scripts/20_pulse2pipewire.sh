#!/bin/bash

# Pipewire is the new default in Leap 16.0+
# https://code.opensuse.org/leap/features/issue/140
# https://en.opensuse.org/openSUSE:Pipewire#Installation

set -euo pipefail

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

# This is used to generate dynamic list of tasks
if [[ "${1:-}" == "--check" ]]; then
    if rpm -q pulseaudio &>/dev/null && zypper se -x pipewire-pulseaudio &>/dev/null; then
        exit 0
    else
        exit 1
    fi
fi

log "Starting PulseAudio to PipeWire migration..."

# Check if pipewire-pulseaudio is already installed
if rpm -q pipewire-pulseaudio >/dev/null 2>&1; then
    log "Package pipewire-pulseaudio is already installed. Skipping."
    exit 0
fi

# Check if pulseaudio was ever installed
if ! rpm -q pulseaudio >/dev/null 2>&1; then
    log "Package pulseaudio is not installed. Assuming minimal system. Skipping."
    exit 0
fi

log "Installing packages: pipewire-pulseaudio and ensure wireplumber-video-only-profile is removed"
if $DRYRUN zypper --non-interactive install --force-resolution pipewire-pulseaudio -wireplumber-video-only-profile; then
    log "Migration completed successfully."
else
    error_exit "Package installation failed. Please check zypper logs or try again manually."
fi
