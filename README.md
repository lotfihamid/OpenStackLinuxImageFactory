<p align="center">For Iran, with love 🇮🇷</p>


## OpenStack Linux Image Factory

A robust Bash script to build, customize, and upload cloud images to OpenStack Glance.

This tool automates the entire lifecycle of preparing a cloud-ready image:  
downloading (or using a local file), verifying checksum, converting to RAW, installing guest packages, cleaning up with `virt-sysprep`, and uploading to Glance with proper metadata.  
It also offers an interactive mode and flexible cleanup prompts.

---

## Features

- **Download from URL** or **use a local image file**
- **SHA256 checksum verification** (optional, URL mode only)
- **Automatic format detection** (qcow2, raw, etc.) and conversion to RAW
- **Guest customization**:
  - Installs `qemu-guest-agent`, `cloud-init`, `openssh-server`
  - Cleans cloud-init state
  - Runs targeted `virt-sysprep` operations (machine-id, ssh host keys, dhcp leases, bash history, tmp files)
- **Upload to OpenStack Glance** with:
  - Custom properties (`os_distro`, `os_version`, `architecture`, `hw_disk_bus`, `hw_qemu_guest_agent`)
  - Visibility control (`public`, `private`, `shared`, `community`)
  - Option to skip upload (`--no-upload`)
- **Interactive mode** (`-i`) – prompts for all parameters
- **Work directory preservation** (`--keep-workdir`)
- **Smart cleanup** – asks before deleting source and RAW files (when run in a terminal)
- **Detailed logging** – all output saved to `build.log`
- **Error handling** – clear error messages and automatic trap

---

## Prerequisites

Ensure the following tools are installed and available in your `PATH`:

| Tool | Package (Debian/Ubuntu) | Purpose |
|------|--------------------------|---------|
| `curl`, `wget` | `curl`, `wget` | Downloading images and checksums |
| `qemu-img` | `qemu-utils` | Image format detection and conversion |
| `virt-customize`, `virt-sysprep`, `virt-ls`, `virt-cat` | `libguestfs-tools` | Guest image customization and inspection |
| `sha256sum` | `coreutils` | Checksum calculation |
| `python3` | `python3` | JSON parsing (for format detection) |
| `openstack` | `python3-openstackclient` | Uploading image to Glance |

You also need a working OpenStack environment with valid credentials (e.g., `clouds.yaml` or environment variables like `OS_AUTH_URL`, `OS_USERNAME`, etc.).

> **Note:** `virt-customize` and `virt-sysprep` may require root privileges or membership in the `libvirt` group. Run the script with appropriate permissions.

---

## Installation

Simply download the script and make it executable:

```bash
curl -O https://your-repo/image-factory.sh
chmod +x image-factory.sh
```

Place it anywhere in your `PATH` or run it directly.

---

## Usage

### Non‑interactive (classic)

```bash
./image-factory.sh [OPTIONS] <IMAGE_NAME> <VERSION> [DOWNLOAD_URL]
```

- `IMAGE_NAME` – Name of the image in Glance (spaces allowed; they will be replaced with `_` in file paths)
- `VERSION` – Version string (e.g., `22.04`, `12`)
- `DOWNLOAD_URL` – URL to download the source image (optional if `--local-file` is used)

### Interactive

```bash
./image-factory.sh -i
```

The script will guide you through all parameters step by step.

---

## Options

| Option | Description |
|--------|-------------|
| `-i`, `--interactive` | Run in interactive mode (prompts for all parameters) |
| `--local-file PATH` | Use a local image file instead of downloading. `DOWNLOAD_URL` becomes optional. |
| `--checksum-url URL` | URL to a checksum file (e.g., `SHA256SUMS`). Only valid when downloading from URL. |
| `--os-distro DISTRO` | Value for the `os_distro` property in Glance. If omitted, the property is not set. |
| `--no-upload` | Build the image but do **not** upload to Glance. |
| `--visibility {public\|private\|shared\|community}` | Visibility of the uploaded image. Default: `public`. |
| `--keep-workdir` | Keep the entire work directory (including source and logs) after completion. |
| `-h`, `--help` | Show help message and exit. |

---

## Examples

