#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
PIDFILE="$VM_DIR/qemu.pid"
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  # Ask the guest to shut down cleanly so SQLite/WAL and filesystem writes can flush.
  ssh -i "$CONTROL_SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$CONTROL_SSH_KNOWN_HOSTS" "${CONTROL_SSH_USER}@127.0.0.1" 'poweroff' >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do
    kill -0 "$(cat "$PIDFILE")" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -TERM "$(cat "$PIDFILE")"
    for _ in $(seq 1 15); do kill -0 "$(cat "$PIDFILE")" 2>/dev/null || break; sleep 1; done
  fi
  if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then echo "QEMU did not stop cleanly; refusing to SIGKILL it." >&2; exit 1; fi
  rm -f "$PIDFILE"
  echo "VM stopped."
else
  rm -f "$PIDFILE"
  echo "VM is not running."
fi
