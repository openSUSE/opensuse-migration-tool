# migration-tool
openSUSE migration tool

!!!DO NOT USE THE TOOL IN PRODUCTION!!!

The tool was created during [Hackweek 24](https://hackweek.opensuse.org/24/projects/new-migration-tool-for-leap).
It is still experimental and is not expected to be used in production until we have a proper test suite.
It is fetching information about active point releases and pre-releases from get.opensuse.org api.

![image](https://github.com/user-attachments/assets/08926da0-14d8-4f9c-b290-b98373025087)



# License
This project is using [Apache-2.0](http://www.apache.org/licenses/LICENSE-2.0) license.

# Testing

Please always run the tool first with --dry-run to get an overall idea about what the tool would do to your system.
I highly recommend testing tool in a virtual machine or container via e.g. distrobox.



# Testing migration from Leap Micro
git clone git@github.com:openSUSE/migration-tool.git
cd migration-tool
distrobox create --image registry.opensuse.org/opensuse/leap-micro/6.0/toolbox --name micro60
distrobox enter micro60
zypper in bc jq curl dialog sed gawk
./migration-tool.sh --dry-run
sudo ./migration-tool.sh

# Migration from Leap
git clone git@github.com:openSUSE/migration-tool.git
cd migration-tool
distrobox create --image opensuse/leap:15.5 --name leap155
distrobox enter leap155
sudo zypper in bc jq curl dialog sed gawk
./migration-tool.sh --dry-run
sudo ./migration-tool.sh

# Migration / Upgrade to a pre-release e.g Leap 16.0 Alpha
./migration-tool.sh --pre-release --dry-run
sudo ./migration-tool.sh --pre-release
