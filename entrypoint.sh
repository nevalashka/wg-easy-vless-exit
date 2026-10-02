#!/bin/bash
# Выходной сервер: Xray VLESS + REALITY
#
# Всё, что не задано через env (UUID, ключи REALITY, shortId, путь xhttp), генерируется
# при первом старте и сохраняется в /data/server.env — ключи переживают пересоздание контейнера.
# Готовые параметры для первой ноды печатаются в лог и пишутся в /data/client.txt.
set -Eeuo pipefail

log() { echo "[exit] $*"; }
die() { echo "[exit] FATAL: $*" >&2; exit 1; }

DATA=/data
STATE="$DATA/server.env"
CFG=/run/xray/config.json
mkdir -p "$DATA" "$(dirname "$CFG")"

# ---------- сохранённое состояние ----------
if [[ -f "$STATE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE"
fi

hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

VLESS_PORT="${VLESS_PORT:-443}"
VLESS_UUID="${VLESS_UUID:-${SAVED_UUID:-$(xray uuid)}}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-${SAVED_PRIVATE_KEY:-$(xray x25519 | sed -n 1p | awk -F': ' '{print $2}')}}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-${SAVED_SHORT_ID:-$(hex 8)}}"
REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"
REALITY_TARGET="${REALITY_TARGET:-${REALITY_SNI}:443}"
XHTTP_PORT="${XHTTP_PORT:-}"                       # пусто = xhttp выключен
XHTTP_PATH="${XHTTP_PATH:-${SAVED_XHTTP_PATH:-/$(hex 6)}}"
BLOCK_TORRENT="${BLOCK_TORRENT:-true}"
XRAY_LOGLEVEL="${XRAY_LOGLEVEL:-warning}"
XRAY_ACCESS_LOG="${XRAY_ACCESS_LOG:-false}"
PUBLIC_HOST="${PUBLIC_HOST:-}"

# ---------- проверки ----------
[[ "$VLESS_PORT" =~ ^[0-9]+$ ]] || die "VLESS_PORT: число"
[[ -z "$XHTTP_PORT" || "$XHTTP_PORT" =~ ^[0-9]+$ ]] || die "XHTTP_PORT: число"
[[ "$XHTTP_PORT" != "$VLESS_PORT" ]] || die "XHTTP_PORT должен отличаться от VLESS_PORT"
[[ "$REALITY_SHORT_ID" =~ ^[0-9a-f]{0,16}$ ]] || die "REALITY_SHORT_ID: hex в нижнем регистре, до 16 символов"
[[ "$REALITY_SNI" =~ ^[A-Za-z0-9.-]+$ ]] || die "REALITY_SNI: доменное имя"
[[ "$REALITY_TARGET" =~ ^[A-Za-z0-9.-]+:[0-9]+$ ]] || die "REALITY_TARGET: host:port"
[[ "$XHTTP_PATH" =~ ^/[A-Za-z0-9._~/-]*$ ]] || die "XHTTP_PATH: начинается с /, без спецсимволов"
[[ "$VLESS_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "VLESS_UUID: формат UUID"

REALITY_PUBLIC_KEY=$(xray x25519 -i "$REALITY_PRIVATE_KEY" | sed -n 2p | awk -F': ' '{print $2}')
[[ -n "$REALITY_PUBLIC_KEY" ]] || die "REALITY_PRIVATE_KEY невалиден"

umask 077
cat > "$STATE" <<EOF
SAVED_UUID=$VLESS_UUID
SAVED_PRIVATE_KEY=$REALITY_PRIVATE_KEY
SAVED_SHORT_ID=$REALITY_SHORT_ID
SAVED_XHTTP_PATH=$XHTTP_PATH
EOF

# ---------- конфиг Xray ----------
reality_json() {
  cat <<EOF
"security": "reality",
"realitySettings": {
  "target": "${REALITY_TARGET}",
  "serverNames": ["${REALITY_SNI}"],
  "privateKey": "${REALITY_PRIVATE_KEY}",
  "shortIds": ["${REALITY_SHORT_ID}"]
}
EOF
}

SNIFF='"sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true}'

XHTTP_INBOUND=""
if [[ -n "$XHTTP_PORT" ]]; then
  XHTTP_INBOUND=$(cat <<EOF
,
{
  "tag": "vless-xhttp",
  "listen": "0.0.0.0",
  "port": ${XHTTP_PORT},
  "protocol": "vless",
  "settings": {"clients": [{"id": "${VLESS_UUID}"}], "decryption": "none"},
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {"path": "${XHTTP_PATH}", "mode": "auto"},
    $(reality_json)
  },
  ${SNIFF}
}
EOF
)
fi

TORRENT_RULE=""
[[ "$BLOCK_TORRENT" == "true" ]] && TORRENT_RULE=',{"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"}'

ACCESS='"access": "none",'
[[ "$XRAY_ACCESS_LOG" == "true" ]] && ACCESS=''

cat > "$CFG" <<EOF
{
  "log": {${ACCESS} "loglevel": "${XRAY_LOGLEVEL}"},
  "inbounds": [
    {
      "tag": "vless-tcp",
      "listen": "0.0.0.0",
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {"clients": [{"id": "${VLESS_UUID}", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {
        "network": "raw",
        $(reality_json)
      },
      ${SNIFF}
    }${XHTTP_INBOUND}
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "block"}${TORRENT_RULE}
    ]
  },
  "policy": {"levels": {"0": {"handshake": 4, "connIdle": 300}}}
}
EOF

xray run -test -c "$CFG" >/dev/null || { xray run -test -c "$CFG"; die "конфиг Xray невалиден"; }

# ---------- параметры для первой ноды ----------
if [[ -z "$PUBLIC_HOST" ]]; then
  # busybox wget (curl в образе нет); api4/ipv4 — только IPv4-адрес
  PUBLIC_HOST=$(wget -qO- -T 5 https://api4.ipify.org 2>/dev/null || wget -qO- -T 5 https://ipv4.icanhazip.com 2>/dev/null || true)
  PUBLIC_HOST=$(printf '%s' "$PUBLIC_HOST" | tr -d '[:space:]')
  [[ "$PUBLIC_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || PUBLIC_HOST="<IP_ЭТОГО_СЕРВЕРА>"
fi

urlenc_path() { printf '%s' "$1" | sed 's#/#%2F#g'; }
URI_TCP="vless://${VLESS_UUID}@${PUBLIC_HOST}:${VLESS_PORT}?type=tcp&security=reality&pbk=${REALITY_PUBLIC_KEY}&fp=chrome&sni=${REALITY_SNI}&sid=${REALITY_SHORT_ID}&flow=xtls-rprx-vision#exit-tcp"

{
  echo "================ параметры для первой ноды (wg-easy-tun) ================"
  echo "# docker-compose.yml первой ноды, environment:"
  echo "      - VLESS_IP=${PUBLIC_HOST}"
  echo "      - VLESS_PORT=${VLESS_PORT}"
  echo "      - VLESS_UUID=${VLESS_UUID}"
  echo "      - VLESS_PUBLIC_KEY=${REALITY_PUBLIC_KEY}"
  echo "      - VLESS_SHORT_ID=${REALITY_SHORT_ID}"
  echo "      - VLESS_SNI=${REALITY_SNI}"
  echo "      - VLESS_TRANSPORT=tcp"
  echo
  echo "# или одной строкой:"
  echo "      - 'VLESS_URI=${URI_TCP}'"
  if [[ -n "$XHTTP_PORT" ]]; then
    echo
    echo "# запасной транспорт xhttp (на ноде: VLESS_PORT=${XHTTP_PORT}, VLESS_TRANSPORT=xhttp, VLESS_XHTTP_PATH=${XHTTP_PATH}):"
    echo "      - 'VLESS_URI=vless://${VLESS_UUID}@${PUBLIC_HOST}:${XHTTP_PORT}?type=xhttp&security=reality&pbk=${REALITY_PUBLIC_KEY}&fp=chrome&sni=${REALITY_SNI}&sid=${REALITY_SHORT_ID}&path=$(urlenc_path "$XHTTP_PATH")&mode=auto#exit-xhttp'"
  fi
  echo "========================================================================="
} | tee "$DATA/client.txt"

log "VLESS+REALITY tcp :${VLESS_PORT}${XHTTP_PORT:+, xhttp :${XHTTP_PORT}} | sni=${REALITY_SNI} target=${REALITY_TARGET} | torrent_block=${BLOCK_TORRENT}"
exec xray run -c "$CFG"
