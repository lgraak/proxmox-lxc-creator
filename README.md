# Proxmox LXC Creator

A fully modular Bash script for **automated, reliable, and clean Linux container (LXC) creation** across multi-node Proxmox VE clusters.

Designed for professional and personal environments:
- Dynamically fetches available Debian, Ubuntu, and Rocky Linux templates
- Handles missing remote templates automatically
- Configures hostname, networking, and safe options after creation
- Fully audited, production-grade, and GitHub-ready

---

## Features

- ✅ Dynamic Node Selection
- ✅ Dynamic Template Listing (Debian / Ubuntu / Rocky Linux only)
- ✅ Local and Remote Template Handling (auto-download if needed)
- ✅ CTID Uniqueness Validation
- ✅ CPU / RAM / Disk Customization
- ✅ DHCP or Static IP Networking (VLAN support)
- ✅ Privileged or Unprivileged Container Type Selection
- ✅ Root Password with Confirmation
- ✅ Internal Hostname Setting (short name externally, FQDN internally)
- ✅ Full Timestamped Logging
- ✅ GitHub-Ready Codebase
- ✅ Safe Error Handling (`set -e -o pipefail`)
- ✅ Distro-Neutral Networking Configuration

---

## Environment Configuration

Create a `.env` file in your script directory:

```bash
# Example .env

# DNS servers for containers (comma-separated)
DEFAULT_DNS="192.168.1.11,192.168.20.99"

# Storage for template cache (must be NFS-mounted)
TEMPLATE_STORAGE="proxmox-templates"

# Storage for root disks (LVMThin or NFS-backed)
NFS_STORAGE="proxmox-vmstore"

# Default network bridge
DEFAULT_BRIDGE="vmbr0"

# Hostname domain suffix (optional)
HOSTNAME_SUFFIX="ad.debian.com"

# SSH public key to inject (optional)
SSH_PUBLIC_KEY=""
```

---

## Requirements

- Proxmox VE 8.x
- `whiptail`, `jq` installed on the host
- NFS storage configured for templates and/or container disks
- Local template cache preferred for speed

---

## Usage

```bash
# Clone this repository
git clone git@github.com:lgraak/proxmox-lxc-creator.git
cd proxmox-lxc-creator

# Copy and edit the env-template
cp env-template .env
nano .env

# Make script executable
chmod +x create-lxc.sh

# Run the script
./create-lxc.sh
```

The script will guide you through container creation interactively.

---

## Logging

Each run generates a timestamped log file:

```bash
create-lxc-YYYY-MM-DD.log
```

in the same directory.

---

## License

Licensed under the [Creative Commons Zero v1.0 Universal (CC0 1.0)](LICENSE).

---

## Version

- `v0.2.1`
  - Production-grade release
  - Debian/Ubuntu/Rocky Linux support
  - Clean Proxmox naming (short names)
  - Safe remote template downloads
  - Full dynamic networking configuration
  - Full timestamped logging
  - Finalized for GitHub publication
