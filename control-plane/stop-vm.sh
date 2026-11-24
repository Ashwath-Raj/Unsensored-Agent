#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
echo "===== Stop agent program before guest shutdown ====="
if ! "$ROOT/control-plane/stop-agent.sh"; then
  echo "Graceful program stop did not finish; attempting a bounded guest service stop..." >&2
  if timeout 4 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
    ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=6 \
      -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" \
      "${CONTROL_SSH_USER}@127.0.0.1" 'stop unsensored-agent.service' || true
  fi
fi
echo
echo "===== Stop browser viewer tunnel ====="
"$ROOT/control-plane/stop-novnc.sh" || true
echo
echo "===== Stop host-to-guest API/model tunnel ====="
systemctl --user stop unsensored-agent-tunnel.service 2>/dev/null || true
echo
echo "===== Power off VM ====="
"$ROOT/host/stop-vm.sh"
echo "VM stopped. Host control dashboard and host Ollama were not stopped."
