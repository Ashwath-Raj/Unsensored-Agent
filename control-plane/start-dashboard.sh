#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! systemctl --user cat unsensored-agent-control-dashboard.service >/dev/null 2>&1; then
  echo "Control-plane service is not installed. Run ./control-plane/install.sh first." >&2; exit 1
fi
systemctl --user enable --now unsensored-agent-control-dashboard.service
for _ in $(seq 1 20); do
  if curl -fsS --max-time 2 http://127.0.0.1:8766/api/control/overview >/dev/null 2>&1; then
    echo "Dashboard running: http://127.0.0.1:8766"; exit 0
  fi
  sleep 0.5
done
systemctl --user --no-pager --full status unsensored-agent-control-dashboard.service || true
exit 1
