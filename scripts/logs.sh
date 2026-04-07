#!/usr/bin/env bash
# Tail the cloud-init setup log via Tailscale (useful during first boot).
# Usage: ./scripts/logs.sh
set -euo pipefail

TS_HOST=$(terraform output -raw tailscale_ssh 2>/dev/null | sed 's|ssh ||') || {
  echo "Error: could not read outputs from Terraform state." >&2
  exit 1
}

ssh "$TS_HOST" tail -f /var/log/paperclip-setup.log
