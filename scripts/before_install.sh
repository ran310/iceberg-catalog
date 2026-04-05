#!/bin/bash
set -euxo pipefail
systemctl stop iceberg-catalog.service 2>/dev/null || true
/usr/bin/docker rm -f iceberg-rest 2>/dev/null || true
