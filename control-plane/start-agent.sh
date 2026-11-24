#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"

if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
  echo "VM SSH is offline. Start it first: ./control-plane/start-vm.sh" >&2
  exit 1
fi

# Host proxy and SSH fabric are dependencies of the guest agent. Only start
# known units from this kit; leave the host Ollama service untouched.
for unit in unsensored-agent-proxy.service unsensored-agent-tunnel.service; do
  if systemctl --user cat "$unit" >/dev/null 2>&1; then
    systemctl --user start "$unit"
  fi
done

ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" \
  -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" \
  "${CONTROL_SSH_USER}@127.0.0.1" \
  'start agent-desktop.service agent-vnc.service agent-novnc.service unsensored-agent.service'

for _ in $(seq 1 45); do
  if curl --silent --fail --max-time 2 http://127.0.0.1:8765/health >/dev/null 2>&1; then
    echo "Agent API is healthy on 127.0.0.1:8765."
    echo "Host control room: http://127.0.0.1:8766"
    exit 0
  fi
  sleep 1
done

echo "Agent start was requested but health did not become ready within 45 seconds." >&2
ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=6 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" \
  "${CONTROL_SSH_USER}@127.0.0.1" \
  'logs unsensored-agent.service 45' >&2 || true
exit 1
