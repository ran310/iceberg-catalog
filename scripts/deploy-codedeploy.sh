#!/usr/bin/env bash
# Package this repo, upload to S3, and start a CodeDeploy deployment.
# Prereqs: aws CLI v2, zip, deploy/iceberg-catalog.env present in the repo.
#
# Required environment variables:
#   CODEDEPLOY_APPLICATION       — CodeDeploy application name
#   CODEDEPLOY_DEPLOYMENT_GROUP  — deployment group name (targets your EC2 host)
#   CODEDEPLOY_S3_BUCKET         — bucket for the revision zip
#
# Optional:
#   CODEDEPLOY_S3_KEY            — object key (default: iceberg-catalog/releases/<timestamp>-bundle.zip)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${CODEDEPLOY_APPLICATION:?set CODEDEPLOY_APPLICATION}"
: "${CODEDEPLOY_DEPLOYMENT_GROUP:?set CODEDEPLOY_DEPLOYMENT_GROUP}"
: "${CODEDEPLOY_S3_BUCKET:?set CODEDEPLOY_S3_BUCKET}"

if [[ ! -f deploy/iceberg-catalog.env ]]; then
  echo "Missing deploy/iceberg-catalog.env — copy deploy/iceberg-catalog.env.example and set CATALOG_WAREHOUSE / AWS_REGION." >&2
  exit 1
fi

KEY="${CODEDEPLOY_S3_KEY:-iceberg-catalog/releases/$(date +%Y%m%d-%H%M%S)-bundle.zip}"
ZIP="$(mktemp -t iceberg-catalog-bundle.XXXXXX.zip)"
trap 'rm -f "$ZIP"' EXIT

zip -qr "$ZIP" appspec.yml deploy scripts
aws s3 cp "$ZIP" "s3://${CODEDEPLOY_S3_BUCKET}/${KEY}"
aws deploy create-deployment \
  --application-name "${CODEDEPLOY_APPLICATION}" \
  --deployment-group-name "${CODEDEPLOY_DEPLOYMENT_GROUP}" \
  --s3-location "bucket=${CODEDEPLOY_S3_BUCKET},key=${KEY},bundleType=zip"

echo "Uploaded s3://${CODEDEPLOY_S3_BUCKET}/${KEY} and started deployment."
