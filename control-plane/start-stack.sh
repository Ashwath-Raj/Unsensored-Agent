#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Dashboard comes up first so the operator can inspect startup or failure states.
if ! curl --silent --fail --max-time 2 http://127.0.0.1:8766/api/control/overview >/dev/null 2>&1; then
  "$ROOT/control-plane/start-dashboard.sh"
fi
"$ROOT/control-plane/start-vm.sh"
"$ROOT/control-plane/start-novnc.sh"
"$ROOT/control-plane/start-agent.sh"
echo
echo "Stack ready:"
echo "  Control Room: http://127.0.0.1:8766"
echo "  Agent API:    http://127.0.0.1:8765/docs"
echo "  VM desktop:   http://127.0.0.1:6081/vnc.html?autoconnect=true"
