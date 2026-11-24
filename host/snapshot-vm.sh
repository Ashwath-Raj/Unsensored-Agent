#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
"$(dirname "$0")/stop-vm.sh"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="$VM_DIR/backups/disk-$STAMP.qcow2"
mkdir -p "$VM_DIR/backups"
cp --reflink=auto --sparse=always "$VM_DIR/disk.qcow2" "$DEST"
qemu-img check "$DEST"
echo "Stopped-disk backup created at: $DEST"
echo "VM remains stopped. Run ./host/start-vm.sh when ready."
