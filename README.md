# Proxmox LXC Creator

A modular Bash script for **automated, flexible, and reliable LXC container creation** across multi-node Proxmox VE clusters.

This script is designed to:
- Dynamically fetch available templates (local NFS and Proxmox public)
- Prompt interactively for critical container settings
- Configure networking and hostname inside containers after creation
- Support both **Debian** and **Ubuntu** containers reliably
- Write full timestamped logs for auditing and troubleshooting
- Follow clean, production-safe scripting practices

---

## Features

- ✅ Dynamic Node Selection
- ✅ Dynamic Template Listing (Local + Remote)
- ✅ Storage Selection (lvmthin and NFS)
- ✅ CTID Validation
- ✅ Clean Container Naming (short name only)
- ✅ CPU / RAM / Disk Customization
- ✅ DHCP or Static IP Networking (VLAN support)
- ✅ Privileged / Unprivileged Container Choice
- ✅ Root Password Prompt (with confirmation)
- ✅ Post-creation Networking Configuration:
  - Ubuntu: Netplan YAML creation + apply
  - Debian: Ensure `/etc/network/interfaces` exists, bring up eth0
- ✅ Internal Hostname Setting (`hostnamectl`)
- ✅ Full Timestamped Logging
- ✅ Distro Neutral (Debian and Ubuntu tested)
- ✅ GitHub-Ready Codebase

---

## Environment Variables

Configure a `.env` file or modify the provided `env-template`:

```bash
# Example .env

# Comma-separated DNS servers
DEFAULT_DNS="192.168.1.10,192.168.20.10"

# Storage where templates are stored (must be NFS)
TEMPLATE_STORAGE="proxmox-templates"

# Storage for container root disks
NFS_STORAGE="proxmox-vmstore"

# Default network bridge
DEFAULT_BRIDGE="vmbr0"

# Domain suffix to append to internal hostnames
HOSTNAME_SUFFIX="ad.cgillett.com"

# SSH public key to inject (optional)
SSH_PUBLIC_KEY=""
