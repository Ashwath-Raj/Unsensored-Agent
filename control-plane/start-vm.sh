#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
"$ROOT/host/start-vm.sh"
echo "Waiting for guest SSH..."
ready=0
for _ in $(seq 1 90); do
  if timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then ready=1; break; fi
  sleep 2
done
if [[ "$ready" != 1 ]]; then echo "Guest SSH did not become available. Inspect vm/serial.log." >&2; exit 1; fi
for unit in unsensored-agent-proxy.service unsensored-agent-tunnel.service; do
  if systemctl --user cat "$unit" >/dev/null 2>&1; then systemctl --user start "$unit"; fi
done
ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" \
  "${CONTROL_SSH_USER}@127.0.0.1" 'start agent-desktop.service agent-vnc.service agent-novnc.service'
echo "VM and isolated desktop are up. The agent program is a separate service."
