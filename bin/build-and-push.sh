#!/usr/bin/env bash
# build-and-push.sh
# Builds the Docker image for the backend service and pushes it to ECR.
#
# Usage:
#   ./bin/build-and-push.sh [image-tag]
#
# Environment variables (can also be set via .env):
#   AWS_REGION      – AWS region (default: ap-southeast-2)
#   AWS_ACCOUNT_ID  – AWS account ID (auto-detected if not set)
#   APP_NAME        – application/ECR repository name (default: reports-cataloguer)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
APP_NAME="${APP_NAME:-reports-cataloguer}"
IMAGE_TAG="${1:-latest}"

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

echo "==> Building Docker image: ${ECR_URI}:${IMAGE_TAG}"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
docker build \
  --platform linux/amd64 \
  --tag "${ECR_URI}:${IMAGE_TAG}" \
  "${REPO_ROOT}/service"

# Tag as latest as well (unless the caller already specified "latest")
if [[ "${IMAGE_TAG}" != "latest" ]]; then
  docker tag "${ECR_URI}:${IMAGE_TAG}" "${ECR_URI}:latest"
fi

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
echo "==> Authenticating with ECR"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin \
      "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "==> Pushing ${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:${IMAGE_TAG}"

if [[ "${IMAGE_TAG}" != "latest" ]]; then
  docker push "${ECR_URI}:latest"
fi

echo "==> Done. Image: ${ECR_URI}:${IMAGE_TAG}"
