#!/bin/bash
# create-lxc.sh
# Version: 0.2.0
#
# Proxmox LXC Creator - Full Working Version (Phase 2)
# Licensed under Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)
# https://creativecommons.org/licenses/by-nc/4.0/

set -e
set -o pipefail

VERSION="0.2.0"
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

# Check dependencies
command -v pvesh >/dev/null 2>&1 || { echo >&2 "pvesh not found. Is this a Proxmox server? Aborting."; exit 1; }
command -v pveam >/dev/null 2>&1 || { echo >&2 "pveam not found. Is this a Proxmox server? Aborting."; exit 1; }
command -v whiptail >/dev/null 2>&1 || { echo >&2 "whiptail not installed. Install it first: apt install whiptail"; exit 1; }

# Utility function to exit cleanly on cancel
check_cancel() {
    if [[ $? -ne 0 ]]; then
        log "User canceled. Exiting."
        exit 1
    fi
}

# Function to get available nodes
get_nodes() {
    pvesh get /nodes --output-format=json | jq -r '.[].node'
}

# Function to list local templates from NFS
list_local_templates() {
    pvesm list "$TEMPLATE_STORAGE" | awk '$2 == "vztmpl" {print $3}'
}

# Function to list remote templates from Proxmox
list_remote_templates() {
    pveam available | awk '$2 ~ /default|standard/ {print $2}'
}

# Function to check existing CTIDs
ctid_exists() {
    pct list | awk 'NR>1 {print $1}' | grep -q "^$1$"
}

