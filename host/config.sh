#!/usr/bin/env bash
# Sourced by host scripts. This project is expected to live at your requested path.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$ROOT/vm"
VM_NAME="unsensored-agent-vm"
VM_RAM_MB="${VM_RAM_MB:-5120}"
VM_VCPUS="${VM_VCPUS:-4}"
VM_DISK_GB="${VM_DISK_GB:-60}"
BASE_IMAGE_URL="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
SSH_PORT="2222"
SSH_USER="agent"
SSH_KEY="$VM_DIR/agent_vm_ed25519"
SSH_KNOWN_HOSTS="$VM_DIR/known_hosts"

# Host-only key and forced-command user for dashboard lifecycle control.
CONTROL_SSH_USER="${CONTROL_SSH_USER:-agentctl}"
CONTROL_SSH_KEY="${CONTROL_SSH_KEY:-$VM_DIR/agent_control_ed25519}"
CONTROL_SSH_KNOWN_HOSTS="${CONTROL_SSH_KNOWN_HOSTS:-$SSH_KNOWN_HOSTS}"
