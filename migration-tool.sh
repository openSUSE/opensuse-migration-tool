#!/bin/bash

#The migration-tool helps to migrate to another product mainly from 
#openSUSE.

#Copyright (C) 2024 Marcela Maslanova
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.
#

# Ensure the script is run with Bash 4.0+ for associative array support
if ! [ "${BASH_VERSION:0:1}" -ge 4 ]; then
    echo "This script requires Bash 4.0 or higher." >&2
    exit 1
fi

# Define current system type (e.g., Leap, Slowroll, etc.)
CURRENT_SYSTEM="Leap"  # Change this as needed to reflect the current system

# Define migration targets using an associative array
declare -A MIGRATION_OPTIONS

if [ "$CURRENT_SYSTEM" == "Leap" ]; then
    MIGRATION_OPTIONS=(
        ["1"]="SLES"
        ["2"]="Tumbleweed"
        ["3"]="Slowroll"
        ["4"]="Leap 16.0"
    )
elif [ "$CURRENT_SYSTEM" == "Slowroll" ]; then
    MIGRATION_OPTIONS=(
        ["2"]="Tumbleweed"
    )
else
    echo "Unsupported system type: $CURRENT_SYSTEM" >&2
    exit 1
fi

# Generate the dialog input string from the associative array
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
    2>&1 >/dev/tty)

zypper in snapper grub2-snapper-plugin

rpmsave_repo() {
for repo_file in \
repo-backports-debug-update.repo repo-oss.repo repo-backports-update.repo \
repo-sle-debug-update.repo repo-debug-non-oss.repo repo-sle-update.repo \
repo-debug.repo repo-source.repo repo-debug-update.repo repo-update.repo \
repo-debug-update-non-oss.repo repo-update-non-oss.repo repo-non-oss.repo \
download.opensuse.org-oss.repo download.opensuse.org-non-oss.repo download.opensuse.org-tumbleweed.repo \
repo-openh264.repo openSUSE-*-0.repo repo-main.repo; do
  if [ -f %{_sysconfdir}/zypp/repos.d/$repo_file ]; then
    echo "Content of $repo_file will be newly managed by zypp-services."
    echo "Storing old copy as %{_sysconfdir}/zypp/repos.d/$repo_file.rpmsave"
    mv %{_sysconfdir}/zypp/repos.d/$repo_file %{_sysconfdir}/zypp/repos.d/$repo_file.rpmsave
  fi
done
}



# Clear the screen and handle the user choice
clear
if [ "$CHOICE" == "1" ]; then
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

	zypper in suseconnect-ng
	cp SLES.prod /etc/products.d/
        rm -r /etc/products.d/baseproduct
        ln -s /etc/products.d/SLES.prod /etc/products.d/baseproduct
	rpmsave_repo
	rpm -e --nodeps openSUSE-release
	read -p "Enter your email: " email
	read -p "Enter your registration code: " code
	suseconnect -e  email -r code 
	SUSEConnect -p PackageHub/15.6/x86_64
	zypper dup --allow-vendor-change --force-resolution -y
# to tumbleweed
elif [ "$CHOICE" == "2" ]; then
        zypper ar -f -c http://download.opensuse.org/tumbleweed/repo/oss repo-oss
        zypper in openSUSE-repos-Tumbleweed
	zypper dup --allow-vendor-change --force-resolution -y
	for repo in openSUSE-Leap*.repo openSUSE\:Leap*.repo; do
        if [ -f /etc/zypp/repos.d/$repo ]; then
                mv /etc/zypp/repos.d/$repo /etc/zypp/repos.d/$repo.rpmsave
        fi
        done
# to slowroll
elif [ "$CHOICE" = "3" ]; then
        zypper addrepo https://download.opensuse.org/slowroll/repo/oss/ leap-to-slowroll
	shopt -s globstar && TMPSR=$(mktemp -d) && zypper --pkg-cache-dir=${TMPSR} download openSUSE-repos-Slowroll && zypper modifyrepo --all --disable && zypper install ${TMPSR}/**/openSUSE-repos-Slowroll*.rpm && zypper dist-upgrade
	zypper dup --allow-vendor-change --force-resolution -y
        for repo in openSUSE-Leap*.repo openSUSE\:Leap*.repo; do
        if [ -f /etc/zypp/repos.d/$repo ]; then
                mv /etc/zypp/repos.d/$repo /etc/zypp/repos.d/$repo.rpmsave
        fi
	done
# to 16.0
elif [ "$CHOICE" == "4" ]; then
        zypper ar -f -c http://download.opensuse.org/16.0/repo/oss repo-sle16
	zypper in Leap-release
fi

if [ -n "$CHOICE" ]; then
    echo "You selected: ${MIGRATION_OPTIONS[$CHOICE]}"
    echo "Now is recommended to reboot. "
else
    echo "No option selected. Exiting."
    exit 1
fi
