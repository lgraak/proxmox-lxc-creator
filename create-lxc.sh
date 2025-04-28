#!/bin/bash
# create-lxc.sh
# Version: 0.1.0
#
# Proxmox LXC Creator - Partial Working Prototype
# Licensed under Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)
# https://creativecommons.org/licenses/by-nc/4.0/

set -e
set -o pipefail
set -x

VERSION="0.1.0"
LOGFILE="./create-lxc-$(date '+%Y-%m-%d').log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# Handle --version flag
if [[ "$1" == "--version" ]]; then
    echo "Proxmox LXC Creator Script - Version $VERSION"
    exit 0
fi

# Load .env file
if [[ ! -f ".env" ]]; then
    log "ERROR: .env file not found."
    exit 1
fi

# shellcheck disable=SC1091
source ".env"

# Validate required .env variables
REQUIRED_VARS=(DEFAULT_DNS TEMPLATE_STORAGE NFS_STORAGE DEFAULT_BRIDGE)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        log "ERROR: $var is not set in .env"
        exit 1
    fi
done

HOSTNAME_SUFFIX="${HOSTNAME_SUFFIX:-}" # optional
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"   # optional

# Function to get available nodes
get_nodes() {
    pvesh get /nodes | jq -r '.[].node'
}

# Function to list local templates from NFS
list_local_templates() {
    pvesm list "$TEMPLATE_STORAGE" | awk '/vztmpl/ {print $1, $2}' | grep -E 'default|standard' | awk '{print $2}'
}

# Function to list remote templates from Proxmox
list_remote_templates() {
    pveam available | awk '$2 ~ /default|standard/ {print $2}'
}

# Function to check existing CTIDs
ctid_exists() {
    pct list | awk 'NR>1 {print $1}' | grep -q "^$1$"
}

# Select Node
select_node() {
    log "Fetching available nodes..."
    NODES=($(get_nodes))
    if [[ ${#NODES[@]} -eq 0 ]]; then
        log "ERROR: No nodes found."
        exit 1
    fi
    echo "Select Proxmox Node:"
    select NODE in "${NODES[@]}"; do
        if [[ -n "$NODE" ]]; then
            log "Selected node: $NODE"
            break
        else
            echo "Invalid selection."
        fi
    done
}

# Select Template
select_template() {
    log "Fetching templates..."
    LOCAL_TEMPLATES=($(list_local_templates))
    REMOTE_TEMPLATES=($(list_remote_templates))

    TEMPLATES=("${LOCAL_TEMPLATES[@]}")
    for remote in "${REMOTE_TEMPLATES[@]}"; do
        # Only add remote templates that aren't local
        if [[ ! " ${LOCAL_TEMPLATES[*]} " =~ " $remote " ]]; then
            TEMPLATES+=("$remote (remote)")
        fi
    done

    echo "Select a template:"
    select TEMPLATE in "${TEMPLATES[@]}"; do
        if [[ -n "$TEMPLATE" ]]; then
            if [[ "$TEMPLATE" == *"(remote)"* ]]; then
                TEMPLATE_NAME="${TEMPLATE%% *}"
                echo "Template not found locally. Download it?"
                select yn in "Yes" "No"; do
                    case $yn in
                        Yes ) pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"; break;;
                        No ) log "Template download cancelled. Exiting."; exit 1;;
                    esac
                done
                TEMPLATE="$TEMPLATE_NAME"
            fi
            log "Selected template: $TEMPLATE"
            break
        else
            echo "Invalid selection."
        fi
    done
}

# Ask for CTID
ask_ctid() {
    while true; do
        read -rp "Enter CTID (numeric, unused): " CTID
        if [[ "$CTID" =~ ^[0-9]+$ ]]; then
            if ctid_exists "$CTID"; then
                echo "CTID $CTID already exists. Choose another."
            else
                log "Selected CTID: $CTID"
                break
            fi
        else
            echo "Invalid CTID. Must be a number."
        fi
    done
}

# Ask for Container Name
ask_name() {
    while true; do
        read -rp "Enter container name (no spaces, lowercase recommended): " NAME
        NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
        if [[ "$NAME" =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]]; then
            log "Container name: $NAME"
            break
        else
            echo "Invalid name. Use lowercase letters, numbers, and hyphens only."
        fi
    done
}

# Ask for Storage
ask_storage() {
    AVAILABLE_STORAGES=()
    while IFS= read -r storage; do
        type=$(pvesm status --storage "$storage" | awk 'NR>1 {print $2}')
        if [[ "$type" == "lvmthin" ]]; then
            AVAILABLE_STORAGES+=("$storage")
        fi
    done < <(pvesm status | awk 'NR>1 {print $1}')

    AVAILABLE_STORAGES+=("$NFS_STORAGE")

    echo "Select Storage:"
    select STORAGE in "${AVAILABLE_STORAGES[@]}"; do
        if [[ -n "$STORAGE" ]]; then
            log "Selected Storage: $STORAGE"
            break
        else
            echo "Invalid selection."
        fi
    done
}

# ========== MAIN LOGIC ==========

log "Starting Proxmox LXC Creator Script v$VERSION"
select_node
select_template
ask_ctid
ask_name
ask_storage

log "User selections complete."
log "Node: $NODE | Template: $TEMPLATE | CTID: $CTID | Name: $NAME | Storage: $STORAGE"

# (Placeholder for future steps: CPU, RAM, Disk Size, Networking, Passwords, pct create)

log "Partial working script finished. Exiting."

exit 0

