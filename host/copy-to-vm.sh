#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: ./host/copy-to-vm.sh /path/to/project [guest-folder-name]" >&2
  exit 2
fi
SRC="$(realpath "$1")"
[[ -d "$SRC" ]] || { echo "Source must be a directory: $SRC" >&2; exit 1; }
NAME="${2:-$(basename "$SRC")}"
if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "Destination name may contain only letters, numbers, dot, underscore and hyphen." >&2; exit 1; fi
"$(dirname "$0")/start-vm.sh"
TMP="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "$TMP"' EXIT
# Copy a source snapshot, not a shared mount. Exclude Git internals, environments, and common secret files.
tar -czf "$TMP" -C "$(dirname "$SRC")" \
  --exclude='*/.git' --exclude='.git' \
  --exclude='*/node_modules' --exclude='node_modules' \
  --exclude='*/.venv' --exclude='.venv' --exclude='*/venv' --exclude='venv' \
  --exclude='*/__pycache__' --exclude='__pycache__' \
  --exclude='*/.env' --exclude='.env' --exclude='*/.env.*' --exclude='.env.*' \
  --exclude='*/.ssh' --exclude='.ssh' --exclude='*/.aws' --exclude='.aws' \
  --exclude='*.pem' --exclude='*.key' --exclude='id_rsa*' --exclude='*.p12' \
  "$(basename "$SRC")"
scp -i "$SSH_KEY" -P "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "$TMP" "${SSH_USER}@127.0.0.1:/home/agent/drop.tar.gz"
ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "${SSH_USER}@127.0.0.1" \
  "bash -lc 'set -e; mkdir -p /home/agent/workspace/$NAME; test -z \"\$(find /home/agent/workspace/$NAME -mindepth 1 -maxdepth 1 -print -quit)\" || { echo Destination already exists and is non-empty; exit 3; }; tar -xzf /home/agent/drop.tar.gz --strip-components=1 -C /home/agent/workspace/$NAME; rm -f /home/agent/drop.tar.gz; cd /home/agent/workspace/$NAME; git init -q; git config user.name Agent-Sandbox; git config user.email agent@vm.invalid; git add -A; git commit -qm \"Baseline imported for isolated agent edits\" || true; echo Project copied to /home/agent/workspace/$NAME'"
echo "Project snapshot copied into the VM. Excluded .git, .env, venvs, node_modules, and common credential file types. Inspect the guest workspace before authorizing edits."
