#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <server-ip>" >&2
  exit 1
fi

server_ip="$1"

admin_user="admin"
api_dir="/opt/mtproxy-panel/api"
web_dir="/var/www/mtproxy-panel-web"
state_dir="/var/lib/mtproxy-panel"
log_dir="/var/log/mtproxy"
db_name="mtproxy_panel"
db_user="mtproxy_panel"
db_password="$(openssl rand -hex 12)"
jwt_secret="$(openssl rand -hex 32)"
admin_password="$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-18)"
root_secret_path="/root/mtproxy-panel-info.txt"

cat >"${api_dir}/.env" <<EOF_ENV
HOST=127.0.0.1
PORT=3210
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
JWT_SECRET=${jwt_secret}
ADMIN_USERNAME=${admin_user}
ADMIN_PASSWORD=${admin_password}
PANEL_ORIGIN=http://${server_ip}:8088
MTPROXY_HOST=${server_ip}
MTPROXY_PORT=443
MTPROXY_FAKE_HOST=www.cloudflare.com
MTPROXY_SYNC_COMMAND="sudo /usr/local/bin/mtproxy-panel-sync"
MTPROXY_LOG_PATH=${log_dir}/mtproxy.log
MTPROXY_LOG_STATE_PATH=${state_dir}/log-state.json
MTPROXY_SLOT_WINDOW_HOURS=72
EOF_ENV

mkdir -p "${state_dir}" "${log_dir}" /etc/mtproxy
touch "${log_dir}/mtproxy.log"
chown -R mtpanel:mtpanel "${api_dir}" "${web_dir}" "${state_dir}"
chown root:mtpanel "${log_dir}/mtproxy.log"
chmod 640 "${log_dir}/mtproxy.log"

mysql <<EOF_SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'127.0.0.1' IDENTIFIED BY '${db_password}';
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';
ALTER USER '${db_user}'@'127.0.0.1' IDENTIFIED BY '${db_password}';
ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF_SQL

cd "${api_dir}"
node scripts/init-db.mjs
node scripts/seed-admin.mjs

if ! mysql -Nse "SELECT 1 FROM ${db_name}.proxy_secrets LIMIT 1" | grep -q 1; then
  secret_raw="$(awk -F= '/^SECRET_RAW=/{print $2}' /etc/mtproxy/mtproxy.env)"
  secret_tls="$(awk -F= '/^SECRET_TLS=/{print $2}' /etc/mtproxy/mtproxy.env)"
  fake_host="$(awk -F= '/^FAKE_HOST=/{print $2}' /etc/mtproxy/mtproxy.env)"
  mysql "${db_name}" <<EOF_SQL
INSERT INTO proxy_secrets (label, note, status, raw_secret, client_secret, fake_host, port, max_unique_ips)
VALUES ('Initial MTProxy', 'Imported from existing server config', 'active', '${secret_raw}', '${secret_tls}', '${fake_host}', 443, 10);
EOF_SQL
fi

python3 - <<'PY'
from pathlib import Path

path = Path("/opt/MTProxy/net/net-tcp-rpc-ext-server.c")
text = path.read_text()

text = text.replace("static unsigned char ext_secret[16][16];", "static unsigned char ext_secret[512][16];")
text = text.replace("  assert (ext_secret_cnt < 16);", "  assert (ext_secret_cnt < 512);")

if '#include "net/net-tcp-rpc-server.h"' not in text:
    text = text.replace('#include "net/net-tcp-rpc-common.h"\n', '#include "net/net-tcp-rpc-common.h"\n#include "net/net-tcp-rpc-server.h"\n')

