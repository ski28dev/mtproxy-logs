#!/usr/bin/env bash
set -euo pipefail

. /etc/mtproxy/mtproxy.env

args=(
  -u "${RUN_USER:-nobody}"
  -p "${STATS_PORT}"
  -H "${PORT}"
  -D "${FAKE_HOST}"
  --aes-pwd /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf
  -M 1
)

has_secret=0
if [[ -f /etc/mtproxy/managed_secrets.list ]]; then
  while IFS= read -r raw_secret; do
    [[ -n "${raw_secret}" ]] || continue
    args+=(-S "${raw_secret}")
    has_secret=1
  done </etc/mtproxy/managed_secrets.list
fi

if [[ "${has_secret}" -eq 0 && -n "${SECRET_RAW:-}" ]]; then
  args+=(-S "${SECRET_RAW}")
fi

exec /opt/MTProxy/objs/bin/mtproto-proxy "${args[@]}" 2>>/var/log/mtproxy/mtproxy.log
