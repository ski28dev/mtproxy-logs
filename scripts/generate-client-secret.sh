#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <raw-secret-32-hex> <fake-host>" >&2
  exit 1
fi

raw_secret="$1"
fake_host="$2"

python3 - "$raw_secret" "$fake_host" <<'PY'
import binascii
import re
import sys

raw_secret = sys.argv[1].strip().lower()
fake_host = sys.argv[2].strip()

if not re.fullmatch(r"[0-9a-f]{32}", raw_secret):
    raise SystemExit("raw secret must be exactly 32 hex chars")

host_hex = fake_host.encode("utf-8").hex()
print(f"ee{raw_secret}{host_hex}")
PY

