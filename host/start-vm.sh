#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
DISK="$VM_DIR/disk.qcow2"
SEED="$VM_DIR/seed.iso"
PIDFILE="$VM_DIR/qemu.pid"
mkdir -p "$VM_DIR"
[[ -f "$DISK" ]] || { echo "VM disk missing. Run ./host/create-vm.sh first." >&2; exit 1; }
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "$VM_NAME already running (PID $(cat "$PIDFILE"))."; exit 0
fi
rm -f "$PIDFILE"
NETDEV="user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
# First boot needs direct NAT for apt/cloud-init. After setup, the VM runs QEMU restricted mode and uses the SSH-tunnelled HTTP proxy.
if [[ -f "$VM_DIR/network-restricted" ]]; then NETDEV+=",restrict=on"; fi
ARGS=(
  -name "$VM_NAME" -machine q35,accel=kvm -cpu host
  -m "$VM_RAM_MB" -smp "$VM_VCPUS",cores="$VM_VCPUS"
  -drive "file=$DISK,if=virtio,format=qcow2,cache=writeback"
  -netdev "$NETDEV"
  -device virtio-net-pci,netdev=net0
  -display none -serial "file:$VM_DIR/serial.log" -monitor none
  -daemonize -pidfile "$PIDFILE"
)
if [[ -f "$SEED" ]]; then ARGS+=( -drive "file=$SEED,if=virtio,format=raw,readonly=on" ); fi
qemu-system-x86_64 "${ARGS[@]}"
echo "VM started. SSH is forwarded to 127.0.0.1:${SSH_PORT}."
