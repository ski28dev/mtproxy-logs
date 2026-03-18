#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MTPROXY_SRC_DIR="${MTPROXY_SRC_DIR:-/opt/MTProxy}"
MTPROXY_REPO_URL="${MTPROXY_REPO_URL:-https://github.com/TelegramMessenger/MTProxy.git}"
PORT="${PORT:-443}"
STATS_PORT="${STATS_PORT:-127.0.0.1:8888}"
FAKE_HOST="${FAKE_HOST:-www.cloudflare.com}"
RUN_USER="${RUN_USER:-nobody}"
ENV_FILE="${ENV_FILE:-/etc/mtproxy/mtproxy.env}"
MANAGED_LIST="${MANAGED_LIST:-/etc/mtproxy/managed_secrets.list}"
LOG_FILE="${LOG_FILE:-/var/log/mtproxy/mtproxy.log}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  curl \
  ca-certificates \
  git \
  make \
  zlib1g-dev \
  libssl-dev \
  openssl

if [[ ! -d "${MTPROXY_SRC_DIR}/.git" ]]; then
  git clone "${MTPROXY_REPO_URL}" "${MTPROXY_SRC_DIR}"
else
  git -C "${MTPROXY_SRC_DIR}" fetch --all --tags
  git -C "${MTPROXY_SRC_DIR}" pull --ff-only
fi

"${REPO_DIR}/scripts/build-patched-mtproxy.sh" "${MTPROXY_SRC_DIR}"

install -d -m 755 /etc/mtproxy /var/log/mtproxy
touch "${LOG_FILE}"
chmod 640 "${LOG_FILE}"

install -m 755 "${REPO_DIR}/scripts/mtproxy-managed-run.sh" /usr/local/bin/mtproxy-managed-run.sh
install -m 755 "${REPO_DIR}/scripts/mtproxy-unshare-run.sh" /usr/local/bin/mtproxy-unshare-run.sh
install -m 755 "${REPO_DIR}/scripts/mtproxy-fetch-config.sh" /usr/local/bin/mtproxy-fetch-config.sh
install -m 755 "${REPO_DIR}/scripts/mtproxy-watchdog.sh" /usr/local/bin/mtproxy-watchdog.sh
install -m 755 "${REPO_DIR}/scripts/generate-client-secret.sh" /usr/local/bin/mtproxy-generate-client-secret
install -m 644 "${REPO_DIR}/templates/mtproxy.service" /etc/systemd/system/mtproxy.service
install -m 644 "${REPO_DIR}/templates/mtproxy-watchdog.service" /etc/systemd/system/mtproxy-watchdog.service
install -m 644 "${REPO_DIR}/templates/mtproxy-watchdog.timer" /etc/systemd/system/mtproxy-watchdog.timer
install -m 644 "${REPO_DIR}/templates/mtproxy-refresh.service" /etc/systemd/system/mtproxy-refresh.service
install -m 644 "${REPO_DIR}/templates/mtproxy-refresh.timer" /etc/systemd/system/mtproxy-refresh.timer

if [[ ! -f "${ENV_FILE}" ]]; then
  raw_secret="$(openssl rand -hex 16)"
  client_secret="$(/usr/local/bin/mtproxy-generate-client-secret "${raw_secret}" "${FAKE_HOST}")"
  cat >"${ENV_FILE}" <<EOF
PORT=${PORT}
STATS_PORT=${STATS_PORT}
FAKE_HOST=${FAKE_HOST}
SECRET_RAW=${raw_secret}
SECRET_TLS=${client_secret}
EOF
  chmod 600 "${ENV_FILE}"
  echo "created ${ENV_FILE}"
else
  echo "keeping existing ${ENV_FILE}"
fi

if [[ ! -f "${MANAGED_LIST}" ]]; then
  raw_secret="$(awk -F= '/^SECRET_RAW=/{print $2}' "${ENV_FILE}")"
  printf '%s\n' "${raw_secret}" > "${MANAGED_LIST}"
  chmod 600 "${MANAGED_LIST}"
  echo "created ${MANAGED_LIST}"
fi

/usr/local/bin/mtproxy-fetch-config.sh

if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable --now mtproxy.service
systemctl enable --now mtproxy-watchdog.timer
systemctl enable --now mtproxy-refresh.timer

echo
echo "MTProxy runtime installed."
echo "Env file: ${ENV_FILE}"
echo "Managed secrets: ${MANAGED_LIST}"
echo "Log file: ${LOG_FILE}"
echo "Client secret:"
awk -F= '/^SECRET_TLS=/{print $2}' "${ENV_FILE}"
