#!/bin/bash

# Migration-tool: Helps migrate to another product, mainly from openSUSE.
# 
# Copyright 2024 Marcela Maslanova, SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#set -x
#set -euo pipefail

# Trap to clean up on exit or interruption
#trap 'clear; tput cnorm' EXIT INT TERM

# Ensure required tools are installed
REQUIRED_TOOLS=("bc" "jq" "curl" "dialog")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo "$tool is required but not installed. Please run: sudo zypper in $tool"
        exit 1
    fi
done

# Ensure Bash version is 4.0+
if ((BASH_VERSINFO[0] < 4)); then
    echo "This script requires Bash 4.0 or higher." >&2
    exit 1
fi

# Ensure /etc/os-release exists
if [[ ! -f /etc/os-release ]]; then
    echo "File /etc/os-release not found." >&2
    exit 2
fi

# Source OS release info
source /etc/os-release

# Fetch distribution data from API
API_URL="https://get.opensuse.org/api/v0/distributions.json"
API_DATA=$(curl -s "$API_URL")
if [ $? != 0 ]; then
    echo "Network error: Unable to fetch release data from https://get.opensuse.org/api/v0/distributions.json"
    echo "Ensure that you have working network connectivity and get.opensuse.org is accessible."
    exit 3
fi

DRYRUN=""
PRERELEASE=""

# Initialize MIGRATION_OPTIONS as an empty associative array
declare -A MIGRATION_OPTIONS=()
CURRENT_INDEX=1

# Parse command-line arguments
function print_help() {
    echo "Usage: migration-tool [--pre-release] [--dry-run] [--help]"
    echo "  --pre-release  Include pre-release versions in the migration options."
    echo "  --dry-run      Show commands without executing them."
    echo "  --help         Show this help message and exit."
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --pre-release) PRERELEASE="YES"; shift ;;
        --dry-run) DRYRUN="echo"; shift ;;
        --help) print_help ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Populate migration options
function fetch_versions() {
    local filter="$1"
    local key="$2"
    jq -r ".${key}[] | select(${filter}) | .version" <<<"$API_DATA"
}

function populate_options() {
    local key="$1"
    local current_version="$2"
    local filter="$3"
    local versions

    versions=$(fetch_versions "$filter" "$key")
    while IFS= read -r version; do
        if (( $(bc <<<"$current_version < $version") )); then
            MIGRATION_OPTIONS["$CURRENT_INDEX"]="openSUSE $key $version"
            ((CURRENT_INDEX++))
        fi
    done <<<"$versions"
}

# System-specific options
if [[ "$NAME" == "openSUSE Leap Micro" ]]; then
    MIGRATION_OPTIONS["$CURRENT_INDEX"]="MicroOS"
    ((CURRENT_INDEX++))
    if [[ $PRERELEASE ]]; then
        populate_options "LeapMicro" "$VERSION" '.state!="EOL"'
    else
        populate_options "LeapMicro" "$VERSION" '.state=="Stable"'
    fi
elif [[ "$NAME" == "openSUSE Leap" ]]; then
    MIGRATION_OPTIONS["$CURRENT_INDEX"]="SUSE Linux Enterprise $(sed 's/\./ SP/' <<<"$VERSION")"
    ((CURRENT_INDEX++))
    MIGRATION_OPTIONS["$CURRENT_INDEX"]="openSUSE Tumbleweed"
    ((CURRENT_INDEX++))
    MIGRATION_OPTIONS["$CURRENT_INDEX"]="openSUSE Tumbleweed-Slowroll"
    ((CURRENT_INDEX++))
    if [[ $PRERELEASE ]]; then
        populate_options "Leap" "$VERSION" '.state!="EOL"'
    else
        populate_options "Leap" "$VERSION" '.state=="Stable"'
    fi
elif [[ "$NAME" == "openSUSE Tumbleweed-Slowroll" ]]; then
    MIGRATION_OPTIONS["$CURRENT_INDEX"]="openSUSE Tumbleweed"
    ((CURRENT_INDEX++))
else
    echo "Unsupported system type: $NAME" >&2
    exit 1
fi

# Display migration options
if [[ ${#MIGRATION_OPTIONS[@]} -eq 0 ]]; then
    echo "No migration options available."
    exit 1
fi

# Prepare dialog items
DIALOG_ITEMS=()
for key in "${!MIGRATION_OPTIONS[@]}"; do
    DIALOG_ITEMS+=("$key" "${MIGRATION_OPTIONS[$key]}")
done

# Display dialog and get choice
CHOICE=$(dialog --clear \
    --title "System Migration" \
    --menu "Select the migration target:" \
    20 60 10 \
    "${DIALOG_ITEMS[@]}" \
    2>&1 >/dev/tty) || exit

# Handle user choice
clear
if [[ -n $CHOICE ]]; then
    echo "Selected option: ${MIGRATION_OPTIONS[$CHOICE]}"
    case "${MIGRATION_OPTIONS[$CHOICE]}" in
        *"SUSE Linux Enterprise"*)
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            ;;
        "openSUSE Tumbleweed")
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            ;;
        "openSUSE Tumbleweed-Slowroll")
            $DRYRUN echo "Migrating to ${MIGRATION_OPTIONS[$CHOICE]}"
            ;;
        *"openSUSE Leap"*)
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            ;;
        *"openSUSE Leap Micro"*)
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            ;;
        *"MicroOS"*)
            $DRYRUN echo "Migrating to openSUSE MicroOS..."
            ;;
    esac
else
    echo "No option selected. Exiting."
    exit 1
fi

echo "Migration process completed. A reboot is recommended."
