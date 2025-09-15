# 🛍️ openSUSE Migration Tool

&#x20;  &#x20;

A command-line tool to **simplify upgrades and migrations** across openSUSE distributions — including *Leap*, *Tumbleweed*, *Slowroll*, and even migrations from **Leap to SLE**.

> 🗪 **Experimental** — Use with caution until a complete test suite is implemented.

---
<img width="1443" height="910" alt="image" src="https://github.com/user-attachments/assets/e7a37163-88a5-4de0-8e05-d8f543a3f61b" />

## 🌟 Key Features

👉 **Upgrade to pre-releases such as Leap 16.0 Beta**
👉 **Migration across various openSUSE distributions**
👉 **Migration to SUSE Linux Enterprise products**
👉 **Integrates get.opensuse.org product API + openSUSE-repos**
👉 **Dry-run mode for safe previews**
👉 **Support for immutable systems (Leap Micro)**
👉 **Disabling 3rd party repos prior to migration**

---

## 🔄 Supported Migration Paths

```
Leap           → Leap n+1, SLES, Tumbleweed, Slowroll
Leap Micro     → Leap Micro n+1, MicroOS
Slowroll       → Tumbleweed
Tumbleweed     → Slowroll
```

⚠️ **Unsupported or discouraged paths**:

* Tumbleweed → Leap (downgrade, not supported)
* Tumbleweed → MicroOS (immutable shift)
* Non-immutable → Immutable (generally unsupported)

---

## 📜 License

This project is licensed under the [Apache-2.0 License](http://www.apache.org/licenses/LICENSE-2.0). 👐

---

## 🧪 Quick Start: Testing the Tool

> Always use `--dry-run` first to preview planned changes!

### 🔧 On regular systems (Leap, Tumbleweed, Slowroll)

```bash
sudo zypper in opensuse-migration-tool
opensuse-migration-tool --dry-run
sudo opensuse-migration-tool
reboot
```

---

### 💨 On immutable systems (Leap Micro)

```bash
sudo transactional-update shell
# Inside shell:
zypper in opensuse-migration-tool
opensuse-migration-tool --dry-run
sudo opensuse-migration-tool
exit && reboot  # boot into new snapshot
```

---

### 🚧 Upgrading to Alpha/Beta/RC Releases

By default, **pre-release versions are hidden** to avoid accidental installs.

Use `--pre-release` to opt-in:

```bash
./opensuse-migration-tool --pre-release --dry-run
sudo ./opensuse-migration-tool --pre-release
```

---

## 🐳 Development & Testing in Distrobox (Recommended)

### Leap Micro inside Toolbox container

```bash
git clone https://github.com/openSUSE/opensuse-migration-tool.git
cd opensuse-migration-tool

distrobox create --image registry.opensuse.org/opensuse/leap-micro/6.0/toolbox --name micro60
distrobox enter micro60

zypper in bc jq curl dialog sed gawk
./opensuse-migration-tool --dry-run
sudo ./opensuse-migration-tool
```

### Leap 15.5 container

```bash
distrobox create --image opensuse/leap:15.5 --name leap155
distrobox enter leap155

sudo zypper in bc jq curl dialog sed gawk
./opensuse-migration-tool --dry-run
sudo ./opensuse-migration-tool
```

⚠️ **Heads-up:** Toolbox environments are not truly immutable and may exhibit issues (e.g. bind-mounted `/etc/hostname` — [bug 1233982](https://bugzilla.opensuse.org/show_bug.cgi?id=1233982)).

---

## 📋 Manual Migration Resources

For traditional `zypper dup` approaches:

* 🔗 [System Upgrade (Leap)](https://en.opensuse.org/SDB:System_upgrade)
* 🔗 [Leap → SLE Migration Guide](https://en.opensuse.org/SDB:How_to_migrate_to_SLE)
* 🔗 [Leap Micro Upgrade](https://en.opensuse.org/SDB:System_upgrade_to_LeapMicro_6.0)

---

## 📦 Packaging & Submitting to openSUSE

### Working on the package (Base\:System)

```bash
osc bco Base:System opensuse-migration-tool
cd Base:System/opensuse-migration-tool

osc service runall
osc addremove
vim *.changes     # Review changelog
osc build         # Test build locally
osc commit
osc sr            # Submit to Base:System
```

### Forwarding to openSUSE\:Factory

If not done by the maintainer:

```bash
osc sr Base:System opensuse-migration-tool openSUSE:Factory
```

### Submitting to Leap and Leap Micro

After Factory acceptance:

```bash
osc sr openSUSE:Factory opensuse-migration-tool openSUSE:Leap:Micro:6.1
osc sr openSUSE:Factory opensuse-migration-tool openSUSE:Leap:16.0
osc sr openSUSE:Factory opensuse-migration-tool openSUSE:Leap:15.6:Update
```

---

## 🤝 Contributions Welcome!

We're happy to receive PRs, testing reports, or feedback on supported scenarios.
Please open issues or pull requests on GitHub.
