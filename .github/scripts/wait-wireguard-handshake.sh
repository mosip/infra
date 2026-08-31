#!/bin/bash
# Wait until a WireGuard interface completes a handshake.
#
# Usage: ./wait-wireguard-handshake.sh <iface> [timeout-seconds]

set -euo pipefail

SCRIPT_NAME="wait-wireguard-handshake.sh"
IFACE="${1:-wg0}"
TIMEOUT="${2:-60}"

echo "[$SCRIPT_NAME] Waiting up to ${TIMEOUT}s for handshake on $IFACE..."
sudo wg show "$IFACE" || true

elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  if sudo wg show "$IFACE" | grep -q "latest handshake"; then
    echo "[$SCRIPT_NAME] ✅ Handshake established"
    sudo wg show "$IFACE"
    exit 0
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "[$SCRIPT_NAME] ❌ No handshake on $IFACE after ${TIMEOUT}s"
sudo wg show "$IFACE" || true
echo "The VPN interface is up but the peer is not responding."
echo "Check the WireGuard environment secret (endpoint IP/port and keys)"
echo "and that the jump server WireGuard service is running."
exit 1
