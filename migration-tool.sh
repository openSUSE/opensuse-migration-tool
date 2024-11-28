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
REQUIRED_TOOLS=("bc" "jq" "curl" "dialog" "sed" "gawk")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo "$tool is required but not installed."
        echo "Please run: sudo zypper in ${REQUIRED_TOOLS[*]}"
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
ARCH=$(uname -i) # x86_64 XXX: check for other arches

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
TMP_REPO_NAME="tmp-migration-tool-repo" # tmp repo to get sles-release or openSUSE-repos-*
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
        --dry-run) DRYRUN="echo Would execute: "; shift ;;
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
    echo "Unsupported system type: '$NAME'" >&2
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
    --title "[EXPERIMENTAL] System Migration - NOT FOR PRODUCTION" \
    --menu "Select the migration target:" \
    20 60 10 \
    "${DIALOG_ITEMS[@]}" \
    2>&1 >/dev/tty) || exit

rpmsave_repo() {
### XXX: This could go away if we install openSUSE-repos before migration
### It does the same thing
for repo_file in \
repo-backports-debug-update.repo repo-oss.repo repo-backports-update.repo \
repo-sle-debug-update.repo repo-debug-non-oss.repo repo-sle-update.repo \
repo-debug.repo repo-source.repo repo-debug-update.repo repo-update.repo \
repo-debug-update-non-oss.repo repo-update-non-oss.repo repo-non-oss.repo \
download.opensuse.org-oss.repo download.opensuse.org-non-oss.repo download.opensuse.org-tumbleweed.repo \
repo-openh264.repo openSUSE-*-0.repo repo-main.repo $TMP_REPO_NAME.repo; do
  if [ -f /etc/zypp/repos.d/$repo_file ]; then
    echo "Storing old copy as /etc/zypp/repos.d/$repo_file.rpmsave"
    $DRYRUN  /etc/zypp/repos.d/$repo_file /etc/zypp/repos.d/$repo_file.rpmsave
  fi
done
# regexpes
for file in /etc/zypp/repos.d/openSUSE-*.repo; do
    repo_file=$(basename $file)
    if [ -f /etc/zypp/repos.d/$repo_file ]; then
        echo "Storing old copy as /etc/zypp/repos.d/$repo_file.rpmsave"
        $DRYRUN mv /etc/zypp/repos.d/$repo_file /etc/zypp/repos.d/$repo_file.rpmsave
    fi
done
# Ensure to drop any SCC generated service/repo files for Leap
# e.g. /etc/zypp/services.d/openSUSE_Leap_15.6_x86_64.service
for file in /etc/zypp/services.d/openSUSE_*.service; do
    service_file=$(basename $file)
    if [ -f /etc/zypp/services.d/$service_file ]; then
        echo "Storing old copy as /etc/zypp/repos.d/$service_file.rpmsave"
        mv /etc/zypp/services.d/$service_file /etc/zypp/services.d/$service_file.rpmsave
    fi
done
}
# Clear the screen and handle the user choice
clear
if [[ -n $CHOICE ]]; then
    echo "Selected option: ${MIGRATION_OPTIONS[$CHOICE]}"
    case "${MIGRATION_OPTIONS[$CHOICE]}" in
        *"SUSE Linux Enterprise"*|"SLE")
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"

            SP=$(sed 's/\./-SP/' <<<"$VERSION") # VERSION from /etc/os-release 15.6 -> 15-SP6

            while true; do
                # Capture output and return code
                OUTPUT=$(dialog --clear \
                    --backtitle "SCC - Registration code" \
                    --title "SCC - Registration code" \
                    --form "\nPlease enter valid email and registration code." 25 60 16 \
                    "Email:" 1 1 "" 1 25 25 50 \
                    "Regcode:" 2 1 "" 2 25 25 50 \
                    2>&1 >/dev/tty)
                RETCODE=$?

                #echo "Dialog output: '$OUTPUT'" >&2
                #echo "Return code: $RETCODE" >&2

                # Handle cancel or escape
                if [[ $RETCODE -ne 0 ]]; then
                    dialog --clear \
                        --backtitle "SCC - Registration code" \
                        --title "Operation Cancelled" \
                        --msgbox "You have cancelled the registration process." 10 40
                    exit 1
                fi

                {
                    read -r EMAIL
                    read -r REGCODE 
                } <<< "$OUTPUT"
            
                # Check if both values are entered
                if [[ -n "$EMAIL" && -n "$REGCODE" ]]; then
                    break
                else
                    dialog --clear \
                        --backtitle "SCC - Registration code" \
                        --title "Input Error" \
                        --msgbox "Both email and registration code are required. Please try again." 10 40
                fi
            done

            # This is a dream workflow that doesn't really work. Enable BCI repo and register as SLES with BCI-release
            # Perhaps we can fix it in near future
            #$DRYRUN zypper ar -f https://updates.suse.com/SUSE/Products/SLE-BCI/$SP/$ARCH/product/ $TMP_REPO_NAME
            #$DRYRUN zypper in --force-resolution -y suseconnect-ng
            #$DRYRUN zypper in --force-resolution -y unified-installer-release SLE_BCI-release # sles-release is not in BCI

            MAJVER=$(echo $VERSION| awk -F"." '{ print $1 }') # 15
            MINVER=$(echo $VERSION| awk -F"." '{ print $2 }') # 6
            echo $REGCODE
            $DRYRUN zypper in -y suseconnect-ng snapper grub2-snapper-plugin
            # Backup /etc/os-release before release package removal
            echo "Backing up /etc/os-release as /etc/os-release.backup"
            $DRYRUN cp /etc/os-release /etc/os-release.backup
            $DRYRUN rpm -e --nodeps openSUSE-release
            $DRYRUN rpm -e --nodeps openSUSE-repos
             # Backup the release
            echo "Backing up /etc/os-release as /etc/os-release.backup"
            $DRYRUN cp /etc/os-release /etc/os-release.backup
            if [ -z "$DRYRUN" ]; then
                cat > /etc/os-release  << EOL
