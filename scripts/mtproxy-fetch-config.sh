#!/usr/bin/env bash
set -euo pipefail

install -d -m 755 /etc/mtproxy

curl -fsSL https://core.telegram.org/getProxySecret -o /etc/mtproxy/proxy-secret
curl -fsSL https://core.telegram.org/getProxyConfig -o /etc/mtproxy/proxy-multi.conf

chmod 600 /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf

