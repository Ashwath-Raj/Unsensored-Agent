#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "This bootstrap currently targets x86_64 Ubuntu Linux with QEMU/KVM." >&2; exit 1
fi
if ! grep -Eq '(vmx|svm)' /proc/cpuinfo; then
  echo "CPU virtualization flags were not detected. Enable VT-x/AMD-V (SVM) in firmware." >&2; exit 1
fi
if systemctl is-active --quiet squid.service; then
  echo "A system-wide squid service is already active. Refusing to alter it; stop/configure your existing proxy manually before using this kit." >&2
  exit 1
fi
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils openssh-client curl ca-certificates squid
# The kit uses a separate loopback-only Squid instance with a private config; disable the package default instance.
sudo systemctl disable --now squid.service >/dev/null 2>&1 || true
if [[ ! -e /dev/kvm ]]; then
  echo "No /dev/kvm device. Check firmware virtualization and host kernel modules." >&2; exit 1
fi
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx kvm; then
  sudo usermod -aG kvm "$USER"
  echo "Added $USER to the kvm group. Log out/in, then rerun ./host/setup-all.sh." >&2
  exit 2
fi
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "Current user cannot read/write /dev/kvm. Log out/in after group change or check KVM permissions." >&2; exit 1
fi
free -h
df -h "$ROOT"
echo "Host preflight passed."
