# Codebase Guide

This document explains the structure of the ubuntu-rockchip repository, the technologies it relies on, and how all the pieces fit together. It is intended for contributors and developers who want to understand, extend, or debug the build system.

---

## Table of Contents

1. [What This Repository Does](#what-this-repository-does)
2. [Repository Layout](#repository-layout)
3. [Key Technologies](#key-technologies)
4. [Configuration System](#configuration-system)
5. [Build Pipeline](#build-pipeline)
6. [Overlay Files](#overlay-files)
7. [U-Boot Packages](#u-boot-packages)
8. [CI/CD Workflows](#cicd-workflows)
9. [Adding a New Board](#adding-a-new-board)

---

## What This Repository Does

Ubuntu Rockchip automates the creation of bootable Ubuntu disk images for Rockchip-based ARM single-board computers (SBCs). It handles every step:

1. Cross-compiles a custom Linux kernel for Rockchip SoCs.
2. Builds a board-specific U-Boot bootloader.
3. Bootstraps an Ubuntu root filesystem (server or desktop).
4. Assembles a partitioned disk image, writes the bootloader, applies board-specific hardware configuration, and compresses the result.

The final artefact is a `.img.xz` file that can be flashed directly to an SD card or eMMC module.

---

## Repository Layout

```
ubuntu-rockchip/
├── build.sh              # Main entry-point – orchestrates the full build
├── config/
│   ├── boards/           # One .sh file per supported board (31 boards)
│   ├── suites/           # One .sh file per Ubuntu release (jammy, noble, …)
│   └── flavors/          # One .sh file per image type (server, desktop)
├── overlay/              # Static files that are copied into every image
│   ├── boot/firmware/    #   Cloud-init seed files
│   ├── usr/bin/          #   Bluetooth helper binaries
│   ├── usr/lib/scripts/  #   Hardware initialisation shell scripts
│   └── usr/lib/systemd/  #   Board-specific systemd service units
├── packages/             # Debian source packages for U-Boot variants
│   ├── u-boot-radxa-rk3588/
│   ├── u-boot-mixtile-rk3588/
│   ├── u-boot-turing-rk3588/
│   └── u-boot-rk3576/
├── scripts/
│   ├── build-kernel.sh   # Clone & cross-compile the kernel into .deb packages
│   ├── build-u-boot.sh   # Build the board U-Boot .deb package
│   ├── build-rootfs.sh   # Bootstrap the Ubuntu root filesystem tarball
│   ├── config-image.sh   # Board-specific image customisation (called by build-image.sh)
│   └── build-image.sh    # Partition, install rootfs & bootloader, compress
├── .github/
│   └── workflows/        # GitHub Actions CI pipeline definitions
├── README.md             # End-user installation guide
└── LICENSE               # GPL-3.0
```

---

## Key Technologies

| Technology | Role |
|---|---|
| **Bash** | All build logic – `build.sh` and every script under `scripts/` |
| **cross-compilation (aarch64-linux-gnu)** | Compiles the ARM64 kernel on an x86-64 host |
| **fakeroot / debian/rules** | Packages the compiled kernel as installable `.deb` files |
| **debootstrap / live-build** | Bootstraps an Ubuntu ARM64 root filesystem |
| **livecd-rootfs** (custom fork) | Drives `live-build` with Ubuntu-specific configuration |
| **QEMU user-mode emulation** | Allows `chroot` into the ARM64 rootfs on an x86-64 host |
| **U-Boot** | Bootloader for all supported boards |
| **APT / Launchpad PPAs** | Installs Rockchip-specific kernel, drivers, and multimedia packages |
| **Panfork / Mali G610** | Open-source 3D GPU driver for the Mali G610 GPU |
| **GNOME / Wayland** | Desktop environment for the `desktop` flavor |
| **GitHub Actions** | Nightly, release, and manual CI builds |
| **XZ compression** | Final images and root filesystem tarballs |

**Custom Launchpad PPAs used:**

| PPA | Contents |
|---|---|
| `jjriek/rockchip` | Rockchip kernel packages and core drivers |
| `jjriek/rockchip-multimedia` | GPU drivers, media codecs, camera engine |
| `jjriek/panfork-mesa` | Open-source Panfork Mesa driver for Mali G610 |

---

## Configuration System

The build is parameterised by three independent dimensions, each defined by a small shell script that exports environment variables.

### `config/boards/<board>.sh` – Board

Defines hardware metadata and the board-specific image customisation hook:

```bash
export BOARD_NAME="Orange Pi 5"
export BOARD_MAKER="Xulong"
export BOARD_SOC="Rockchip RK3588S"
export BOARD_CPU="ARM Cortex A76 / A55"
export UBOOT_PACKAGE="u-boot-radxa-rk3588"       # which U-Boot package to build/install
export UBOOT_RULES_TARGET="orangepi-5-rk3588s"   # make target inside the U-Boot package
export COMPATIBLE_SUITES=("jammy" "noble" "oracular" "plucky")
export COMPATIBLE_FLAVORS=("server" "desktop")

function config_image_hook__orangepi-5() {
    local rootfs="$1"    # path to the mounted root filesystem
    local overlay="$2"   # path to the overlay/ directory
    local suite="$3"     # ubuntu suite name

    # Install GPU driver, Bluetooth service, USB quirks, etc.
}
```

The `config_image_hook__<board>` function is the primary extension point. It runs inside `config-image.sh` with the rootfs chroot-mounted so it can call `chroot`, copy overlay files, and enable systemd services.

**Supported boards (31 total):**

| Family | Boards |
|---|---|
| Radxa ROCK 5 | rock-5a, rock-5b, rock-5b-plus, rock-5c, rock-5d, rock-5-itx |
| Radxa CM5 / NX5 | radxa-cm5-io, radxa-cm5-rpi-cm4-io, radxa-nx5-io |
| Radxa Zero | radxa-zero3 |
| Orange Pi 5 | orangepi-5, orangepi-5b, orangepi-5-plus, orangepi-5-pro, orangepi-5-max |
| Orange Pi CM5 / 3B | orangepi-cm5, orangepi-3b |
| NanoPC / NanoPi | nanopc-t6, nanopi-r6c, nanopi-r6s |
| ArmSom | armsom-aim7, armsom-sige5, armsom-sige7, armsom-w3 |
| Mixtile | mixtile-blade3, mixtile-core3588e |
| Others | aio-3588l, indiedroid-nova, lubancat-4, roc-rk3588s-pc, turing-rk1 |

### `config/suites/<suite>.sh` – Ubuntu Release

Defines the Ubuntu version and the kernel source:

```bash
export RELASE_NAME="Ubuntu 24.04 LTS (Noble Nombat)"
export RELASE_VERSION="24.04"
export KERNEL_REPO="https://github.com/Joshua-Riek/linux-rockchip.git"
export KERNEL_BRANCH="noble"
export KERNEL_FLAVOR="rockchip"
export EXTRA_PPAS="jjriek/rockchip jjriek/rockchip-multimedia"
```

| Suite | Ubuntu Version | Kernel |
|---|---|---|
| `jammy` | 22.04 LTS | Linux 5.10 |
| `noble` | 24.04 LTS | Linux 6.1 |
| `oracular` | 24.10 | Linux 6.1 |
| `plucky` | 25.04 | Linux 6.1 |

### `config/flavors/<flavor>.sh` – Image Type

Controls which top-level meta-package `live-build` installs:

| Flavor | `PROJECT` | Result |
|---|---|---|
| `server` | `ubuntu-cpc` | Minimal headless Ubuntu Server with cloud-init |
| `desktop` | `ubuntu` + `desktop-preinstalled` subproject | Full GNOME desktop with first-run wizard |

---

## Build Pipeline

```
build.sh
│
├── scripts/build-kernel.sh    (skipped when --launchpad or already built)
│     Clone Joshua-Riek/linux-rockchip  →  cross-compile  →  linux-*.deb
│
├── scripts/build-u-boot.sh    (skipped when --launchpad or already built)
│     Source packages/u-boot-<family>/  →  dpkg-buildpackage  →  u-boot-<board>_*.deb
│
├── scripts/build-rootfs.sh
│     Clone Joshua-Riek/livecd-rootfs  →  lb config  →  lb build
│     → ubuntu-<version>-preinstalled-<flavor>-arm64.rootfs.tar.xz
│
└── scripts/config-image.sh   (called via build-image.sh)
      Extract rootfs  →  mount chroot  →  run config_image_hook__<board>()
      →  install U-Boot .deb + kernel .debs inside chroot
      →  update-initramfs  →  teardown chroot
      →  build-image.sh: create GPT, write partitions, write U-Boot, compress
      → ubuntu-<version>-preinstalled-<flavor>-arm64-<board>.img.xz
```

### `build.sh` — Orchestrator

`build.sh` is the single entry-point for a complete build:

```bash
sudo ./build.sh --board=orangepi-5 --suite=noble --flavor=desktop
```

It sources the three config files, then calls each sub-script in order. If `.deb` packages from a previous run are already present in `build/`, the kernel and U-Boot steps are skipped automatically.

**Flags:**

| Flag | Effect |
|---|---|
| `--kernel-only` | Run only `build-kernel.sh` |
| `--uboot-only` | Run only `build-u-boot.sh` |
| `--rootfs-only` | Run only `build-rootfs.sh` |
| `--launchpad` | Skip local kernel/U-Boot build; use packages from Launchpad PPAs instead |
| `--clean` | Delete the entire `build/` directory first |
| `--verbose` | Enable `set -x` shell tracing |

### `scripts/build-kernel.sh` — Kernel

1. Clones `Joshua-Riek/linux-rockchip` on the branch matching the suite.
2. Sets `CROSS_COMPILE=aarch64-linux-gnu-` and `CC=aarch64-linux-gnu-gcc`.
3. Runs `fakeroot debian/rules clean binary-headers binary-rockchip do_mainline_build=true` to produce:
   - `linux-image-<version>-rockchip_*.deb`
   - `linux-headers-<version>-rockchip_*.deb`
   - `linux-modules-<version>-rockchip_*.deb`
   - `linux-buildinfo-<version>-rockchip_*.deb`
   - `linux-rockchip-headers-<version>_*.deb`

### `scripts/build-u-boot.sh` — U-Boot

1. Sources the board config to read `UBOOT_PACKAGE` and `UBOOT_RULES_TARGET`.
2. Sources the corresponding package metadata from `packages/<UBOOT_PACKAGE>/debian/upstream`.
3. Clones the upstream U-Boot repo at the pinned commit.
4. Runs `dpkg-buildpackage` to produce `u-boot-<board>_*.deb`.

### `scripts/build-rootfs.sh` — Root Filesystem

1. Exits early if a cached `rootfs.tar.xz` already exists.
2. Clones and builds the custom `livecd-rootfs` fork, then installs the resulting `.deb`.
3. Calls `lb config` to configure `live-build` for ARM64 with Ubuntu's ports mirror.
4. For `jammy`/`noble`: pins the Rockchip PPAs at priority 1001 (overrides official Ubuntu packages).
5. Writes package lists: `software-properties-common` plus either `ubuntu-desktop-rockchip` (desktop) or `ubuntu-server-rockchip` (server).
6. Runs `lb build` (uses QEMU user-mode to run ARM64 binaries on the host).
7. Tars the `chroot/` directory and compresses it to `ubuntu-<version>-preinstalled-<flavor>-arm64.rootfs.tar.xz`.

### `scripts/config-image.sh` — Board Customisation

1. Extracts the rootfs tarball.
2. Mounts `devtmpfs`, `devpts`, `proc`, `sysfs`, `cgroup`, and `tmpfs` into the chroot.
3. Runs `apt-get upgrade` inside the chroot.
4. Calls `config_image_hook__<board>()` — this is where GPU drivers, Bluetooth services, USB quirks, and other board-specific changes are applied.
5. Installs the U-Boot and kernel `.deb` packages inside the chroot (or pulls from Launchpad if `--launchpad` was used).
6. Runs `update-initramfs`.
7. Tears down all mounts, re-tars the rootfs, and passes it to `build-image.sh`.

### `scripts/build-image.sh` — Disk Image Assembly

1. Creates a GPT-partitioned disk image:
   - **Server:** FAT32 boot partition (16 MB) + EXT4 root partition
   - **Desktop:** Single EXT4 partition
2. Formats partitions and extracts the board-specific rootfs tar onto them.
3. Writes the U-Boot bootloader binary to the image at the appropriate sector offset (typically sector 64).
4. Runs `u-boot-update` inside a chroot to write `extlinux.conf`.
5. Compresses the image to `.img.xz` with `xz -T0`.
6. Generates a `SHA256SUMS` file alongside the image.

**Caching strategy:**

| Artefact | Rebuilt when |
|---|---|
| `linux-*.deb` | Not found in `build/` |
| `u-boot-<board>_*.deb` | Not found in `build/` |
| `rootfs.tar.xz` | Not found in `build/` |
| Final `.img.xz` | Always (image is board-specific) |

---

## Overlay Files

The `overlay/` directory contains static files that are copied verbatim into images by the board hook functions. They are never installed globally — each board only copies the files it needs.

```
overlay/
├── boot/firmware/
│   ├── meta-data          # Cloud-init instance identity
│   ├── user-data          # Cloud-init default user/password configuration
│   └── network-config     # Cloud-init network configuration
├── usr/bin/
│   ├── brcm_patchram_plus # Broadcom Bluetooth firmware loader
│   ├── hciattach_opi      # Orange Pi Bluetooth attachment helper
│   ├── rtk_hciattach      # Realtek Bluetooth attachment helper
│   └── bt_load_rtk_firmware
├── usr/lib/scripts/
│   ├── ap6275p-bluetooth.sh   # Broadcom AP6275P init script
│   ├── aic8800-bluetooth.sh   # Aicsemi AIC8800 init script
│   └── alsa-audio-config      # ALSA audio profile configuration
└── usr/lib/systemd/system/
    ├── ap6275p-bluetooth.service
    ├── ap6256s-bluetooth.service
    ├── rtl8821cs-bluetooth.service
    ├── radxa-a8-bluetooth.service
    ├── aic8800-bluetooth.service
    ├── sprd-bluetooth.service
    ├── rtl8852be-reload.service
    ├── ap6256-reboot.service
    ├── enable-usb2.service
    └── alsa-audio-config.service
```

A typical board hook selects only the services matching its WiFi/Bluetooth chip:

```bash
# Example: copy and enable the Broadcom AP6275P Bluetooth service
cp "${overlay}/usr/lib/systemd/system/ap6275p-bluetooth.service" \
   "${rootfs}/usr/lib/systemd/system/ap6275p-bluetooth.service"
cp "${overlay}/usr/lib/scripts/ap6275p-bluetooth.sh" \
   "${rootfs}/usr/lib/scripts/ap6275p-bluetooth.sh"
cp "${overlay}/usr/bin/brcm_patchram_plus" "${rootfs}/usr/bin/brcm_patchram_plus"
chroot "${rootfs}" systemctl enable ap6275p-bluetooth
```

---

## U-Boot Packages

The `packages/` directory contains Debian source package scaffolding for four U-Boot variants. Each subdirectory follows standard Debian packaging conventions:

```
packages/u-boot-radxa-rk3588/
├── debian/
│   ├── upstream     # Git URL, branch, commit hash, upstream version
│   ├── control      # Package metadata and dependencies
│   ├── rules        # Build rules (invokes make <target>)
│   └── …
```

| Package | SoC family | Upstream source |
|---|---|---|
| `u-boot-radxa-rk3588` | RK3588 / RK3588S | github.com/radxa/u-boot |
| `u-boot-mixtile-rk3588` | RK3588 | github.com/radxa/u-boot |
| `u-boot-turing-rk3588` | RK3588 | github.com/u-boot/u-boot (mainline) |
| `u-boot-rk3576` | RK3576 | github.com/Joshua-Riek/u-boot-rockchip |

Each package supports multiple board targets (controlled by `UBOOT_RULES_TARGET` in the board config). `build-u-boot.sh` reads the `debian/upstream` file to clone the correct repo at the pinned commit before running `dpkg-buildpackage`.

---

## CI/CD Workflows

All workflows live in `.github/workflows/`.

### `build.yml` — Manual Test Build

- **Trigger:** `workflow_dispatch`
- Builds rootfs for all suite × flavor combinations (4 jobs).
- Builds kernels for `jammy` and `noble`.
- Runs a matrix of all 31 boards × supported suites × flavors as image jobs (excludes incompatible combinations declared in each board config).
- Does **not** upload artefacts to a release.

### `nightly.yml` — Scheduled Nightly Build

- **Trigger:** `schedule` (daily at midnight UTC)
- Generates the board matrix dynamically from `config/boards/*.sh` using each board's `COMPATIBLE_SUITES` and `COMPATIBLE_FLAVORS`.
- Always passes `--launchpad` so kernels and U-Boot are pulled from Launchpad PPAs (faster, no local cross-compile).
- Uploads images as workflow artefacts.

### `release.yml` — Release Build

- **Trigger:** `workflow_dispatch`
- Full build of all boards.
- Uploads all images to a draft GitHub release.

### `stale.yml` — Issue Hygiene

- **Trigger:** `schedule` (weekly)
- Marks issues and pull requests as stale after a period of inactivity and closes them after a further grace period.

---

## Adding a New Board

1. **Create `config/boards/<board-id>.sh`** and export the required variables:
   - `BOARD_NAME`, `BOARD_MAKER`, `BOARD_SOC`, `BOARD_CPU`
   - `UBOOT_PACKAGE` — which package in `packages/` provides U-Boot
   - `UBOOT_RULES_TARGET` — the make target inside that package
   - `COMPATIBLE_SUITES` and `COMPATIBLE_FLAVORS`
   - `config_image_hook__<board-id>()` — install GPU driver, Bluetooth, audio, etc.

2. **Check whether an existing U-Boot package covers your board** (`packages/u-boot-radxa-rk3588` supports many RK3588 boards via different `UBOOT_RULES_TARGET` values). If not, add a new package under `packages/`.

3. **Add overlay files** to `overlay/` if the board needs a Bluetooth binary or service that is not already present.

4. **Test locally:**
   ```bash
   sudo ./build.sh --board=<board-id> --suite=noble --flavor=server --launchpad
   ```

5. The CI matrix is generated dynamically from the board configs, so the new board will be picked up automatically by `nightly.yml` and `build.yml` on the next run.
