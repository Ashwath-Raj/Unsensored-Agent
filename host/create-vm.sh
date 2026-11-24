#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
mkdir -p "$VM_DIR"
chmod 700 "$VM_DIR"
if [[ ! -f "$SSH_KEY" ]]; then
  ssh-keygen -t ed25519 -N '' -C 'unsensored-agent-vm-host-to-guest' -f "$SSH_KEY" >/dev/null
  chmod 600 "$SSH_KEY"
fi
if [[ ! -f "$VM_DIR/ubuntu-24.04-server-cloudimg-amd64.img" ]]; then
  echo "Downloading Ubuntu 24.04 LTS cloud image..."
  curl -fL --retry 3 "$BASE_IMAGE_URL" -o "$VM_DIR/ubuntu-24.04-server-cloudimg-amd64.img"
fi
if [[ ! -f "$VM_DIR/disk.qcow2" ]]; then
  echo "Creating persistent VM disk..."
  qemu-img convert -p -f qcow2 -O qcow2 "$VM_DIR/ubuntu-24.04-server-cloudimg-amd64.img" "$VM_DIR/disk.qcow2"
  qemu-img resize "$VM_DIR/disk.qcow2" "${VM_DISK_GB}G"
fi
if [[ ! -f "$VM_DIR/seed.iso" ]]; then
  PUBKEY="$(cat "$SSH_KEY.pub")"
  cat > "$VM_DIR/user-data" <<'CLOUDCFG'
#cloud-config
hostname: unsensored-agent
manage_etc_hosts: true
ssh_pwauth: false
disable_root: true
users:
  - name: agent
    gecos: Isolated Agent User
    groups: [adm, sudo, video, audio]
    shell: /bin/bash
    lock_passwd: true
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - __PUBKEY__
package_update: true
package_upgrade: false
packages:
  - openssh-server
  - xfce4
  - xfce4-terminal
  - dbus-x11
  - xvfb
  - x11vnc
  - xdotool
  - scrot
  - git
  - curl
  - jq
  - python3
  - python3-venv
  - python3-pip
  - python3-dev
  - build-essential
  - ca-certificates
  - xauth
  - nftables
write_files:
  - path: /etc/nftables.conf
    owner: root:root
    permissions: '0644'
    content: |
      flush ruleset
      table inet agent_guest_egress_guard {
        chain output {
          type filter hook output priority 0; policy accept;
          oifname "lo" accept
          ct state established,related accept
          ip daddr 10.0.2.3 udp dport 53 accept
          ip daddr 10.0.2.3 tcp dport 53 accept
          ip daddr 10.0.2.2 drop
          ip daddr 10.0.0.0/8 drop
          ip daddr 172.16.0.0/12 drop
          ip daddr 192.168.0.0/16 drop
          ip daddr 169.254.0.0/16 drop
          ip daddr 100.64.0.0/10 drop
          ip6 daddr fc00::/7 drop
          ip6 daddr fe80::/10 drop
        }
      }
  - path: /usr/local/bin/agent-desktop
    owner: root:root
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      export HOME=/home/agent
      export DISPLAY=:0
      export XDG_RUNTIME_DIR=/run/user/1000
      mkdir -p "$XDG_RUNTIME_DIR"
      chown agent:agent "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"
      /usr/bin/Xvfb :0 -screen 0 1440x900x24 -ac -nolisten tcp -noreset &
      sleep 2
      exec /usr/bin/dbus-run-session -- /usr/bin/startxfce4
  - path: /etc/systemd/system/agent-desktop.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Isolated Agent Virtual Desktop
      After=network.target
      [Service]
      User=agent
      Group=agent
      Environment=HOME=/home/agent
      Environment=DISPLAY=:0
      Restart=on-failure
      RestartSec=3
      ExecStart=/usr/local/bin/agent-desktop
      [Install]
      WantedBy=multi-user.target
  - path: /etc/systemd/system/agent-vnc.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Loopback-only VNC for isolated guest desktop
      Requires=agent-desktop.service
      After=agent-desktop.service
      [Service]
      User=agent
      Group=agent
      Environment=DISPLAY=:0
      ExecStart=/usr/bin/x11vnc -display :0 -rfbport 5901 -localhost -forever -shared -nopw
      Restart=always
      RestartSec=2
      [Install]
      WantedBy=multi-user.target
runcmd:
  - [ bash, -lc, 'install -d -o agent -g agent /home/agent/workspace /home/agent/data /home/agent/backups' ]
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, ssh ]
  - [ systemctl, enable, nftables ]
  - [ systemctl, start, nftables ]
  - [ systemctl, enable, agent-desktop.service ]
  - [ systemctl, enable, agent-vnc.service ]
  - [ systemctl, start, agent-desktop.service ]
  - [ systemctl, start, agent-vnc.service ]
final_message: "Unsensored Agent VM base is ready."
CLOUDCFG
  sed -i "s|__PUBKEY__|$PUBKEY|" "$VM_DIR/user-data"
  cat > "$VM_DIR/meta-data" <<'METADATA'
instance-id: unsensored-agent-vm
local-hostname: unsensored-agent
METADATA
  cloud-localds "$VM_DIR/seed.iso" "$VM_DIR/user-data" "$VM_DIR/meta-data"
fi
"$(dirname "$0")/start-vm.sh"
echo "Waiting for guest SSH and cloud-init (initial setup can take several minutes)..."
for i in $(seq 1 180); do
  if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "${SSH_USER}@127.0.0.1" 'cloud-init status --wait >/dev/null 2>&1' >/dev/null 2>&1; then
    echo "Guest cloud-init completed."; exit 0
  fi
  sleep 5
done
echo "Timed out waiting for cloud-init. Inspect $VM_DIR/serial.log and retry; the disk is retained." >&2
exit 1
