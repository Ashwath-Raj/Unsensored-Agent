#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now unsensored-agent-control-dashboard.service 2>/dev/null || true
echo "Host dashboard stopped. The VM, agent service, tasks, tunnel and model were not stopped."
