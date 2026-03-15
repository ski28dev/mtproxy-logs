#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <mtproxy-source-dir>" >&2
  exit 1
fi

src_dir="$1"
target_file="${src_dir}/net/net-tcp-rpc-ext-server.c"

if [[ ! -f "${target_file}" ]]; then
  echo "missing source file: ${target_file}" >&2
  exit 1
fi

python3 - "${target_file}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
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

make -C "${src_dir}" -j"$(nproc)"

