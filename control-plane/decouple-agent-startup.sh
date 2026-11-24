#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
[[ -f "$SSH_KEY" ]] || { echo "SSH key not found: $SSH_KEY" >&2; exit 1; }
ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" "${CONTROL_SSH_USER}@127.0.0.1" \
  'disable unsensored-agent.service'
echo "Agent is disabled at VM boot but was not stopped. Start it separately using ./control-plane/start-agent.sh."
