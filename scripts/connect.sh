#!/usr/bin/env bash
# Connect to the Paperclip server via Tailscale and open the UI.
# Usage: ./scripts/connect.sh
set -euo pipefail

HOSTNAME=$(terraform output -raw tailscale_url 2>/dev/null) || {
  echo "Error: could not read tailscale_url from Terraform state." >&2
  echo "Run 'terraform apply' first." >&2
  exit 1
}

echo "Paperclip UI: $HOSTNAME"
echo ""

# Check if the host is reachable via Tailscale
TS_HOST=$(echo "$HOSTNAME" | sed 's|http://||' | sed 's|:.*||')
if command -v tailscale &>/dev/null; then
  if tailscale ping --timeout=3s "$TS_HOST" &>/dev/null; then
    echo "Tailscale connection: OK"
  else
    echo "Warning: cannot reach $TS_HOST via Tailscale."
    echo "  - Is Tailscale running? (tailscale status)"
    echo "  - Has the EC2 instance finished setup? (./scripts/logs.sh)"
  fi
else
  echo "Note: tailscale CLI not found locally — verify connection manually."
fi

echo ""
echo "Open $HOSTNAME in your browser."
