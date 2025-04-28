# Proxmox LXC Creator

A Bash script to automate creating Linux Containers (LXC) in a Proxmox VE environment.

## Features
- Pulls available templates from both local NFS and Proxmox remote repository
- Filters templates to only default or standard (no turnkey/appliance)
- Offers to auto-download missing templates
- Fully interactive prompts for Node, CTID, Name, Storage, and Template
- Validates CTID uniqueness
- Supports version tracking (`--version`)
- Verbose logging to timestamped log files
- Configuration via simple `.env` file

## Requirements
- Proxmox VE 7.x or 8.x
- Bash shell
- `pvesh`, `pct`, and `pveam` available

## License
Licensed under Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0).

## Usage
1. Copy `.env.example` to `.env` and adjust settings.
2. Run the script:
```bash
chmod +x create-lxc.sh
./create-lxc.sh

