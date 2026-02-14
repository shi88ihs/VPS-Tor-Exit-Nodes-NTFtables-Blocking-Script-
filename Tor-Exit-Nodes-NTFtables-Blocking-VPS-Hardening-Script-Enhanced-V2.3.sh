#!/bin/bash

#############################################################################
# TorBlock - Professional Tor Exit Node Blocker
# Version: 2.3
# License: GPL-3.0
# Description: Automated Tor exit node blocking with nftables
#############################################################################

##Version 2.3 edited to fix ERROR: 

# Loaded 1326 IPv4 addresses (failed: 0)
# 1326: arithmetic syntax error: operand expected (error token is "ℹ  Loading IPv4 addresses...

##COMPLETED

set -euo pipefail

# Script metadata
VERSION="2.3"
SCRIPT_NAME="torblock"

# Default configuration
DEFAULT_CONFIG_DIR="/etc/torblock"
DEFAULT_CONFIG_FILE="${DEFAULT_CONFIG_DIR}/torblock.conf"
DEFAULT_DATA_DIR="/var/lib/torblock"
DEFAULT_LOG_FILE="/var/log/torblock.log"
DEFAULT_STATE_FILE="${DEFAULT_DATA_DIR}/state.json"

# Load configuration
CONFIG_DIR="${TORBLOCK_CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
CONFIG_FILE="${TORBLOCK_CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"
DATA_DIR="${TORBLOCK_DATA_DIR:-$DEFAULT_DATA_DIR}"
LOG_FILE="${TORBLOCK_LOG_FILE:-$DEFAULT_LOG_FILE}"
STATE_FILE="${DEFAULT_STATE_FILE}"

# Default values (can be overridden by config file)
NFT="/usr/sbin/nft"
TOR_LIST_URL="https://check.torproject.org/torbulkexitlist"
TOR_LIST_IPV6_URL="https://onionoo.torproject.org/details?flag=Exit"
TOR_LIST_FILE="${DATA_DIR}/tor-exit-nodes.txt"
TOR_LIST_IPV6_FILE="${DATA_DIR}/tor-exit-nodes-ipv6.txt"
TABLE="filter"
CHAIN="input"
SET_IPV4="torlist"
SET_IPV6="torlist6"
UPDATE_INTERVAL="daily"
LOG_LEVEL="info"
# IPv6 is disabled by default due to API timeout issues
ENABLE_IPV6="false"
ENABLE_SYSLOG="true"

#############################################################################
# Logging Functions
#############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # # Console output with colors
    # case "$level" in
    #     ERROR)   echo -e "\e[31m❌ $message\e[0m" ;;
    #     SUCCESS) echo -e "\e[32m✅ $message\e[0m" ;;
    #     INFO)    echo -e "\e[34mℹ️  $message\e[0m" ;;
    #     WARN)    echo -e "\e[33m⚠️  $message\e[0m" ;;
    #     *)       echo "$message" ;;
    # esac

    # Console output with colors (goes to stdout or can be redirected)
   case "$level" in
    ERROR)   echo -e "\e[31m❌ $message\e[0m" >&2 ;;
    SUCCESS) echo -e "\e[32m✅ $message\e[0m" >&2 ;;
    INFO)    echo -e "\e[34mℹ️  $message\e[0m" >&2 ;;
    WARN)    echo -e "\e[33m⚠️  $message\e[0m" >&2 ;;
    *)       echo "$message" >&2 ;;
esac

    
    # File logging
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    # Syslog
    if [ "$ENABLE_SYSLOG" = "true" ]; then
        logger -t "$SCRIPT_NAME" -p "user.$level" "$message" 2>/dev/null || true
    fi
}

#############################################################################
# Helper Functions
#############################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log ERROR "This script must be run as root. Use sudo."
        exit 1
    fi
}

