#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then echo "VM SSH is offline; start the VM first." >&2; exit 1; fi
# Avoid restarting the agent halfway through a model call.
if curl --silent --fail --max-time 3 http://127.0.0.1:8765/health >/dev/null 2>&1; then
  active="$(python3 - <<'PY'
import json,urllib.request
try:
 with urllib.request.urlopen('http://127.0.0.1:8765/tasks',timeout=4) as r: tasks=json.load(r)
 print('yes' if any(t.get('status') in ('queued','running') for t in tasks) else 'no')
except Exception: print('unknown')
PY
)"
  if [[ "$active" == yes ]]; then echo "Active tasks detected. Stop/interrupt them before repairing screenshot dependencies." >&2; exit 2; fi
fi
ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" \
  "${CONTROL_SSH_USER}@127.0.0.1" 'repair-screenshot'

echo "Screenshot dependencies repaired and agent service restarted. Test desktop_screenshot before retrying GUI tasks."
