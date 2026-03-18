#!/usr/bin/env bash
set -euo pipefail

LOG_FILE=/var/log/mtproxy/watchdog.log
MTP_LOG=/var/log/mtproxy/mtproxy.log
mkdir -p /var/log/mtproxy

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" >> "$LOG_FILE"; }

service_ok=1
port_ok=1
handshake_ok=1

if ! systemctl is-active --quiet mtproxy; then
  service_ok=0
fi

if ! ss -lnt '( sport = :443 )' | grep -q LISTEN; then
  port_ok=0
fi

if [ -f "$MTP_LOG" ]; then
  if ! timeout 2 tail -n 200 "$MTP_LOG" | grep -q 'MTP_EVENT handshake_ok'; then
    handshake_ok=0
  fi
else
  handshake_ok=0
fi

if [ "$service_ok" -eq 1 ] && [ "$port_ok" -eq 1 ]; then
  if [ "$handshake_ok" -eq 1 ]; then
    log 'ok: service active, port 443 listening, handshake events present'
  else
    log 'warn: service active, port 443 listening, but no recent handshake_ok in last 200 log lines'
  fi
  exit 0
fi

log "restart: service_ok=$service_ok port_ok=$port_ok handshake_ok=$handshake_ok"
systemctl restart mtproxy
sleep 3
if systemctl is-active --quiet mtproxy && ss -lnt '( sport = :443 )' | grep -q LISTEN; then
  log 'restart successful'
else
  log 'restart failed'
  exit 1
fi