check_dependencies() {
    log INFO "Checking dependencies..."
    
    local missing=()
    
    if ! command -v nft >/dev/null 2>&1; then
        missing+=("nftables")
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log ERROR "Missing dependencies: ${missing[*]}"
        log ERROR "Install with: apt install ${missing[*]}"
        exit 1
    fi
    
    log SUCCESS "All dependencies are installed"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log INFO "Loading configuration from $CONFIG_FILE"
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

create_directories() {
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true
}

save_state() {
    local ipv4_count=$1
    local ipv6_count=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$STATE_FILE" <<EOF
{
    "version": "$VERSION",
    "last_update": "$timestamp",
    "ipv4_blocked": $ipv4_count,
    "ipv6_blocked": $ipv6_count,
    "total_blocked": $((ipv4_count + ipv6_count))
}
EOF
}

#############################################################################
# Download Functions
#############################################################################

download_tor_list() {
    log INFO "Downloading Tor exit node list (IPv4)..."
    
    if curl -sf "$TOR_LIST_URL" -o "$TOR_LIST_FILE"; then
        local count=$(grep -c -E '([0-9]{1,3}\.){3}[0-9]{1,3}' "$TOR_LIST_FILE" || echo 0)
        log SUCCESS "Downloaded $count IPv4 addresses"
        return 0
    else
        log ERROR "Failed to download Tor exit node list"
        return 1
    fi
}

download_tor_list_ipv6() {
    if [ "$ENABLE_IPV6" != "true" ]; then
        return 0
    fi
    
    log INFO "Downloading Tor exit node list (IPv6)..."
    
    if curl -sf "$TOR_LIST_IPV6_URL" -o "${TOR_LIST_IPV6_FILE}.json"; then
        # Extract IPv6 addresses from JSON
        grep -oE '"or_addresses":\["[^"]+"]' "${TOR_LIST_IPV6_FILE}.json" | \
            grep -oE '\[([0-9a-fA-F:]+)\]' | \
            tr -d '[]' | \
            sort -u > "$TOR_LIST_IPV6_FILE"
        
        local count=$(wc -l < "$TOR_LIST_IPV6_FILE" || echo 0)
        log SUCCESS "Downloaded $count IPv6 addresses"
        rm -f "${TOR_LIST_IPV6_FILE}.json"
        return 0
    else
        log WARN "Failed to download IPv6 list (continuing without IPv6)"
        return 0
    fi
}

#############################################################################
# nftables Functions
#############################################################################

setup_nftables() {
    log INFO "Setting up nftables..."
    
    # Clean slate
    $NFT delete table inet $TABLE 2>/dev/null || true
    
    # Create table
    if ! $NFT add table inet $TABLE; then
        log ERROR "Failed to create table"
        return 1
    fi
    
    # Create chain
    if ! $NFT add chain inet $TABLE $CHAIN '{ type filter hook input priority 0; policy accept; }'; then
        log ERROR "Failed to create chain"
        return 1
    fi
    
    # Create IPv4 set
    if ! $NFT add set inet $TABLE $SET_IPV4 '{ type ipv4_addr; }'; then
        log ERROR "Failed to create IPv4 set"
        return 1
    fi
    
    # Create IPv6 set if enabled
    if [ "$ENABLE_IPV6" = "true" ]; then
        if ! $NFT add set inet $TABLE $SET_IPV6 '{ type ipv6_addr; }'; then
            log ERROR "Failed to create IPv6 set"
            return 1
        fi
    fi
    
    log SUCCESS "nftables setup complete"
}

# load_ipv4_addresses() {
#     if [ ! -f "$TOR_LIST_FILE" ]; then
#         log ERROR "IPv4 list file not found: $TOR_LIST_FILE" >&2
#         echo "0"
#         return 1
#     fi
    
#     log INFO "Loading IPv4 addresses..." >&2
    
#     readarray -t IP_ARRAY < <(grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$TOR_LIST_FILE" | sort -u)
    
#     if [ ${#IP_ARRAY[@]} -eq 0 ]; then
#         log WARN "No valid IPv4 addresses found" >&2
#         echo "0"
#         return 0
#     fi
    
#     local loaded=0
#     local failed=0
    
#     for ip in "${IP_ARRAY[@]}"; do
#         if $NFT add element inet $TABLE $SET_IPV4 "{ $ip }" 2>/dev/null; then
#             ((loaded++))
#             if [ $((loaded % 100)) -eq 0 ]; then
#                 log INFO "Loaded $loaded IPv4 addresses..." >&2
#             fi
#         else
#             ((failed++))
#         fi
#     done
    
#     log SUCCESS "Loaded $loaded IPv4 addresses (failed: $failed)" >&2
#     echo "$loaded"
# }

#################################################

load_ipv4_addresses() {
    if [ ! -f "$TOR_LIST_FILE" ]; then
        log ERROR "IPv4 list file not found: $TOR_LIST_FILE"
        return 1
    fi
    
    # Log to stderr so it doesn't interfere with the return value
    log INFO "Loading IPv4 addresses..." 1>&2
    
    readarray -t IP_ARRAY < <(grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$TOR_LIST_FILE" | sort -u)
    
    if [ ${#IP_ARRAY[@]} -eq 0 ]; then
        log WARN "No valid IPv4 addresses found" 1>&2
        echo "0"
        return 0
    fi
    
    local loaded=0
    local failed=0
    
    for ip in "${IP_ARRAY[@]}"; do
        if $NFT add element inet $TABLE $SET_IPV4 "{ $ip }" 2>/dev/null; then
            ((loaded++))
            if [ $((loaded % 100)) -eq 0 ]; then
                # Send progress to stderr, not stdout
                log INFO "Loaded $loaded IPv4 addresses..." 1>&2
            fi
        else
            ((failed++))
        fi
    done
    
    # Send final message to stderr
    log SUCCESS "Loaded $loaded IPv4 addresses (failed: $failed)" 1>&2
    
    # ONLY output the number to stdout (this is what gets captured)
    echo "$loaded"
}

#################################################

# load_ipv6_addresses() {
#     if [ "$ENABLE_IPV6" != "true" ]; then
#         echo "0"
#         return 0
#     fi
    
#     if [ ! -f "$TOR_LIST_IPV6_FILE" ]; then
#         log WARN "IPv6 list file not found" >&2
#         echo "0"
#         return 0
#     fi
    
#     log INFO "Loading IPv6 addresses..." >&2
    
#     readarray -t IP_ARRAY < <(grep -Eo '([0-9a-fA-F:]+)' "$TOR_LIST_IPV6_FILE" | sort -u)
    
#     if [ ${#IP_ARRAY[@]} -eq 0 ]; then
#         log WARN "No valid IPv6 addresses found" >&2
#         echo "0"
#         return 0
#     fi
    
#     local loaded=0
#     local failed=0
    
#     for ip in "${IP_ARRAY[@]}"; do
#         if $NFT add element inet $TABLE $SET_IPV6 "{ $ip }" 2>/dev/null; then
#             ((loaded++))
#             if [ $((loaded % 50)) -eq 0 ]; then
#                 log INFO "Loaded $loaded IPv6 addresses..." >&2
#             fi
#         else
#             ((failed++))
#         fi
#     done
    
#     log SUCCESS "Loaded $loaded IPv6 addresses (failed: $failed)" >&2
#     echo "$loaded"
# }

#################################################

load_ipv6_addresses() {
    if [ "$ENABLE_IPV6" != "true" ]; then
        echo "0"
        return 0
    fi
    
    if [ ! -f "$TOR_LIST_IPV6_FILE" ]; then
        log WARN "IPv6 list file not found" 1>&2
        echo "0"
        return 0
    fi
    
    log INFO "Loading IPv6 addresses..." 1>&2
    
    readarray -t IP_ARRAY < <(grep -Eo '([0-9a-fA-F:]+)' "$TOR_LIST_IPV6_FILE" | sort -u)
    
    if [ ${#IP_ARRAY[@]} -eq 0 ]; then
        log WARN "No valid IPv6 addresses found" 1>&2
        echo "0"
        return 0
    fi
    
    local loaded=0
    local failed=0
    
    for ip in "${IP_ARRAY[@]}"; do
        if $NFT add element inet $TABLE $SET_IPV6 "{ $ip }" 2>/dev/null; then
            ((loaded++))
            if [ $((loaded % 50)) -eq 0 ]; then
                log INFO "Loaded $loaded IPv6 addresses..." 1>&2
            fi
        else
            ((failed++))
        fi
    done
    
    log SUCCESS "Loaded $loaded IPv6 addresses (failed: $failed)" 1>&2
    echo "$loaded"
}

#################################################

add_firewall_rules() {
    log INFO "Adding firewall rules..."
    
    # IPv4 rule
    if ! $NFT add rule inet $TABLE $CHAIN ip saddr @$SET_IPV4 drop; then
        log ERROR "Failed to add IPv4 drop rule"
        return 1
    fi
    
    # IPv6 rule
    if [ "$ENABLE_IPV6" = "true" ]; then
        if ! $NFT add rule inet $TABLE $CHAIN ip6 saddr @$SET_IPV6 drop; then
            log ERROR "Failed to add IPv6 drop rule"
            return 1
        fi
    fi
    
    log SUCCESS "Firewall rules added"
}

#############################################################################
# Command Handlers
#############################################################################

cmd_install() {
    log INFO "Installing TorBlock..."
    check_root
    check_dependencies
    create_directories
    
    # Create default config file if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        log INFO "Creating default configuration..."
        cat > "$CONFIG_FILE" <<EOF
# TorBlock Configuration File
# Generated on $(date)

# Tor exit node list URLs
TOR_LIST_URL="https://check.torproject.org/torbulkexitlist"
TOR_LIST_IPV6_URL="https://onionoo.torproject.org/details?flag=Exit"

# Update interval (daily, hourly, weekly)
UPDATE_INTERVAL="daily"

# Enable IPv6 blocking (disabled by default due to API timeout issues)
ENABLE_IPV6="false"

# Logging
LOG_LEVEL="info"
ENABLE_SYSLOG="true"

# nftables configuration
TABLE="filter"
CHAIN="input"
SET_IPV4="torlist"
SET_IPV6="torlist6"
EOF
        log SUCCESS "Configuration file created at $CONFIG_FILE"
    fi
    
    # Copy script to /usr/local/bin if not already there
    if [ ! -f "/usr/local/bin/$SCRIPT_NAME" ]; then
        cp "$0" "/usr/local/bin/$SCRIPT_NAME"
        chmod +x "/usr/local/bin/$SCRIPT_NAME"
        log SUCCESS "Script installed to /usr/local/bin/$SCRIPT_NAME"
    fi
    
    # Create systemd service
    create_systemd_service
    
    log SUCCESS "Installation complete! Run 'torblock --update' to download and block Tor nodes"
}

cmd_uninstall() {
    log INFO "Uninstalling TorBlock..."
    check_root
    
    # Stop and disable service
    systemctl stop torblock.service 2>/dev/null || true
    systemctl disable torblock.service 2>/dev/null || true
    systemctl stop torblock.timer 2>/dev/null || true
    systemctl disable torblock.timer 2>/dev/null || true
    
    # Remove nftables rules
    $NFT delete table inet $TABLE 2>/dev/null || true
    log SUCCESS "Removed firewall rules"
    
    # Remove systemd files
    rm -f /etc/systemd/system/torblock.service
    rm -f /etc/systemd/system/torblock.timer
    systemctl daemon-reload
    
    # Ask before removing data
    read -p "Remove configuration and data files? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR" "$DATA_DIR"
        rm -f "$LOG_FILE"
        log SUCCESS "Configuration and data removed"
    fi
    
    log SUCCESS "Uninstallation complete"
}

cmd_update() {
    log INFO "Updating Tor exit node blocklist..."
    check_root
    check_dependencies
    create_directories
    load_config
    
    # Download lists
    download_tor_list || exit 1
    download_tor_list_ipv6
    
    # Setup nftables
    setup_nftables || exit 1
    
    # # Load addresses
    # ipv4_count=$(load_ipv4_addresses)
    # ipv6_count=$(load_ipv6_addresses)

    # Load addresses
  # Load addresses
    load_ipv4_addresses > /tmp/torblock_ipv4_count.tmp 2>&1
    ipv4_count=$(tail -1 /tmp/torblock_ipv4_count.tmp)
    
    load_ipv6_addresses > /tmp/torblock_ipv6_count.tmp 2>&1
    ipv6_count=$(tail -1 /tmp/torblock_ipv6_count.tmp)
    
    rm -f /tmp/torblock_ipv4_count.tmp /tmp/torblock_ipv6_count.tmp
    
    # Add firewall rules
    add_firewall_rules || exit 1
    
    # Save state
    save_state "$ipv4_count" "$ipv6_count"
    
    log SUCCESS "Update complete! Blocking $ipv4_count IPv4 and $ipv6_count IPv6 addresses"
}

cmd_status() {
    log INFO "TorBlock Status"
    echo ""
    
    # Check if table exists
    if ! $NFT list table inet $TABLE >/dev/null 2>&1; then
        log WARN "TorBlock is not active (table not found)"
        echo ""
        echo "Run 'torblock --update' to activate blocking"
        exit 0
    fi
    
    # Read state file
    if [ -f "$STATE_FILE" ]; then
        echo "Last Update: $(jq -r '.last_update' "$STATE_FILE" 2>/dev/null || echo "Unknown")"
        echo "IPv4 Blocked: $(jq -r '.ipv4_blocked' "$STATE_FILE" 2>/dev/null || echo "0")"
        echo "IPv6 Blocked: $(jq -r '.ipv6_blocked' "$STATE_FILE" 2>/dev/null || echo "0")"
        echo "Total Blocked: $(jq -r '.total_blocked' "$STATE_FILE" 2>/dev/null || echo "0")"
    else
        echo "No state file found"
    fi
    
    echo ""
    echo "=== nftables Rules ==="
    $NFT list chain inet $TABLE $CHAIN 2>/dev/null || echo "No rules found"
}

cmd_stats() {
    cmd_status
    
    echo ""
    echo "=== Firewall Statistics ==="
    
    # Get packet/byte counters (this requires nftables to have counters enabled)
    $NFT -j list ruleset | grep -A 5 "$SET_IPV4" 2>/dev/null || echo "Statistics not available"
}

cmd_help() {
    cat <<EOF
TorBlock v$VERSION - Professional Tor Exit Node Blocker

USAGE:
    torblock [COMMAND]

COMMANDS:
    --install       Install TorBlock and create configuration
    --uninstall     Remove TorBlock and optionally delete data
    --update        Download latest Tor lists and update firewall rules
    --status        Show current blocking status
    --stats         Show detailed statistics
    --help          Show this help message
    --version       Show version information

EXAMPLES:
    # Initial installation
    sudo torblock --install
    
    # Activate blocking
    sudo torblock --update
    
    # Check status
    sudo torblock --status
    
    # View statistics
    sudo torblock --stats

FILES:
    $CONFIG_FILE       Configuration file
    $DATA_DIR          Data directory
    $LOG_FILE          Log file
    $STATE_FILE        State file

For more information, visit:
    https://github.com/shi88ihs/VPS-Tor-Exit-Nodes-NTFtables-Blocking-Script

EOF
}

create_systemd_service() {
    log INFO "Creating systemd service..."
    
    # Service file
    cat > /etc/systemd/system/torblock.service <<EOF
[Unit]
Description=TorBlock - Block Tor Exit Nodes
After=network.target nftables.service
Wants=nftables.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/torblock --update
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Timer file
    cat > /etc/systemd/system/torblock.timer <<EOF
[Unit]
Description=TorBlock Daily Update Timer
Requires=torblock.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable torblock.timer
    systemctl start torblock.timer
    
    log SUCCESS "Systemd service created and enabled"
}

#############################################################################
# Main
#############################################################################

main() {
    # Parse command
    case "${1:-}" in
        --install)
            cmd_install
            ;;
        --uninstall)
            cmd_uninstall
            ;;
        --update)
            cmd_update
            ;;
        --status)
            cmd_status
            ;;
        --stats)
            cmd_stats
            ;;
        --version)
            echo "TorBlock v$VERSION"
            ;;
        --help|"")
            cmd_help
            ;;
        *)
            log ERROR "Unknown command: $1"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
