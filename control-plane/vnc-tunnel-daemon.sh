#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
exec /usr/bin/ssh -N \
  -i "$SSH_KEY" -p "$SSH_PORT" \
  -o BatchMode=yes -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" \
  -L 127.0.0.1:6081:127.0.0.1:6080 "${SSH_USER}@127.0.0.1"
