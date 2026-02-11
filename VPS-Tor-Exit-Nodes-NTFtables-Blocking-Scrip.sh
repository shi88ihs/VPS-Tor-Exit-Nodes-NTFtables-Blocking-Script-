#!/bin/bash
##By A. Walker - awalker {at} wegrid {dot} org
##Made for Alpine Linux VPS Web server Hardening

# Config
NFT="/usr/sbin/nft"
TOR_LIST="./tor-exit-nodes.txt"
TABLE="filter"  # Use simple table name instead of "inet"
CHAIN="input"
SET="torlist"

echo "=== Starting Tor blocking script ==="

# Safety check
if [ ! -f "$TOR_LIST" ]; then
    echo "❌ File not found: $TOR_LIST"
    exit 1
fi

# Test nftables basic functionality
echo "Testing nftables..."
if ! $NFT list tables >/dev/null 2>&1; then
    echo "❌ nftables not working or permission denied. Run as root!"
    exit 1
fi
echo "✅ nftables is working"

# Clean slate - remove any existing table with this name
echo "Cleaning up existing table..."
$NFT delete table inet $TABLE 2>/dev/null || true

# Create table
echo "Creating table inet $TABLE..."
if ! $NFT add table inet $TABLE; then
    echo "❌ Failed to create table"
    exit 1
fi
echo "✅ Table created"

# Create chain
echo "Creating chain..."
if ! $NFT add chain inet $TABLE $CHAIN '{ type filter hook input priority 0; policy accept; }'; then
    echo "❌ Failed to create chain"
    exit 1
fi
echo "✅ Chain created"

# Create set
echo "Creating IP set..."
if ! $NFT add set inet $TABLE $SET '{ type ipv4_addr; }'; then
    echo "❌ Failed to create set"
    exit 1
fi
echo "✅ Set created"

# Test with single IP first
echo "Testing with single IP..."
if ! $NFT add element inet $TABLE $SET '{ 1.1.1.1 }'; then
    echo "❌ Failed to add test IP"
    exit 1
fi
echo "✅ Test IP added successfully"

# Clear test IP
$NFT flush set inet $TABLE $SET

# Load real IPs
echo "Loading Tor exit node IPs..."
readarray -t IP_ARRAY < <(grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$TOR_LIST" | sort -u)

if [ ${#IP_ARRAY[@]} -eq 0 ]; then
    echo "⚠️ No valid IPs found in $TOR_LIST"
    exit 1
fi

echo "Found ${#IP_ARRAY[@]} unique IP addresses"

LOADED=0
FAILED=0

for ip in "${IP_ARRAY[@]}"; do
    if $NFT add element inet $TABLE $SET "{ $ip }" 2>/dev/null; then
        ((LOADED++))
        if [ $((LOADED % 100)) -eq 0 ]; then
            echo "Loaded $LOADED IPs..."
        fi
    else
        ((FAILED++))
        if [ $FAILED -le 3 ]; then  # Show first 3 failures only
            echo "⚠️ Failed to load IP: $ip"
        fi
    fi
done

echo ""
echo "✅ Successfully loaded $LOADED IPs into set"
if [ $FAILED -gt 0 ]; then
    echo "⚠️ Failed to load $FAILED IPs"
fi

# Add drop rule
if [ "$LOADED" -gt 0 ]; then
    echo "Adding drop rule..."
    if $NFT add rule inet $TABLE $CHAIN ip saddr @$SET drop; then
        echo "✅ Drop rule added successfully"
    else
        echo "❌ Failed to add drop rule"
        exit 1
    fi
else
    echo "❌ No IPs loaded, not adding drop rule"
    exit 1
fi

echo ""
echo "=== FINAL STATUS ==="
echo "Table: inet $TABLE"
echo "Chain: $CHAIN"
echo "Set: $SET"
echo "IPs loaded: $LOADED"
echo "IPs failed: $FAILED"

echo ""
echo "=== Verification ==="
echo "Set contains $(nft list set inet $TABLE $SET | grep -c elements) element(s)"
echo ""
echo "Chain rules:"
$NFT list chain inet $TABLE $CHAIN

echo ""
echo "🎉 Tor exit nodes are now being blocked!"
echo ""
echo "To remove the blocks later, run:"
echo "  nft delete table inet $TABLE"
