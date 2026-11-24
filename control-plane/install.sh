#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CP="$ROOT/control-plane"
USER_UNITS="$HOME/.config/systemd/user"
STATE="$HOME/.local/state/unsensored-agent-control"
mkdir -p "$USER_UNITS" "$STATE/actions"
chmod +x "$CP"/*.sh "$ROOT"/run-agent.sh "$ROOT"/stop-agent-stack.sh "$ROOT"/status-agent.sh 2>/dev/null || true

# Ensure user services survive terminal closure/reboot on this same host login.
if ! loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
  sudo loginctl enable-linger "$USER"
fi

# systemd understands \x20 escapes inside ExecStart/WorkingDirectory paths with spaces.
SYSROOT="$(python3 -c 'import sys; print(sys.argv[1].replace("\\", "\\\\").replace(" ", "\\x20"))' "$ROOT")"
cat > "$USER_UNITS/unsensored-agent-control-dashboard.service" <<UNIT
[Unit]
Description=Unsensored Agent Host Control Room Dashboard
After=default.target

[Service]
Type=simple
WorkingDirectory=${SYSROOT}/control-plane
Environment=UNSENSORED_CONTROL_PORT=8766
ExecStart=/usr/bin/python3 ${SYSROOT}/control-plane/dashboard.py --host 127.0.0.1 --port 8766
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT

cat > "$USER_UNITS/unsensored-agent-novnc-tunnel.service" <<UNIT
[Unit]
Description=SSH tunnel for Unsensored Agent noVNC desktop viewer
After=unsensored-agent-tunnel.service
Wants=unsensored-agent-tunnel.service

[Service]
Type=simple
ExecStart=/bin/bash ${SYSROOT}/control-plane/vnc-tunnel-daemon.sh
Restart=on-failure
RestartSec=4

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable unsensored-agent-control-dashboard.service
systemctl --user restart unsensored-agent-control-dashboard.service
sleep 1
if ! curl --silent --show-error --fail --max-time 4 http://127.0.0.1:8766/api/control/overview >/dev/null; then
  echo "Control Room service installed but health check failed. Recent logs:" >&2
  systemctl --user --no-pager --full status unsensored-agent-control-dashboard.service >&2 || true
  journalctl --user -u unsensored-agent-control-dashboard.service -n 50 --no-pager >&2 || true
  exit 1
fi

# Set a bounded service-stop timeout inside the guest. This only affects the
# agent API service's shutdown duration; it does not change the VM's power policy.
if [[ -f "$ROOT/vm/agent_vm_ed25519" ]] && timeout 4 bash -c '</dev/tcp/127.0.0.1/2222' 2>/dev/null; then
  ssh -i "$ROOT/vm/agent_vm_ed25519" -p 2222 -o BatchMode=yes -o ConnectTimeout=3 \
    -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$ROOT/vm/known_hosts" agent@127.0.0.1 'sudo bash -s' <<'GUEST'
set -euo pipefail
DROP=/etc/systemd/system/unsensored-agent.service.d/control-plane-lifecycle.conf
install -d -m 0755 /etc/systemd/system/unsensored-agent.service.d
if [[ -f "$DROP" ]] && ! grep -q 'TimeoutStopSec=15s' "$DROP"; then
  cp -a "$DROP" "$DROP.bak.$(date +%Y%m%d-%H%M%S)"
fi
cat > "$DROP" <<'OVERRIDE'
[Service]
TimeoutStopSec=15s
KillMode=mixed
SendSIGKILL=yes
OVERRIDE
systemctl daemon-reload
# Keep agent startup separate from VM power-on. Do not stop a currently running task.
systemctl disable unsensored-agent.service >/dev/null 2>&1 || true
GUEST
  echo "Agent auto-start disabled for future VM boots; a bounded 15-second service-stop limit was configured. A running agent was not stopped."
else
  echo "VM SSH not currently reachable. Agent boot decoupling and stop timeout will be applied on the next install while the VM is reachable."
fi

cat <<EOF

Control Room installed and running.
  Control Room: http://127.0.0.1:8766
  Agent API:    http://127.0.0.1:8765/docs
  VM desktop:   http://127.0.0.1:6081/vnc.html?autoconnect=true

Use ./run-agent.sh to start the whole stack and open both browser tabs.
Use ./stop-agent-stack.sh to stop the agent + VM + control dashboard.
Existing VM disk, task database, logs, checkpoints, and workspace files were not replaced.
Hourly journal uses local system/task metadata only and makes no LLM requests.
EOF
