#!/bin/bash
# healthy = xray жив и слушает порты VLESS
pgrep -x xray >/dev/null || { echo "xray not running"; exit 1; }
for p in "${VLESS_PORT:-443}" ${XHTTP_PORT:-}; do
  (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null || { echo "port $p closed"; exit 1; }
done
echo ok