old_decl = '''int tcp_rpcs_compact_parse_execute (connection_job_t c);
int tcp_rpcs_ext_alarm (connection_job_t c);
int tcp_rpcs_ext_init_accepted (connection_job_t c);
'''
new_decl = '''int tcp_rpcs_compact_parse_execute (connection_job_t c);
int tcp_rpcs_ext_alarm (connection_job_t c);
int tcp_rpcs_ext_init_accepted (connection_job_t c);
int tcp_rpcs_ext_close (connection_job_t c, int who);

#define MT_EVENT_SECRET_ID(c) (TCP_RPC_DATA(c)->extra_int)
#define MT_EVENT_HANDSHAKE_OK(c) (TCP_RPC_DATA(c)->extra_int2)
#define MT_EVENT_CONNECTED_AT(c) (TCP_RPC_DATA(c)->extra_double)

static void mtproto_log_handshake_ok (connection_job_t C, const char *domain, int secret_id) {
  struct connection_info *c = CONN_INFO (C);
  MT_EVENT_SECRET_ID(C) = secret_id;
  MT_EVENT_HANDSHAKE_OK(C) = 1;
  MT_EVENT_CONNECTED_AT(C) = precise_now;
  vkprintf (1, "MTP_EVENT handshake_ok secret_id=%d fd=%d ip=%s port=%d domain=%s\\n", secret_id, c->fd, show_remote_ip (C), c->remote_port, domain);
}
'''
if old_decl in text and 'MTP_EVENT handshake_ok' not in text:
    text = text.replace(old_decl, new_decl)

text = text.replace('  .close = tcp_rpcs_close_connection,\n', '  .close = tcp_rpcs_ext_close,\n')

old_init = '''int tcp_rpcs_ext_init_accepted (connection_job_t C) {
  job_timer_insert (C, precise_now + 10);
  return tcp_rpcs_init_accepted_nohs (C);
}
'''
new_init = '''int tcp_rpcs_ext_init_accepted (connection_job_t C) {
  job_timer_insert (C, precise_now + 10);
  int res = tcp_rpcs_init_accepted_nohs (C);
  MT_EVENT_SECRET_ID(C) = -1;
  MT_EVENT_HANDSHAKE_OK(C) = 0;
  MT_EVENT_CONNECTED_AT(C) = 0;
  return res;
}

int tcp_rpcs_ext_close (connection_job_t C, int who) {
  struct connection_info *c = CONN_INFO (C);
  if (MT_EVENT_HANDSHAKE_OK(C)) {
    double duration = precise_now - MT_EVENT_CONNECTED_AT(C);
    if (duration < 0) {
      duration = 0;
    }
    vkprintf (1, "MTP_EVENT disconnect secret_id=%d fd=%d ip=%s port=%d duration=%.3f who=%d\\n", MT_EVENT_SECRET_ID(C), c->fd, show_remote_ip (C), c->remote_port, duration, who);
  }
  return tcp_rpcs_close_connection (C, who);
}
'''
if old_init in text and 'MTP_EVENT disconnect' not in text:
    text = text.replace(old_init, new_init)

text = text.replace('        vkprintf (1, "TLS type with domain %s secret_id=%d from %s:%d\\n", info->domain, secret_id, show_remote_ip (C), c->remote_port);\n', '')

old_handshake = '''        assert (rwm_skip_data (&c->in, len) == len);
        c->flags |= C_IS_TLS;
        c->left_tls_packet_length = -1;
'''
new_handshake = '''        assert (rwm_skip_data (&c->in, len) == len);
        c->flags |= C_IS_TLS;
        c->left_tls_packet_length = -1;
        mtproto_log_handshake_ok (C, info->domain, secret_id);
'''
if old_handshake in text and 'mtproto_log_handshake_ok (C, info->domain, secret_id);' not in text:
    text = text.replace(old_handshake, new_handshake)

path.write_text(text)
PY

make -C /opt/MTProxy -j"$(nproc)"

cat >/usr/local/bin/mtproxy-managed-run.sh <<'EOF_RUN'
#!/usr/bin/env bash
set -euo pipefail

. /etc/mtproxy/mtproxy.env

