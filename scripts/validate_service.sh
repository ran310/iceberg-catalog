#!/bin/bash
set -euxo pipefail
# REST spec: config route (anonymous read of server capabilities).
# Avoid `curl | head` under pipefail: head can close the pipe early and curl exits 141 (SIGPIPE).
URL="http://127.0.0.1:8085/v1/config"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
for _ in $(seq 1 5); do
  if curl -fsS "$URL" -o "$TMP" 2>/dev/null; then
    head -c 4000 "$TMP"
    exit 0
  fi
  sleep 2
done
echo "ValidateService: no successful response from $URL after 60s" >&2
exit 1
