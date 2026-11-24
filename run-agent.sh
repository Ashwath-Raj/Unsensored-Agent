#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$ROOT/control-plane/start-stack.sh" ]] || ! systemctl --user cat unsensored-agent-control-dashboard.service >/dev/null 2>&1; then
  echo "Control Room is not installed. Run the downloaded package's install-and-run.sh first." >&2
  exit 2
fi
open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    xdg-open "$url" >/dev/null 2>&1 & disown || true
  else
    echo "Open in browser: $url"
  fi
}
# Open the control room early so the operator can watch startup and read errors.
"$ROOT/control-plane/start-dashboard.sh"
open_url "http://127.0.0.1:8766"
"$ROOT/control-plane/start-stack.sh"
open_url "http://127.0.0.1:6081/vnc.html?autoconnect=true"
echo
echo "Ready. Keep the browser tabs; services run independently in systemd."
echo "Dashboard: http://127.0.0.1:8766"
echo "VM desktop: http://127.0.0.1:6081/vnc.html?autoconnect=true"
echo "Agent API docs: http://127.0.0.1:8765/docs"
