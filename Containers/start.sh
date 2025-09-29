#!/bin/sh
set -eu

echo "Starting setup container please wait"
sleep 1

: "${SERVER_ADDRESS:?missing SERVER_ADDRESS}"
: "${SERVER_PORT:?missing SERVER_PORT}"
: "${USER_ID:?missing USER_ID}"
: "${ENCRYPTION:=none}"
: "${FINGERPRINT_FP:=firefox}"
: "${SERVER_NAME_SNI:?missing SERVER_NAME_SNI}"
: "${PUBLIC_KEY_PBK:?missing PUBLIC_KEY_PBK}"
: "${SHORT_ID_SID:=}"
# interface names used in your setup:
VETH_IF="docker-xray-vle"
VETH_GW="172.18.20.5"
TUN_DEV="tun0"
TUN_ADDR="172.31.200.10/30"
TUN_MTU="1300"

SERVER_IP_ADDRESS="$SERVER_ADDRESS"   # works if SERVER_ADDRESS is already an IP

# Geo files from Loyalsoldier
if [ ! -s /opt/xray/geo/geoip.dat ]; then
  wget -q -O /opt/xray/geo/geoip.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" || true
fi
if [ ! -s /opt/xray/geo/geosite.dat ]; then
  wget -q -O /opt/xray/geo/geosite.dat \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" || true
fi

# --- Networking (idempotent) ---
ip tuntap del mode tun dev "$TUN_DEV" 2>/dev/null || true
ip tuntap add mode tun dev "$TUN_DEV"
ip addr replace "$TUN_ADDR" dev "$TUN_DEV"
ip link set dev "$TUN_DEV" mtu "$TUN_MTU"
ip link set dev "$TUN_DEV" up
sleep 1

# routing: default via tun; keep server IP via veth gw so the tunnel can establish
ip route del default 2>/dev/null || true
ip route replace default dev "$TUN_DEV"
ip route replace "$SERVER_IP_ADDRESS/32" via "$VETH_GW"

# resolver for the container
printf 'nameserver %s\n' "$VETH_GW" > /etc/resolv.conf
echo "nameserver $VETH_GW"

# --- Files & deps ---
mkdir -p /opt/xray/config /opt/xray/geo /tmp/xray /tmp/tun2socks


# --- Xray config (RU bypass rules) ---
cat > /opt/xray/config/config.json <<EOF
{
  "log": { "loglevel": "info" },
  "dns": { "servers": ["$VETH_GW"] },

  "inbounds": [
    {
      "port": 10800,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": { "udp": true },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],

  "outbounds": [
    {
      "protocol": "vless",
      "tag": "proxy",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_ADDRESS",
            "port": $SERVER_PORT,
            "users": [
              { "id": "$USER_ID", "encryption": "$ENCRYPTION", "alterId": 0, "flow": "$FLOW" }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT_FP",
          "serverName": "$SERVER_NAME_SNI",
          "publicKey": "$PUBLIC_KEY_PBK",
          "spiderX": "",
          "shortId": "$SHORT_ID_SID"
        }
      }
    },
    { "protocol": "freedom",   "tag": "direct"  },
    { "protocol": "blackhole", "tag": "block"   }
  ],

  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "outboundTag": "direct", "domain": [
        "domain:.ru",
        "domain:.xn--p1ai"
      ]},
      { "type": "field", "outboundTag": "direct", "ip": [ "geoip:ru" ]},
      { "type": "field", "outboundTag": "proxy", "network": "tcp,udp" }
    ]
  }
}
EOF

echo "Xray and tun2socks preparing for launch"
rm -rf /tmp/xray /tmp/tun2socks
mkdir -p /tmp/xray /tmp/tun2socks
7z x /opt/xray/xray.7z -o/tmp/xray/ -y >/dev/null
chmod 755 /tmp/xray/xray
7z x /opt/tun2socks/tun2socks.7z -o/tmp/tun2socks/ -y >/dev/null
chmod 755 /tmp/tun2socks/tun2socks

# --- just before "Start Xray core" ---
export XRAY_LOCATION_ASSET=/opt/xray/geo
ln -sf /opt/xray/geo/geosite.dat /tmp/xray/geosite.dat 2>/dev/null || true
ln -sf /opt/xray/geo/geoip.dat   /tmp/xray/geoip.dat   2>/dev/null || true

echo "Start Xray core"
/tmp/xray/xray run -config /opt/xray/config/config.json &

echo "Start tun2socks"
/tmp/tun2socks/tun2socks -loglevel silent -tcp-sndbuf 3m -tcp-rcvbuf 3m \
  -device "$TUN_DEV" -proxy socks5://127.0.0.1:10800 -interface "$VETH_IF" &

echo "Container customization is complete"
# Let the parent "&& /sbin/init" take over when run by RouterOS;
# when run manually, keep the script alive so processes aren't reaped.
[ -t 0 ] || exit 0
tail -f /tmp/xray.log /tmp/tun2socks.log
