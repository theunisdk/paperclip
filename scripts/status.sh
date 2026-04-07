#!/usr/bin/env bash
# Check the health of all services on the Paperclip server via Tailscale.
# Usage: ./scripts/status.sh
set -euo pipefail

TS_HOST=$(terraform output -raw tailscale_ssh 2>/dev/null | sed 's|ssh ||') || {
  echo "Error: could not read outputs from Terraform state." >&2
  exit 1
}

ssh "$TS_HOST" << 'REMOTE'
echo "=== Tailscale ==="
tailscale status | head -5
echo ""

echo "=== Paperclip ==="
systemctl --user status paperclip --no-pager 2>/dev/null || echo "  (not running)"
echo ""

echo "=== OpenClaw Registry ==="
if [ -f ~/paperclip-workspaces/openclaw-registry.json ]; then
  python3 -c "
import json
with open('/home/ubuntu/paperclip-workspaces/openclaw-registry.json') as f:
    reg = json.load(f)
if not reg.get('instances'):
    print('  No agents provisioned yet.')
else:
    for inst in reg['instances']:
        print(f\"  {inst['name']} ({inst['profile']}) — port {inst['port']} — {inst['status']}\")
"
else
  echo "  Registry not found."
fi
echo ""

echo "=== System Resources ==="
free -h | head -2
echo ""
df -h / | tail -1 | awk '{print "  Disk: " $3 " used / " $2 " total (" $5 " used)"}'
REMOTE
