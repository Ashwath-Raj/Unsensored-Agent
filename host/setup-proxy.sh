#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
PROXY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/unsensored-agent-proxy"
mkdir -p "$HOME/.config/systemd/user" "$PROXY_DIR/cache"
chmod 700 "$PROXY_DIR"
cat > "$PROXY_DIR/squid.conf" <<CONF
http_port 127.0.0.1:3129
visible_hostname unsensored-agent-local-proxy
acl safe_ports port 80 443
acl ssl_ports port 443
acl connect method CONNECT
acl host_loopback src 127.0.0.1/32 ::1/128
acl manager proto cache_object
acl forbidden_dst dst 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 ::1/128 fc00::/7 fe80::/10
http_access deny manager
http_access deny !safe_ports
http_access deny connect !ssl_ports
http_access deny forbidden_dst
http_access allow host_loopback
http_access deny all
cache deny all
cache_dir ufs $PROXY_DIR/cache 64 16 256
cache_access_log stdio:$PROXY_DIR/access.log
cache_log $PROXY_DIR/cache.log
cache_store_log none
pid_filename $PROXY_DIR/squid.pid
coredump_dir $PROXY_DIR
cache_effective_user $(id -un)
cache_effective_group $(id -gn)
CONF
/usr/sbin/squid -z -f "$PROXY_DIR/squid.conf" >/dev/null
cat > "$HOME/.config/systemd/user/unsensored-agent-proxy.service" <<UNIT
[Unit]
Description=Loopback-only filtered HTTP/HTTPS proxy for isolated Unsensored Agent VM
After=default.target
[Service]
Type=simple
ExecStart=/usr/sbin/squid -N -f "$PROXY_DIR/squid.conf"
Restart=always
RestartSec=3
[Install]
WantedBy=default.target
UNIT
sudo loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now unsensored-agent-proxy.service
for _ in $(seq 1 20); do
  if curl --silent --fail --max-time 2 --proxy http://127.0.0.1:3129 http://example.com/ -o /dev/null; then
    echo "Loopback-only proxy is responding and can reach public HTTP."
    echo "Private/LAN destinations are denied by the proxy ACLs."
    exit 0
  fi
  sleep 1
done
echo "Proxy service did not pass the public HTTP smoke test. Inspect $PROXY_DIR/cache.log" >&2
exit 1