# Function to validate an IP address
validate_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Select Node
select_node() {
    log "Fetching available nodes..."
    RAW_NODES=($(get_nodes))
    if [[ ${#RAW_NODES[@]} -eq 0 ]]; then
        log "ERROR: No nodes found."
        exit 1
    fi

    NODE_MENU=()
    for node in "${RAW_NODES[@]}"; do
        NODE_MENU+=("$node" "Node $node")
    done

    NODE=$(whiptail --title "Select Proxmox Node" --menu "Choose a node:" 15 60 5 "${NODE_MENU[@]}" 3>&1 1>&2 2>&3)
    check_cancel
    log "Selected node: $NODE"
}
# Select Template
select_template() {
    log "Fetching templates..."
    LOCAL_TEMPLATES=($(list_local_templates))
    REMOTE_TEMPLATES=($(list_remote_templates))

    # Combine local and remote templates
    TEMPLATES=()
    TEMPLATE_SOURCE=() # Matches the TEMPLATES array, "local" or "remote"

    # Add local templates
    for template in "${LOCAL_TEMPLATES[@]}"; do
        if [[ "$template" =~ debian || "$template" =~ ubuntu || "$template" =~ rockylinux ]]; then
            TEMPLATES+=("$template")
            TEMPLATE_SOURCE+=("local")
        fi
    done

    # Add remote templates (only if not already present locally)
    for remote in "${REMOTE_TEMPLATES[@]}"; do
        if [[ "$remote" =~ debian || "$remote" =~ ubuntu || "$remote" =~ rockylinux ]]; then
            if [[ ! " ${LOCAL_TEMPLATES[*]} " =~ " $remote " ]]; then
                TEMPLATES+=("$remote")
                TEMPLATE_SOURCE+=("remote")
            fi
        fi
    done

    # Build menu list for Whiptail
    TEMPLATE_MENU=()
    for template in "${TEMPLATES[@]}"; do
        TEMPLATE_MENU+=("$template" "")
    done

    # Prompt user to select template
    SELECTED_TEMPLATE=$(whiptail --title "Select Template" --menu "Choose a container template:" 20 78 10 "${TEMPLATE_MENU[@]}" 3>&1 1>&2 2>&3)
    check_cancel
    log "Selected template: $SELECTED_TEMPLATE"

    # Find the index of the selected template
    SELECTED_INDEX=-1
    for i in "${!TEMPLATES[@]}"; do
        if [[ "${TEMPLATES[$i]}" == "$SELECTED_TEMPLATE" ]]; then
            SELECTED_INDEX="$i"
            break
        fi
    done

    # Check if the selected template is remote
    if [[ "${TEMPLATE_SOURCE[$SELECTED_INDEX]}" == "remote" ]]; then
        log "Selected template is remote. Prompting to download..."
        if whiptail --yesno "Template '$SELECTED_TEMPLATE' is not stored locally.\n\nWould you like to download it now?" 12 60; then
            log "Downloading template..."
            pveam download "$TEMPLATE_STORAGE" "$SELECTED_TEMPLATE"
            log "Template downloaded successfully."
        else
            log "User chose not to download the template. Aborting."
            echo "Template download cancelled. Exiting."
            exit 1
        fi
    fi

    # Set final TEMPLATE variable to the user's selected template
    TEMPLATE="$SELECTED_TEMPLATE"
}

# Select Storage
select_storage() {
    AVAILABLE_STORAGES=()
    while IFS= read -r storage; do
        type=$(pvesm status --storage "$storage" | awk 'NR>1 {print $2}')
        if [[ "$type" == "lvmthin" ]]; then
            AVAILABLE_STORAGES+=("$storage")
        fi
    done < <(pvesm status | awk 'NR>1 {print $1}')

    AVAILABLE_STORAGES+=("$NFS_STORAGE")

    STORAGE_MENU=()
    for storage in "${AVAILABLE_STORAGES[@]}"; do
        STORAGE_MENU+=("$storage" "")
    done

    STORAGE=$(whiptail --title "Select Storage" --menu "Choose container storage:" 20 78 10 "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
    check_cancel
    log "Selected Storage: $STORAGE"
}


# Ask for CTID
ask_ctid() {
    while true; do
        CTID=$(whiptail --inputbox "Enter CTID (numeric, unused):" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        if [[ "$CTID" =~ ^[0-9]+$ ]]; then
            if ctid_exists "$CTID"; then
                whiptail --msgbox "CTID already exists. Choose another." 8 45
            else
                log "Selected CTID: $CTID"
                break
            fi
        else
            whiptail --msgbox "Invalid CTID. Must be numeric." 8 45
        fi
    done
}

# Ask for Container Name
ask_name() {
    while true; do
        NAME=$(whiptail --inputbox "Enter container name (lowercase, no spaces):" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
        if [[ "$NAME" =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]]; then
            log "Container name: $NAME"
            break
        else
            whiptail --msgbox "Invalid name. Use lowercase letters, numbers, and hyphens only." 8 60
        fi
    done
}

# Ask for CPU
ask_cpu() {
    while true; do
        CPU_CORES=$(whiptail --inputbox "Enter number of CPU cores:" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        if [[ "$CPU_CORES" =~ ^[0-9]+$ && "$CPU_CORES" -ge 1 ]]; then
            log "Selected CPU cores: $CPU_CORES"
            break
        else
            whiptail --msgbox "Invalid CPU value. Must be a positive number." 8 45
        fi
    done
}

# Ask for RAM
ask_ram() {
    while true; do
        MEMORY_MB=$(whiptail --inputbox "Enter Memory (MB):" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        if [[ "$MEMORY_MB" =~ ^[0-9]+$ && "$MEMORY_MB" -ge 128 ]]; then
            log "Selected Memory: $MEMORY_MB MB"
            break
        else
            whiptail --msgbox "Invalid memory value. Must be at least 128 MB." 8 45
        fi
    done
}

# Ask for Disk Size
ask_disk() {
    while true; do
        DISK_GB=$(whiptail --inputbox "Enter Disk Size (GB) - minimum 8GB recommended:" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        if [[ "$DISK_GB" =~ ^[0-9]+$ && "$DISK_GB" -ge 8 ]]; then
            log "Selected Disk Size: $DISK_GB GB"
            break
        else
            whiptail --msgbox "Invalid disk size. Must be a number, at least 8GB." 8 45
        fi
    done
}
# Ask for Networking Type (DHCP or Static)
ask_network_type() {
    if whiptail --title "Networking" --yesno "Use DHCP for networking?" 10 60; then
        USE_DHCP=true
        log "Networking: DHCP"
    else
        USE_DHCP=false
        log "Networking: Static"
    fi
}

# Ask for Static IP Details
ask_static_ip() {
    if [ "$USE_DHCP" = false ]; then
        while true; do
            STATIC_IP=$(whiptail --inputbox "Enter Static IP Address (e.g., 192.168.1.100):" 10 60 3>&1 1>&2 2>&3)
            check_cancel
            if validate_ip "$STATIC_IP"; then
                break
            else
                whiptail --msgbox "Invalid IP address." 8 45
            fi
        done

        while true; do
            CIDR=$(whiptail --inputbox "Enter Subnet CIDR (e.g., 24 for 255.255.255.0):" 10 60 3>&1 1>&2 2>&3)
            check_cancel
            if [[ "$CIDR" =~ ^[0-9]+$ && "$CIDR" -ge 8 && "$CIDR" -le 32 ]]; then
                break
            else
                whiptail --msgbox "Invalid CIDR. Must be between 8 and 32." 8 45
            fi
        done

        while true; do
            GATEWAY=$(whiptail --inputbox "Enter Gateway IP:" 10 60 3>&1 1>&2 2>&3)
            check_cancel
            if validate_ip "$GATEWAY"; then
                break
            else
                whiptail --msgbox "Invalid Gateway IP." 8 45
            fi
        done
    fi
}

# Ask for VLAN ID
ask_vlan() {
    while true; do
        VLAN_ID=$(whiptail --inputbox "Enter VLAN ID (1-4094):" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        if [[ "$VLAN_ID" =~ ^[0-9]+$ && "$VLAN_ID" -ge 1 && "$VLAN_ID" -le 4094 ]]; then
            log "Selected VLAN: $VLAN_ID"
            break
        else
            whiptail --msgbox "Invalid VLAN ID. Must be 1-4094." 8 45
        fi
    done
}

# Ask for Privileged or Unprivileged
ask_privilege() {
    PRIVILEGE=$(whiptail --title "Container Type" --menu "Choose container type:" 15 60 4 \
    "unprivileged" "Recommended for security" \
    "privileged" "Full container access" \
    3>&1 1>&2 2>&3)
    check_cancel
    log "Selected container type: $PRIVILEGE"
}

# Ask for Root Password
ask_password() {
    while true; do
        PASSWORD1=$(whiptail --passwordbox "Enter Root Password:" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        PASSWORD2=$(whiptail --passwordbox "Confirm Root Password:" 10 60 3>&1 1>&2 2>&3)
        check_cancel
        if [[ "$PASSWORD1" == "$PASSWORD2" ]]; then
            ROOT_PASSWORD="$PASSWORD1"
            log "Root password confirmed."
            break
        else
            whiptail --msgbox "Passwords do not match. Please try again." 8 45
        fi
    done
}

# Final Confirmation
final_confirm() {
    SUMMARY="Node: $NODE\nTemplate: $TEMPLATE\nCTID: $CTID\nName: $NAME\nStorage: $STORAGE\nCPU: $CPU_CORES\nMemory: $MEMORY_MB MB\nDisk: $DISK_GB GB\nNetworking: "
    if [ "$USE_DHCP" = true ]; then
        SUMMARY+="DHCP\n"
    else
        SUMMARY+="Static IP $STATIC_IP/$CIDR, Gateway $GATEWAY\n"
    fi
    SUMMARY+="VLAN ID: $VLAN_ID\nContainer Type: $PRIVILEGE"
    whiptail --title "Confirm Settings" --yesno "$SUMMARY\n\nProceed with container creation?" 20 78
    check_cancel
}

# Create the container
create_container() {
    log "Creating container..."

    # Build FQDN for inside the container
    HOSTNAME="$NAME"
    if [[ -n "$HOSTNAME_SUFFIX" ]]; then
        HOSTNAME="$NAME.$HOSTNAME_SUFFIX"
    fi

    NET_CONFIG="name=eth0,bridge=$DEFAULT_BRIDGE,tag=$VLAN_ID"
    if [ "$USE_DHCP" = true ]; then
        NET_CONFIG+=",ip=dhcp"
    else
        NET_CONFIG+=",ip=${STATIC_IP}/${CIDR},gw=${GATEWAY}"
    fi

    PRIV_FLAG=0
    if [[ "$PRIVILEGE" == "privileged" ]]; then
        PRIV_FLAG=1
    fi

    # Create the container with SHORT hostname (not FQDN)
    pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
      -hostname "$NAME" \
      -storage "$STORAGE" \
      -cores "$CPU_CORES" \
      -memory "$MEMORY_MB" \
      -net0 "$NET_CONFIG" \
      -rootfs "$STORAGE:$DISK_GB" \
      -password "$ROOT_PASSWORD" \
      -unprivileged "$((1 - PRIV_FLAG))" \
      --features "nesting=1" \
      --ostype unmanaged \
      --start 1

    log "Setting container internal hostname to FQDN ($HOSTNAME)..."
    pct exec "$CTID" -- hostnamectl set-hostname "$HOSTNAME"

    log "Detecting OS inside container..."
    OS_ID=$(pct exec "$CTID" -- bash -c "source /etc/os-release && echo \$ID")
    log "Detected OS: $OS_ID"

    if [[ "$OS_ID" == "ubuntu" ]]; then
        log "Configuring Netplan for Ubuntu container networking..."
        pct exec "$CTID" -- bash -c 'mkdir -p /etc/netplan && echo -e "network:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true" > /etc/netplan/01-netcfg.yaml'

        log "Checking if systemd-networkd is active before applying Netplan..."
        if pct exec "$CTID" -- systemctl is-active --quiet systemd-networkd; then
            log "systemd-networkd is active. Applying Netplan..."
            pct exec "$CTID" -- netplan apply
            log "Netplan applied successfully."
        else
            log "systemd-networkd is NOT active. Skipping Netplan apply inside container."
        fi

    elif [[ "$OS_ID" == "debian" ]]; then
        log "Checking if /etc/network/interfaces exists inside Debian container..."
        if ! pct exec "$CTID" -- grep -q "iface eth0" /etc/network/interfaces; then
            log "Creating minimal /etc/network/interfaces inside container..."
            pct exec "$CTID" -- bash -c 'echo -e "auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp" > /etc/network/interfaces'
        else
            log "/etc/network/interfaces already exists and eth0 configured."
        fi
        log "Bringing up eth0 inside Debian container..."
        pct exec "$CTID" -- bash -c 'ifup eth0 || systemctl restart networking'
    else
        log "WARNING: Unknown OS type ($OS_ID). Networking config skipped."
    fi

    log "Container $CTID created successfully."
    echo "Container $CTID ($NAME) has been created and started."
}




# ========== MAIN SCRIPT ==========

log "Starting Proxmox LXC Creator Script v$VERSION"
select_node
select_template
ask_ctid
ask_name
select_storage
ask_cpu
ask_ram
ask_disk
ask_network_type
ask_static_ip
ask_vlan
ask_privilege
ask_password
final_confirm
create_container

log "Script completed. Exiting."
exit 0
