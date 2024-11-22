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

# Get terminal dimensions
read -r term_width term_height < <(stty size)

# Calculate dialog box dimensions with padding
border=2
dialog_width=$((term_width - 2 * border))
dialog_height=$((term_height - 2 * border))

# Ensure minimum dimensions for dialog box
dialog_width=$((dialog_width < 20 ? 20 : dialog_width))
dialog_height=$((dialog_height < 10 ? 10 : dialog_height))

# Display a dialog with calculated size
dialog --title "Dynamic Sizing Example" \
       --msgbox "This dialog adjusts to your terminal size." \
       "$dialog_height" "$dialog_width"

# Display the dialog menu
CHOICE=$(dialog --clear \
    --title "System Migration" \
    --menu "Select the migration target:" \
    $dialog_width $dialog_height 100 \
    "${DIALOG_ITEMS[@]}" \
    2>&1 >/dev/tty) || exit

zypper in snapper grub2-snapper-plugin

rpmsave_repo() {
for repo_file in \
repo-backports-debug-update.repo repo-oss.repo repo-backports-update.repo \
repo-sle-debug-update.repo repo-debug-non-oss.repo repo-sle-update.repo \
repo-debug.repo repo-source.repo repo-debug-update.repo repo-update.repo \
repo-debug-update-non-oss.repo repo-update-non-oss.repo repo-non-oss.repo \
download.opensuse.org-oss.repo download.opensuse.org-non-oss.repo download.opensuse.org-tumbleweed.repo \
repo-openh264.repo openSUSE-*.repo repo-main.repo; do
  if [ -f /etc/zypp/repos.d/$repo_file ]; then
    echo "Content of $repo_file will be newly managed by zypp-services."
    echo "Storing old copy as /etc/zypp/repos.d/$repo_file.rpmsave"
    mv /etc/zypp/repos.d/$repo_file /etc/zypp/repos.d/$repo_file.rpmsave
  fi
done
}

# Clear the screen and handle the user choice
clear
if [[ -n $CHOICE ]]; then
    echo "Selected option: ${MIGRATION_OPTIONS[$CHOICE]}"
    case "${MIGRATION_OPTIONS[$CHOICE]}" in
        *"SUSE Linux Enterprise"*)
cat > /etc/os-release  << EOL
NAME="SLES" 
VERSION="15-SP6" 
VERSION_ID="15.6"
PRETTY_NAME="SUSE Linux Enterprise Server 15 SP6"
ID="sles"
ID_LIKE="suse"
ANSI_COLOR="0;32" 
CPE_NAME="cpe:/o:suse:sles:15:sp6"
DOCUMENTATION_URL="https://documentation.suse.com/"
EOL

            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            zypper in suseconnect-ng
            cp SLES.prod /etc/products.d/
            rm -r /etc/products.d/baseproduct
            ln -s /etc/products.d/SLES.prod /etc/products.d/baseproduct
            rpmsave_repo
            rpm -e --nodeps openSUSE-release
            suseconnect -e marcela.maslanova@suse.com -r INTERNAL-USE-ONLY-2746-dfc5
            suseconnect -e  email -r code 
            SUSEConnect -p PackageHub/15.6/x86_64
            zypper dup --allow-vendor-change --force-resolution -y
            ;;
        "openSUSE Tumbleweed")
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            zypper ar -f -c http://download.opensuse.org/tumbleweed/repo/oss to-tumbleweed
            zypper in openSUSE-repos-Tumbleweed && rpm -e --nodeps openSUSE-repos-Slowroll
            zypper dup --allow-vendor-change --force-resolution -y
            for repo in openSUSE-Leap*.repo openSUSE\:Leap*.repo; do
                if [ -f /etc/zypp/repos.d/$repo ]; then
                    mv /etc/zypp/repos.d/$repo /etc/zypp/repos.d/$repo.rpmsave
                fi
            done
            ;;
        "openSUSE Tumbleweed-Slowroll")
            $DRYRUN echo "Migrating to ${MIGRATION_OPTIONS[$CHOICE]}"
            zypper addrepo https://download.opensuse.org/slowroll/repo/oss/ leap-to-slowroll
            shopt -s globstar && TMPSR=$(mktemp -d) && zypper --pkg-cache-dir=${TMPSR} download openSUSE-repos-Slowroll && \
                zypper modifyrepo --all --disable && zypper install ${TMPSR}/**/openSUSE-repos-Slowroll*.rpm && zypper dist-upgrade
            zypper dup --allow-vendor-change --force-resolution -y
            for repo in openSUSE-Leap*.repo openSUSE\:Leap*.repo; do
                if [ -f /etc/zypp/repos.d/$repo ]; then
                    mv /etc/zypp/repos.d/$repo /etc/zypp/repos.d/$repo.rpmsave
                fi
            done
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
