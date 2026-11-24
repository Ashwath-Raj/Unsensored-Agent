#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
  echo "VM SSH is offline; cannot interrupt guest agent." >&2; exit 2
fi
if curl --silent --fail --max-time 3 http://127.0.0.1:8765/health >/dev/null 2>&1; then
  python3 <<'PY'
import json,urllib.request
base='http://127.0.0.1:8765'
def req(path,method='GET',payload=None):
    data=None if payload is None else json.dumps(payload).encode()
    r=urllib.request.Request(base+path,data=data,headers={'Content-Type':'application/json'},method=method)
    with urllib.request.urlopen(r,timeout=5) as x:return json.loads(x.read().decode())
try:
    for t in req('/tasks'):
        if t.get('status') in ('queued','running'):
            try: req(f"/tasks/{t['id']}/stop",'POST',{}); print('Stop requested:',t['id'])
            except Exception as e: print('Could not request task stop:',t.get('id'),e)
except Exception as e: print('Task-list request failed; stopping service directly:',e)
PY
fi
ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" \
  "${CONTROL_SSH_USER}@127.0.0.1" 'stop unsensored-agent.service'
state=$(ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" "${CONTROL_SSH_USER}@127.0.0.1" 'is-active unsensored-agent.service' 2>/dev/null || true)
echo "Agent service state: ${state:-unknown}"
test "$state" != active
echo "Agent interrupted. A model request may have been cut off; the VM and dashboard remain running."
