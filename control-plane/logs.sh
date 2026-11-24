#!/usr/bin/env bash
set -euo pipefail
case "${1:-dashboard}" in
  dashboard) exec journalctl --user -u unsensored-agent-control-dashboard.service -f ;;
  tunnel) exec journalctl --user -u unsensored-agent-tunnel.service -f ;;
  novnc) exec journalctl --user -u unsensored-agent-novnc-tunnel.service -f ;;
  agent) ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$ROOT/host/config.sh"; exec ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "${SSH_USER}@127.0.0.1" 'sudo journalctl -u unsensored-agent.service -f' ;;
  *) echo "Usage: $0 [dashboard|tunnel|novnc|agent]" >&2; exit 2;;
esac