NAME="SLES" 
VERSION="$SP" 
VERSION_ID="$VERSION"
PRETTY_NAME="SUSE Linux Enterprise Server $MAJVER SP$MINVER"
ID="sles"
ID_LIKE="suse"
ANSI_COLOR="0;32" 
CPE_NAME="cpe:/o:suse:sles:$MAJVER:sp$MINVER"
DOCUMENTATION_URL="https://documentation.suse.com/"
EOL
            else
                echo "Would write a SLES $SP like /etc/os-release"
            fi

	        $DRYRUN cp SLES.prod /etc/products.d/
            $DRYRUN rm -r /etc/products.d/baseproduct
            $DRYRUN ln -s /etc/products.d/SLES.prod /etc/products.d/baseproduct
            if [ -z "$DRYRUN" ]; then
                rpmsave_repo # invalidates all standard openSUSE repos
            fi

	        $DRYRUN suseconnect -e  $EMAIL -r $REGCODE 
	        $DRYRUN SUSEConnect -p PackageHub/$VERSION/$ARCH

            $DRYRUN zypper dup -y --force-resolution --allow-vendor-change --download in-advance
            if [ $? -ne 0 ]; then # re-run zypper dup as interactive in case of failure in non-interactive mode
                $DRYRUN zypper dup --force-resolution --allow-vendor-change --download in-advance 
            fi


            $DRYRUN rpm -e --nodeps branding-openSUSE grub2-branding-openSUSE wallpaper-branding-openSUSE plymouth-branding-openSUSE systemd-presets-branding-openSUSE systemd-presets-branding-MicroOS
	        $DRYRUN zypper remove -y opensuse-welcome # might not be present on text-installations
	        $DRYRUN zypper in -y branding-SLE-15 grub2-branding-SLE wallpaper-branding-SLE-15 plymouth-branding-SLE systemd-presets-branding-SLE
            ;;
        "openSUSE Tumbleweed")
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            # https://download.opensuse.org/ports/ # for other arches
            REPOURL="https://download.opensuse.org/tumbleweed/repo/oss/"
            if [ "$ARCH" != "x86_64" ]; then
                REPOURL=https://download.opensuse.org/ports/$ARCH # XXX this will likely work only for aarch64
                if [ "$ARCH" != "aarch64" ]; then 
                    # Let's not messup any systems and make sure this is properly implemented first
                    echo "Unsupported arch '$ARCH'."
                    echo "Please open an issue at https://github.com/openSUSE/migration-tool/issues"
                    echo "Make sure to add output of 'uname -i' and content of your /etc/os-release into the ticket."
                    exit 1
                fi
            fi
            $DRYRUN zypper addrepo -f $REPOURL $TMP_REPO_NAME
            $DRYRUN zypper in -y --from $TMP_REPO_NAME openSUSE-repos-Leap # install repos from the nextrelease
            $DRYRUN zypper removerepo $TMP_REPO_NAME # drop the temp repo, we have now definitions of all repos we need
            $DRYRUN zypper refs # !Important! make sure that all repo files under index service were regenerated
            
            $DRYRUN zypper dup -y --force-resolution --allow-vendor-change --download in-advance
            if [ $? -ne 0 ]; then # re-run zypper dup as interactive in case of failure in non-interactive mode
                $DRYRUN zypper dup --force-resolution --allow-vendor-change --download in-advance 
            fi

            ;;
        "openSUSE Tumbleweed-Slowroll")
            $DRYRUN echo "Migrating to ${MIGRATION_OPTIONS[$CHOICE]}"
            REPOURL="https://download.opensuse.org/slowroll/repo/oss/"
            if [ "$ARCH" != "x86_64" ]; then
                echo "Unsupported arch '$ARCH' by Slowroll."
                exit 1
            fi
            $DRYRUN zypper addrepo -f $REPOURL $TMP_REPO_NAME
            $DRYRUN zypper in -y --from $TMP_REPO_NAME openSUSE-repos-Leap # install repos from the nextrelease
            $DRYRUN zypper removerepo $TMP_REPO_NAME # drop the temp repo, we have now definitions of all repos we need
            $DRYRUN zypper refs # !Important! make sure that all repo files under index service were regenerated
            
            $DRYRUN zypper dup -y --force-resolution --allow-vendor-change --download in-advance
            if [ $? -ne 0 ]; then # re-run zypper dup as interactive in case of failure in non-interactive mode
                $DRYRUN zypper dup --force-resolution --allow-vendor-change --download in-advance 
            fi
            ;;
        *"openSUSE LeapMicro"*)
            # Has to be before Leap*
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            TARGET_VER=`echo ${MIGRATION_OPTIONS[$CHOICE]} | awk '{ print $NF }'`
            $DRYRUN zypper addrepo -f https://download.opensuse.org/distribution/leap-micro/$TARGET_VER/product/repo/openSUSE-Leap-Micro-$TARGET_VER-$ARCH/ $TMP_REPO_NAME
            $DRYRUN zypper in -y --from $TMP_REPO_NAME openSUSE-repos-LeapMicro # install repos from the nextrelease
            $DRYRUN zypper removerepo $TMP_REPO_NAME # drop the temp repo, we have now definitions of all repos we need
            $DRYRUN zypper refs # !Important! make sure that all repo files under index service were regenerated

            $DRYRUN zypper --releasever $TARGET_VER dup -y --force-resolution --allow-vendor-change --download in-advance
            if [ $? -ne 0 ]; then # re-run zypper dup as interactive in case of failure in non-interactive mode
                $DRYRUN zypper --releasever $TARGET_VER dup --force-resolution --allow-vendor-change --download in-advance 
            fi
            ;;
        *"openSUSE Leap"*)
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            TARGET_VER=`echo ${MIGRATION_OPTIONS[$CHOICE]} | awk '{ print $NF }'`
            $DRYRUN zypper addrepo -f https://download.opensuse.org/distribution/leap/$TARGET_VER/repo/oss/repodata/ $TMP_REPO_NAME
            $DRYRUN zypper in -y --from $TMP_REPO_NAME openSUSE-repos-Leap # install repos from the nextrelease
            $DRYRUN zypper removerepo $TMP_REPO_NAME # drop the temp repo, we have now definitions of all repos we need
            $DRYRUN zypper refs # !Important! make sure that all repo files under index service were regenerated

            $DRYRUN zypper --releasever $TARGET_VER dup -y --force-resolution --allow-vendor-change --download in-advance
            if [ $? -ne 0 ]; then # re-run zypper dup as interactive in case of failure in non-interactive mode
                $DRYRUN zypper --releasever $TARGET_VER dup --force-resolution --allow-vendor-change --download in-advance
            fi
            ;;
        *"MicroOS"*)
            $DRYRUN echo "Upgrading to ${MIGRATION_OPTIONS[$CHOICE]}"
            # https://download.opensuse.org/ports/ # for other arches
            REPOURL="https://download.opensuse.org/tumbleweed/repo/oss/"
            if [ "$ARCH" != "x86_64" ]; then
                REPOURL=https://download.opensuse.org/ports/$ARCH # XXX this will likely work only for aarch64
                if [ "$ARCH" != "aarch64" ]; then 
                    # Let's not messup any systems and make sure this is properly implemented first
                    echo "Unsupported arch '$ARCH'."
                    echo "Please open an issue at https://github.com/openSUSE/migration-tool/issues"
                    echo "Make sure to add output of 'uname -i' and content of your /etc/os-release into the ticket."
                    exit 1
                fi
            fi
            $DRYRUN zypper addrepo -f $REPOURL $TMP_REPO_NAME
            $DRYRUN zypper in -y --from $TMP_REPO_NAME openSUSE-repos-MicroOS # install repos from the nextrelease
            $DRYRUN zypper removerepo $TMP_REPO_NAME # drop the temp repo, we have now definitions of all repos we need
            $DRYRUN zypper refs # !Important! make sure that all repo files under index service were regenerated
            
            $DRYRUN zypper dup -y --force-resolution --allow-vendor-change --download in-advance
            if [ $? -ne 0 ]; then # re-run zypper dup as interactive in case of failure in non-interactive mode
                $DRYRUN zypper dup --force-resolution --allow-vendor-change --download in-advance 
            fi
            ;;
    esac
else
    echo "No option selected. Exiting."
    exit 1
fi

#dialog --clear \
#    --backtitle "[EXPERIMENTAL] Migration tool" \
#    --title "Migration process completed" \
#    --msgbox "\nMigration process completed.\nA reboot is recommended." 10 40
#
echo "Migration process completed. A reboot is recommended."