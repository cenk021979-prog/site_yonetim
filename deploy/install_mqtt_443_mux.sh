#!/usr/bin/env bash
set -euo pipefail

STAMP="${1:-$(date +%Y%m%d_%H%M%S)}"
BACKUP="/root/kapi-mqtt-443-$STAMP"
mkdir -p "$BACKUP"
cp -a /etc/nginx "$BACKUP/nginx"
[ ! -e /etc/haproxy ] || cp -a /etc/haproxy "$BACKUP/haproxy"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq haproxy

for file in /etc/nginx/sites-enabled/*; do
  [ -f "$file" ] || continue
  sed -i \
    -e 's/listen 443 ssl;/listen 127.0.0.1:8443 ssl proxy_protocol;/' \
    -e 's/listen \[::\]:443 ssl;/listen [::1]:8443 ssl proxy_protocol;/' \
    "$file"
done

cat >/etc/nginx/conf.d/00-haproxy-real-ip.conf <<'EOF'
set_real_ip_from 127.0.0.1;
set_real_ip_from ::1;
real_ip_header proxy_protocol;
EOF

cat >/etc/haproxy/haproxy.cfg <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 2h
    timeout server 2h

frontend tls_443
    bind :::443 v4v6
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl mqtt_sni req.ssl_sni -i mqtt.gudeteknoloji.com.tr
    use_backend mqtt_tls if mqtt_sni
    default_backend nginx_tls

backend mqtt_tls
    server mosquitto 127.0.0.1:8883

backend nginx_tls
    server nginx 127.0.0.1:8443 send-proxy-v2
EOF

nginx -t
haproxy -c -f /etc/haproxy/haproxy.cfg

rollback() {
  systemctl stop haproxy 2>/dev/null || true
  rm -rf /etc/nginx
  cp -a "$BACKUP/nginx" /etc/nginx
  nginx -t && systemctl restart nginx
}
trap rollback ERR

systemctl reload nginx
systemctl enable --now haproxy
sleep 1
curl -fsS --max-time 10 --resolve api.gudeteknoloji.com.tr:443:127.0.0.1 https://api.gudeteknoloji.com.tr/health >/dev/null
echo | openssl s_client -connect 127.0.0.1:443 -servername mqtt.gudeteknoloji.com.tr -brief 2>&1 | grep -q 'Verification: OK'
trap - ERR
echo "MQTT_443_MUX_OK backup=$BACKUP"
