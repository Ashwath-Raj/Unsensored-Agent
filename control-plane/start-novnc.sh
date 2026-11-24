#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then echo "VM SSH is offline. Run ./control-plane/start-vm.sh first." >&2; exit 1; fi
UNIT=unsensored-agent-novnc-tunnel.service
if systemctl --user is-active --quiet "$UNIT" && timeout 1 bash -c '</dev/tcp/127.0.0.1/6081' 2>/dev/null; then
  echo "Managed noVNC tunnel already active: http://127.0.0.1:6081/vnc.html?autoconnect=true"; exit 0
fi
# If an old manual tunnel owns 6081, stop only that exact SSH forwarding process.
if timeout 1 bash -c '</dev/tcp/127.0.0.1/6081' 2>/dev/null; then "$ROOT/control-plane/stop-novnc.sh" || true; fi
systemctl --user enable --now "$UNIT"
for _ in $(seq 1 20); do
  if timeout 1 bash -c '</dev/tcp/127.0.0.1/6081' 2>/dev/null; then echo "noVNC ready: http://127.0.0.1:6081/vnc.html?autoconnect=true"; exit 0; fi
  sleep 1
done
systemctl --user --no-pager --full status "$UNIT" || true
exit 1
