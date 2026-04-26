#!/usr/bin/env bash
# bootstrap.sh
# One-time setup: creates the VPC and ECR repository so the main stack can be
# deployed and Docker images can be pushed.
#
# Run this once. After that, use build-and-push.sh and deploy.sh for all
# subsequent deployments.
#
# Usage:
#   ./bin/bootstrap.sh
#
# Environment variables:
#   AWS_REGION  – AWS region (default: ap-southeast-2)
#   APP_NAME    – application name (default: reports-cataloguer)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_REGION="${AWS_REGION:-ap-southeast-2}"
APP_NAME="${APP_NAME:-reports-cataloguer}"

# ---------------------------------------------------------------------------
# 1. VPC
# ---------------------------------------------------------------------------
VPC_STACK_NAME="${APP_NAME}-vpc"
echo "==> Deploying VPC stack: ${VPC_STACK_NAME}"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${VPC_STACK_NAME}" \
  --template-file "${REPO_ROOT}/cf/vpc.yaml" \
  --parameter-overrides AppName="${APP_NAME}" \
  --no-fail-on-empty-changeset

# ---------------------------------------------------------------------------
# 2. ECR
# ---------------------------------------------------------------------------
ECR_STACK_NAME="${APP_NAME}-ecr"
echo "==> Deploying ECR stack: ${ECR_STACK_NAME}"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${ECR_STACK_NAME}" \
  --template-file "${REPO_ROOT}/cf/ecr.yaml" \
  --parameter-overrides AppName="${APP_NAME}" \
  --no-fail-on-empty-changeset

ECR_REPOSITORY_URI="$(aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${ECR_STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text)"

echo ""
echo "================================================================="
echo "  Bootstrap complete!"
echo "  ECR repository: ${ECR_REPOSITORY_URI}"
echo ""
echo "  You can now run:"
echo "    ./bin/build-and-push.sh v1.0.0"
echo "    BUCKET_SUFFIX=<account-id> ./bin/deploy.sh v1.0.0"
echo "================================================================="
