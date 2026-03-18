#!/usr/bin/env bash
set -euo pipefail
exec /usr/bin/unshare --fork --pid --mount-proc -- /usr/local/bin/mtproxy-managed-run.sh
