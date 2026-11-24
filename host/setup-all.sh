#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/check-host.sh"
"$HERE/create-vm.sh"
"$HERE/install-harness.sh"
"$HERE/setup-proxy.sh"
"$HERE/setup-tunnel.sh"
"$HERE/enable-network-isolation.sh"
echo
echo "Setup finished. Ensure Ollama is running on the host, then open http://127.0.0.1:8765"
echo "VM disk and logs are under: $HERE/../vm"
echo "Guest workspace is /home/agent/workspace inside the VM; no host directory is shared."
