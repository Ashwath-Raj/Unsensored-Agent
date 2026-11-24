#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
sudo loginctl enable-linger "$USER"
mkdir -p "$HOME/.config/systemd/user"
SERVICE="$HOME/.config/systemd/user/unsensored-agent-tunnel.service"
cat > "$SERVICE" <<UNIT
[Unit]
Description=SSH tunnel between host proxy/Ollama and isolated Unsensored Agent VM
After=default.target unsensored-agent-proxy.service
Wants=unsensored-agent-proxy.service
[Service]
Type=simple
ExecStart=/usr/bin/ssh -N -i "$SSH_KEY" -p $SSH_PORT -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" -L 127.0.0.1:5901:127.0.0.1:5901 -L 127.0.0.1:8765:127.0.0.1:8765 -R 127.0.0.1:11434:127.0.0.1:11434 -R 127.0.0.1:3128:127.0.0.1:3129 $SSH_USER@127.0.0.1
Restart=always
RestartSec=5
[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now unsensored-agent-tunnel.service

echo "Tunnel enabled. Dashboard: http://127.0.0.1:8765"
echo "The current Ollama model remains on host loopback; guest access is via the SSH reverse tunnel."
