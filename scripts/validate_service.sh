#!/bin/bash
set -euxo pipefail
# REST spec: config route (anonymous read of server capabilities).
curl -fsS "http://127.0.0.1:8085/v1/config" | head -c 4000
