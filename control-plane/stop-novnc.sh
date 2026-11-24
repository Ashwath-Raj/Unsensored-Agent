#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now unsensored-agent-novnc-tunnel.service 2>/dev/null || true
# Also stop the exact manually-launched noVNC SSH forward, if the user was previously running one in a terminal.
python3 <<'PY'
import os, signal
needle=b'127.0.0.1:6081:127.0.0.1:6080'
me=os.getpid(); killed=[]
for item in os.listdir('/proc'):
 if not item.isdigit(): continue
 pid=int(item)
 if pid in (me,os.getppid()): continue
 try:
  raw=open(f'/proc/{pid}/cmdline','rb').read()
  args=raw.split(b'\0')
  if needle in raw and args and (b'ssh' in os.path.basename(args[0]) or any(b'/ssh' in x for x in args[:2])):
   os.kill(pid,signal.SIGTERM); killed.append(pid)
 except (OSError,ProcessLookupError): pass
if killed: print('Stopped matching manual noVNC tunnel PID(s):',', '.join(map(str,killed)))
PY
echo "noVNC SSH tunnel stopped. VM, agent program and dashboard remain running."
