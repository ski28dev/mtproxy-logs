#!/bin/sh
set -eu
curl -fsSL https://core.telegram.org/getProxySecret -o /etc/mtproxy/proxy-secret.new
curl -fsSL https://core.telegram.org/getProxyConfig -o /etc/mtproxy/proxy-multi.conf.new
mv /etc/mtproxy/proxy-secret.new /etc/mtproxy/proxy-secret
mv /etc/mtproxy/proxy-multi.conf.new /etc/mtproxy/proxy-multi.conf
