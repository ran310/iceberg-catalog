#!/bin/bash
set -euxo pipefail
install -d -m 755 /opt/iceberg-catalog
# SQLite catalog.db lives here (bind-mounted as /data in the container). Mode 700 + non-root
# container user causes SQLITE_CANTOPEN; 755 + root-run container (:z for SELinux) fixes AL2023.
install -d -m 755 /var/lib/iceberg-catalog

# Env: if the bundle ships deploy/iceberg-catalog.env, always refresh /etc (CI/CD friendly).
# Otherwise seed /etc once from example so the unit can start without SSH on first deploy.
if [[ -f /opt/iceberg-catalog/deploy/iceberg-catalog.env ]]; then
  install -m 600 /opt/iceberg-catalog/deploy/iceberg-catalog.env /etc/iceberg-catalog.env
elif [[ ! -f /etc/iceberg-catalog.env ]]; then
  install -m 600 /opt/iceberg-catalog/deploy/iceberg-catalog.env.example /etc/iceberg-catalog.env
  echo "WARN: Using iceberg-catalog.env.example — add deploy/iceberg-catalog.env to the bundle for real settings." >&2
fi

# HTTP Basic auth for nginx (path must match aws-infra ICEBERG_CATALOG_HTPASSWD_PATH).
HT="/etc/nginx/.htpasswd-iceberg-catalog"
if [[ ! -f "$HT" ]]; then
  install -m 640 /dev/null "$HT"
  chown root:nginx "$HT" 2>/dev/null || chown root:root "$HT"
fi
if [[ -f /opt/iceberg-catalog/deploy/iceberg-catalog.htpasswd ]]; then
  install -m 640 /opt/iceberg-catalog/deploy/iceberg-catalog.htpasswd "$HT"
  chown root:nginx "$HT" 2>/dev/null || chown root:root "$HT"
fi

install -m 644 /opt/iceberg-catalog/deploy/iceberg-catalog.service /etc/systemd/system/iceberg-catalog.service
systemctl daemon-reload
systemctl enable iceberg-catalog.service

if command -v nginx >/dev/null 2>&1; then
  nginx -t && systemctl reload nginx || echo "WARN: nginx reload failed (check config or run sudo nginx -t)." >&2
fi