args=(
  -u nobody
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

if [[ "${has_secret}" -eq 0 ]]; then
  args+=(-S "${SECRET_RAW}")
fi

exec /opt/MTProxy/objs/bin/mtproto-proxy "${args[@]}" 2>>/var/log/mtproxy/mtproxy.log
EOF_RUN
chmod 755 /usr/local/bin/mtproxy-managed-run.sh

cat >/usr/local/bin/mtproxy-panel-sync <<'EOF_SYNC'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/mtproxy-panel/api
/usr/bin/node scripts/sync-mtproxy.mjs
EOF_SYNC
chmod 755 /usr/local/bin/mtproxy-panel-sync

cat >/etc/sudoers.d/mtproxy-panel <<'EOF_SUDO'
mtpanel ALL=(root) NOPASSWD: /usr/local/bin/mtproxy-panel-sync
EOF_SUDO
chmod 440 /etc/sudoers.d/mtproxy-panel

cat >/etc/systemd/system/mtproxy.service <<'EOF_MTPROXY'
[Unit]
Description=Telegram MTProxy (Managed Fake TLS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/mtproxy/mtproxy.env
ExecStartPre=/usr/local/bin/mtproxy-fetch-config.sh
ExecStart=/usr/local/bin/mtproxy-managed-run.sh
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_MTPROXY

cat >/etc/systemd/system/mtproxy-panel-api.service <<'EOF_API'
[Unit]
Description=MTProxy Panel API
After=network.target mariadb.service
Wants=network.target

[Service]
Type=simple
User=mtpanel
Group=mtpanel
WorkingDirectory=/opt/mtproxy-panel/api
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF_API

cat >/etc/systemd/system/mtproxy-panel-import-log.service <<'EOF_IMPORT'
[Unit]
Description=MTProxy Panel Log Import
After=network.target mtproxy.service mtproxy-panel-api.service

[Service]
Type=oneshot
User=mtpanel
Group=mtpanel
WorkingDirectory=/opt/mtproxy-panel/api
ExecStart=/usr/bin/node scripts/import-mtproxy-log.mjs
EOF_IMPORT

cat >/etc/systemd/system/mtproxy-panel-import-log.timer <<'EOF_IMPORT_TIMER'
[Unit]
Description=Run MTProxy Panel Log Import every minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
Unit=mtproxy-panel-import-log.service

[Install]
WantedBy=timers.target
EOF_IMPORT_TIMER

cat >/etc/systemd/system/mtproxy-panel-sync.service <<'EOF_SYNC_SERVICE'
[Unit]
Description=MTProxy Panel Sync
After=network.target mtproxy.service

[Service]
Type=oneshot
User=root
Group=root
WorkingDirectory=/opt/mtproxy-panel/api
ExecStart=/usr/local/bin/mtproxy-panel-sync
EOF_SYNC_SERVICE

cat >/etc/systemd/system/mtproxy-panel-sync.timer <<'EOF_SYNC_TIMER'
[Unit]
Description=Run MTProxy Panel Sync every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=mtproxy-panel-sync.service

[Install]
WantedBy=timers.target
EOF_SYNC_TIMER

cat >/etc/nginx/conf.d/mtproxy-panel.conf <<EOF_NGINX
server {
    listen 8088;
    listen [::]:8088;
    server_name _;

    root ${web_dir}/.output/.output/public;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3210/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF_NGINX

nginx -t

chown -R mtpanel:mtpanel "${api_dir}" "${web_dir}" "${state_dir}"
chown root:mtpanel "${log_dir}/mtproxy.log"

systemctl daemon-reload
systemctl enable mtproxy.service mtproxy-panel-api.service mtproxy-panel-import-log.timer mtproxy-panel-sync.timer
systemctl restart mtproxy.service
systemctl restart mtproxy-panel-api.service
systemctl restart nginx
systemctl start mtproxy-panel-import-log.timer mtproxy-panel-sync.timer
/usr/local/bin/mtproxy-panel-sync
ufw allow 8088/tcp >/dev/null 2>&1 || true

cat >"${root_secret_path}" <<EOF_INFO
Panel URL: http://${server_ip}:8088/
Admin username: ${admin_user}
Admin password: ${admin_password}
API bind: 127.0.0.1:3210
DB name: ${db_name}
DB user: ${db_user}
DB password: ${db_password}
EOF_INFO

echo "panel_url=http://${server_ip}:8088/"
echo "admin_username=${admin_user}"
echo "admin_password=${admin_password}"
