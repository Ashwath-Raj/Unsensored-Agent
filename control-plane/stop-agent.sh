#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/host/config.sh"
WAIT_SECONDS="${STOP_WAIT_SECONDS:-120}"
CONTROL_SSH=(ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$CONTROL_SSH_KNOWN_HOSTS" "${CONTROL_SSH_USER}@127.0.0.1")

if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
  echo "VM SSH is offline; the agent cannot be controlled remotely." >&2
  exit 2
fi

# Request cooperative checkpoints while the API is reachable.
if curl --silent --fail --max-time 4 http://127.0.0.1:8765/health >/dev/null 2>&1; then
  echo "Requesting stop for queued/running tasks..."
  python3 - "$WAIT_SECONDS" <<'PY'
import json,sys,time,urllib.request,urllib.error
base='http://127.0.0.1:8765'; wait=max(0,int(sys.argv[1]))
def req(path,method='GET',payload=None):
    data=None if payload is None else json.dumps(payload).encode()
    r=urllib.request.Request(base+path,data=data,headers={'Content-Type':'application/json'},method=method)
    with urllib.request.urlopen(r,timeout=8) as x: return json.loads(x.read().decode())
try: tasks=req('/tasks')
except Exception as e: print(f'Could not read task list: {e}; will still stop the agent service.',flush=True); tasks=[]
active=[t for t in tasks if t.get('status') in ('queued','running')]
for t in active:
    try: req(f"/tasks/{t['id']}/stop",'POST',{}) ; print(f"Stop requested: {t['id']}",flush=True)
    except Exception as e: print(f"Stop request failed for {t.get('id')}: {e}",flush=True)
end=time.monotonic()+wait
while active and time.monotonic()<end:
    time.sleep(5)
    try: tasks=req('/tasks')
    except Exception as e: print(f'API poll failed: {e}',flush=True); continue
    active=[t for t in tasks if t.get('status') in ('queued','running')]
    if active: print('Waiting for current model call/checkpoint: '+', '.join(f"{t['id']}={t['status']}" for t in active),flush=True)
if active:
    print(f'Graceful window ({wait}s) elapsed; stopping the agent service now. Latest persisted checkpoints should be used on restart.',flush=True)
else:
    print('No queued/running tasks remain.',flush=True)
PY
else
  echo "Guest API is unavailable; skipping task stop requests and stopping the service through SSH."
fi

# The installer adds a 15-second service stop budget so this cannot wait forever.
"${CONTROL_SSH[@]}" 'stop unsensored-agent.service'
state=$("${CONTROL_SSH[@]}" 'is-active unsensored-agent.service' 2>/dev/null || true)
echo "Agent service state: ${state:-unknown}"
test "$state" != active
echo "Agent program stopped. VM desktop, VM power state, control dashboard and host Ollama were left running."
