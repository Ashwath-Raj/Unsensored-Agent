#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
[[ -f "$VM_DIR/disk.qcow2" ]] || { echo "Create the VM first." >&2; exit 1; }
"$(dirname "$0")/start-vm.sh"
SSH=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "${SSH_USER}@127.0.0.1")
SCP=(scp -i "$SSH_KEY" -P "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS")
"${SCP[@]}" -r "$ROOT/guest/app" "$ROOT/guest/requirements.txt" "${SSH_USER}@127.0.0.1:/home/agent/"
"${SSH[@]}" 'sudo install -d -o agent -g agent /opt/unsensored-agent /home/agent/workspace /home/agent/data/runs /home/agent/backups; sudo rm -rf /opt/unsensored-agent/app; sudo cp -a /home/agent/app /opt/unsensored-agent/app; sudo cp /home/agent/requirements.txt /opt/unsensored-agent/requirements.txt; sudo chown -R agent:agent /opt/unsensored-agent /home/agent/workspace /home/agent/data /home/agent/backups; python3 -m venv /opt/unsensored-agent/.venv; /opt/unsensored-agent/.venv/bin/pip install --upgrade pip; /opt/unsensored-agent/.venv/bin/pip install -r /opt/unsensored-agent/requirements.txt; sudo /opt/unsensored-agent/.venv/bin/playwright install-deps chromium; /opt/unsensored-agent/.venv/bin/playwright install chromium'
"${SSH[@]}" 'cat > /tmp/unsensored-agent.env <<"AGENTENV"
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=hf.co/HauhauCS/Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced:Q4_K_M
OLLAMA_NUM_CTX=8192
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
ALL_PROXY=http://127.0.0.1:3128
http_proxy=http://127.0.0.1:3128
https_proxy=http://127.0.0.1:3128
all_proxy=http://127.0.0.1:3128
NO_PROXY=localhost,127.0.0.1,::1,.test
no_proxy=localhost,127.0.0.1,::1,.test
BROWSER_PROXY=http://127.0.0.1:3128
AGENT_HOME=/home/agent/data
WORKSPACE=/home/agent/workspace
BROWSER_HEADLESS=false
TASK_MAX_HOURS=12
MAX_TOOL_CALLS_PER_STAGE=32
MAX_STAGE_RETRIES=2
ACTIVE_TARGET_ALLOWLIST=localhost,127.0.0.1,::1,.test
AGENTENV
sudo install -o agent -g agent -m 0600 /tmp/unsensored-agent.env /opt/unsensored-agent/.env
sudo tee /etc/systemd/system/unsensored-agent.service >/dev/null <<"UNIT"
[Unit]
Description=Unsensored Agent sequential task harness
After=network-online.target agent-desktop.service
Wants=network-online.target
[Service]
Type=simple
User=agent
Group=agent
WorkingDirectory=/opt/unsensored-agent
EnvironmentFile=/opt/unsensored-agent/.env
Environment=DISPLAY=:0
Environment=HOME=/home/agent
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/opt/unsensored-agent/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8765
Restart=always
RestartSec=5
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now unsensored-agent.service
'
echo "Harness installed. Check via SSH: sudo systemctl status unsensored-agent"
