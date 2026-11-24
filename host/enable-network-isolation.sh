#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
SSH=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "${SSH_USER}@127.0.0.1")
"${SSH[@]}" 'sudo tee /etc/apt/apt.conf.d/90unsensored-agent-proxy >/dev/null <<"APTCONF"
Acquire::http::Proxy "http://127.0.0.1:3128";
Acquire::https::Proxy "http://127.0.0.1:3128";
APTCONF
sudo chmod 0644 /etc/apt/apt.conf.d/90unsensored-agent-proxy'
touch "$VM_DIR/network-restricted"
"$(dirname "$0")/stop-vm.sh"
"$(dirname "$0")/start-vm.sh"
echo "Reconnecting to guest after applying QEMU network restriction..."
ssh_ok=0
for _ in $(seq 1 90); do
  if "${SSH[@]}" 'true' >/dev/null 2>&1; then ssh_ok=1; break; fi
  sleep 2
done
if [[ "$ssh_ok" != 1 ]]; then echo "SSH did not return after restart; check vm/serial.log and the SSH tunnel service." >&2; exit 1; fi
# The SSH tunnel service reconnects automatically. Wait until the guest's dashboard can call the host Ollama endpoint.
for _ in $(seq 1 60); do
  if curl -fsS --max-time 12 http://127.0.0.1:8765/health 2>/dev/null | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ollama_reachable") else 1)' 2>/dev/null; then
    echo "Network restriction active; dashboard and Ollama tunnel are responding."
    exit 0
  fi
  sleep 2
done
echo "VM is restricted, but the tunnel/model check did not pass yet. Check 'systemctl --user status unsensored-agent-tunnel' and the guest service logs." >&2
exit 1
