#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Stopping the VM and agent stack. Host Ollama remains running."
"$ROOT/control-plane/stop-vm.sh"
"$ROOT/control-plane/stop-dashboard.sh"
echo "Stack stopped. Host Ollama and the host proxy were left untouched."