### 1. Download Ubuntu 22.04, verify checksum, upload as public

```bash
./image-factory.sh \
  --checksum-url https://cloud-images.ubuntu.com/releases/22.04/release/SHA256SUMS \
  --os-distro ubuntu \
  --visibility public \
  "Ubuntu 22.04" "22.04" \
  "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
```

### 2. Use a local Debian image, upload as private

```bash
./image-factory.sh \
  --local-file /data/images/debian-12-generic-amd64.qcow2 \
  --os-distro debian \
  --visibility private \
  "Debian 12" "12"
```

### 3. Interactive mode

```bash
./image-factory.sh -i
```

### 4. Build only, no upload

```bash
./image-factory.sh \
  --no-upload \
  --os-distro centos \
  "CentOS Stream 9" "9" \
  "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
```

---

## Workflow Overview

1. **Argument parsing** – validates inputs and sets defaults.
2. **Directory preparation** – creates a timestamped work directory under `./image-build/`.
3. **Source acquisition** – downloads from URL or copies from local file.
4. **Checksum verification** – if `--checksum-url` provided (URL mode only).
5. **Format detection** – uses `qemu-img info` to determine source format.
6. **Conversion to RAW** – `qemu-img convert` to raw format.
7. **Guest customization**:
   - Installs required packages via `virt-customize`.
   - Cleans cloud-init state.
   - Runs `virt-sysprep` with selected operations.
8. **SHA256 calculation** – saves checksum alongside the RAW file.
9. **Upload to Glance** – unless `--no-upload` is given.
10. **Final report** – shows paths, checksum, and upload status.
11. **Cleanup prompts** – if run interactively, asks whether to delete the source and RAW files.

---

## Directory Structure

After a successful run, the work directory looks like this:

```
image-build/
└── <IMAGE_NAME_SAFE>-<VERSION>-<TIMESTAMP>/
    ├── source/               # Downloaded or copied source image
    ├── build/
    │   ├── <IMAGE_NAME_SAFE>-<VERSION>.raw
    │   └── <IMAGE_NAME_SAFE>-<VERSION>.raw.sha256
    └── logs/
        └── build.log
```

- `IMAGE_NAME_SAFE` is the image name with spaces replaced by underscores.
- The RAW file and its SHA256 are **never deleted automatically**.  
  At the end, if the script is running in a terminal, it asks whether to delete the source and RAW files. If run non‑interactively, they are kept.

---

## Cleanup Behavior

- By default, the script **does not delete** the source image or the RAW file.
- After a successful build, if standard input/output is a TTY, it prompts:
  1. Delete source file? (default: No)
  2. Delete RAW file? (default: No)
- If you answer `y`, the corresponding file (and SHA256 for RAW) is removed.
- Empty directories are cleaned up afterwards (unless `--keep-workdir` is used).
- In non‑interactive environments (e.g., CI/CD), no prompts appear and all files are preserved.

---

## Notes & Tips

- **Spaces in image names** are replaced with `_` for directory and file names, but the original name (with spaces) is used in Glance.
- **Visibility default** is `public`. Change it with `--visibility private` etc.
- **Checksum verification** is only performed when downloading from a URL. It is skipped for local files.
- **`os_distro` property** is optional; if not provided, it is omitted from the Glance image properties.
- The script requires a working OpenStack CLI configuration. Test with `openstack image list` before running.
- If you encounter permission errors with `virt-customize`, try running the script with `sudo` or add your user to the `libvirt` group.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Command 'virt-customize' not found` | Install `libguestfs-tools`. |
| `openstack: command not found` | Install `python3-openstackclient`. |
| `Unable to authenticate` | Source your OpenStack RC file or configure `clouds.yaml`. |
| `qemu-img: Could not open ... Permission denied` | Run with `sudo` or ensure proper file permissions. |
| `virt-customize: error: libguestfs error` | Check that `/dev/kvm` is accessible and user is in `kvm`/`libvirt` group. |

---

## License

This script is provided as‑is, without warranty of any kind.  
You are free to use, modify, and distribute it as needed.

---

## Author

Created for streamlining OpenStack cloud image preparation.  
Feel free to contribute improvements or report issues.
