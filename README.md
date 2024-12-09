# openSUSE migration tool

The tool was created during [Hackweek 24](https://hackweek.opensuse.org/24/projects/new-migration-tool-for-leap).

The goal is to simplify upgrades and cross-distribution upgrades within openSUSE distributions.
It also supports migration from openSUSE Leap to SUSE Linux Enterprise.

**The tool is still experimental and is not expected to be used in production until we have a proper test suite.**

![image](https://github.com/user-attachments/assets/6c50e5f9-630b-4ead-a182-5e940376f2bf)

The tool gets information about point releases from [get.opensuse.org API](https://get.opensuse.org/api/v0/distributions.json) 
and also utilizes [openSUSE-repos](https://github.com/openSUSE/openSUSE-repos) for a cross distribution migration.
Installing openSUSE-repos from the target repo of an upgrade or migration takes away any manual tinkering of distribution repositories.

**Intended supported scenarios**
```
Leap -> Leap n+1, Leap -> SLES, Leap -> Tumbleweed, Leap -> Slowroll
Leap Micro -> Leap Micro n+1, Leap Micro -> MicroOS
Slowroll -> Tumbleweed
Tumbleweed -> Slowroll
```

**Known unsupported scenarios**

Migration from Tumbleweed (rolling) to any point release is not possible as it's effectively a downgrade.
Migration from non-immutable to immutable is generally unsupported and not recommended. 
So no option for Tumbleweed -> MicroOS either.
For such unsupported cases please do a clean install.




## License
This project uses the [Apache-2.0](http://www.apache.org/licenses/LICENSE-2.0) license.

## Testing

Please always run the tool first with --dry-run to get an overall idea of what the tool would do to your system.
I highly recommend testing the tool in a virtual machine or container via e.g. distrobox.

### Execution on a regular system such as Leap, Tumbleweed, Slowroll

```
$ sudo zypper in opensuse-migration-tool
$ opensuse-migration-tool --dry-run
$ sudo opensuse-migration-tool
$ reboot
```

### Execution on Immutable systems such as Leap Micro

```
$ sudo transactional-update shell
# Inside the shell
$ sudo zypper in opensuse-migration-tool
$ opensuse-migration-tool --dry-run
$ sudo opensuse-migration-tool
$ exit && reboot # into new snapshot
```

### Upgrading to pre-releases such as Alpha, Beta

By default the tool with **not show up** Alpha, Beta, RC releases of point releases as viable targets for upgrade/migration.
E.g. Leap Micro 6.1 Beta or Leap 16.9 Alpha.

This is on purpose. We want to ensure that nobody accidentally upgrades their system to e.g. Alpha version of an upcoming release.

The --pre-release argument does the trick, then we'll fetch information from [get.opensuse.org API](https://get.opensuse.org/api/v0/distributions.json) about all available releases which are not EOL.
Default behavior is to fetch only releases with state "Stable" which means released/supported.


```
./opensuse-migration-tool --pre-release --dry-run
sudo ./opensuse-migration-tool --pre-release

```

### Alternatively with git/distrobox (recommended for development)

Leap Micro migration can be easily developed/tested on a toolbox image. 
Just be aware that the toolbox container won't be immutable inside, so no need for transactional-update here.

Please be aware that in such a container environment there could be an issue with updating bind-mounted files such as [/etc/hostname](https://bugzilla.opensuse.org/show_bug.cgi?id=1233982).
```
$ git clone https://github.com/openSUSE/opensuse-migration-tool.git
$ cd opensuse-migration-tool
$ distrobox create --image registry.opensuse.org/opensuse/leap-micro/6.0/toolbox --name micro60
$ distrobox enter micro60
$ zypper in bc jq curl dialog sed gawk
$ ./opensuse-migration-tool --dry-run
$ sudo ./opensuse-migration-tool
```

```
$ git clone https://github.com/openSUSE/opensuse-migration-tool.git
$ cd opensuse-migration-tool
$ distrobox create --image opensuse/leap:15.5 --name leap155
$ distrobox enter leap155
$ sudo zypper in bc jq curl dialog sed gawk
$ ./opensuse-migration-tool --dry-run
$ sudo ./opensuse-migration-tool
```

## Documentation for a manual migration

These are wiki that describe the manual upgrade process with zypper dup

https://en.opensuse.org/SDB:System_upgrade

https://en.opensuse.org/SDB:How_to_migrate_to_SLE

https://en.opensuse.org/SDB:System_upgrade_to_LeapMicro_6.0

### Packaging
```
$ osc bco Base:System opensuse-migration-tool # fork Package from Base:System
$ cd Base:System/opensuse-migration-tool
$ osc service runall
$ osc addremove
$ vim *.changes # review changelog, deduplicate lines from git history etc.
$ osc build # ensure that changes build locally
$ osc commit
$ osc sr # submit changes to the Base:System
```
**Maintainer typically forwards submission from devel project to openSUSE:Factory on accept.**

If this is not the case you can submit it manually.

```
$ osc sr Base:System opensuse-migration-tool openSUSE:Factory
```

Aside from Factory we want to ensure that supported Leap Micro and Leap releases get the update too.
**Once changes are accepted in openUSSE:Factory do following.**

```
$ osc sr openSUSE:Factory opensuse-migration-tool openSUSE:Leap:Micro:6.1
$ osc sr openSUSE:Factory opensuse-migration-tool openSUSE:Leap:16.0
$ osc sr openSUSE:Factory opensuse-migration-tool openSUSE:Leap:15.6:Update
```
