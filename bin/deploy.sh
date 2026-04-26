#!/usr/bin/env bash
# deploy.sh
# Deploys the full Reports Cataloguer stack to AWS.
#
# Steps performed:
#   1. Upload CloudFormation templates to S3
#   2. Deploy (create or update) the main CloudFormation stack
#   3. Force a new ECS deployment so tasks pick up the latest image
#
# Usage:
#   ./bin/deploy.sh [image-tag]
#
# Required environment variables:
#   AWS_REGION           – AWS region
#   AWS_ACCOUNT_ID       – AWS account ID (auto-detected if not set)
#   APP_NAME             – application name (default: reports-cataloguer)
#   CF_TEMPLATES_BUCKET  – S3 bucket that stores the CF templates
#   VPC_ID               – VPC ID
#   PUBLIC_SUBNET_1      – first public subnet
#   PUBLIC_SUBNET_2      – second public subnet
#   PRIVATE_SUBNET_1     – first private subnet
#   PRIVATE_SUBNET_2     – second private subnet
#   BUCKET_SUFFIX        – unique suffix for the S3 submissions bucket
#
# Optional:
#   USER_POOL_DOMAIN_PREFIX  (default: reports-cataloguer)
#   DESIRED_COUNT            (default: 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAME="${APP_NAME:-reports-cataloguer}"
IMAGE_TAG="${1:-latest}"
STACK_NAME="${APP_NAME}-stack"
USER_POOL_DOMAIN_PREFIX="${USER_POOL_DOMAIN_PREFIX:-${APP_NAME}}"
DESIRED_COUNT="${DESIRED_COUNT:-1}"

: "${CF_TEMPLATES_BUCKET:?CF_TEMPLATES_BUCKET must be set}"
: "${VPC_ID:?VPC_ID must be set}"
: "${PUBLIC_SUBNET_1:?PUBLIC_SUBNET_1 must be set}"
: "${PUBLIC_SUBNET_2:?PUBLIC_SUBNET_2 must be set}"
: "${PRIVATE_SUBNET_1:?PRIVATE_SUBNET_1 must be set}"
: "${PRIVATE_SUBNET_2:?PRIVATE_SUBNET_2 must be set}"
: "${BUCKET_SUFFIX:?BUCKET_SUFFIX must be set}"

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

CF_PREFIX="${APP_NAME}/cf"
TEMPLATES_URL="https://s3.amazonaws.com/${CF_TEMPLATES_BUCKET}/${CF_PREFIX}"

# ---------------------------------------------------------------------------
# 1. Upload CF templates
# ---------------------------------------------------------------------------
echo "==> Uploading CloudFormation templates to s3://${CF_TEMPLATES_BUCKET}/${CF_PREFIX}/"
aws s3 sync \
  "${REPO_ROOT}/cf/" \
  "s3://${CF_TEMPLATES_BUCKET}/${CF_PREFIX}/" \
  --exclude "*" \
  --include "*.yaml" \
  --region "${AWS_REGION}"

# ---------------------------------------------------------------------------
# 2. Deploy main stack
# ---------------------------------------------------------------------------
echo "==> Deploying CloudFormation stack: ${STACK_NAME}"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${REPO_ROOT}/cf/main.yaml" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    AppName="${APP_NAME}" \
    TemplatesBucketUrl="${TEMPLATES_URL}" \
    UserPoolDomainPrefix="${USER_POOL_DOMAIN_PREFIX}" \
    BucketSuffix="${BUCKET_SUFFIX}" \
    VpcId="${VPC_ID}" \
    PublicSubnet1="${PUBLIC_SUBNET_1}" \
    PublicSubnet2="${PUBLIC_SUBNET_2}" \
    PrivateSubnet1="${PRIVATE_SUBNET_1}" \
    PrivateSubnet2="${PRIVATE_SUBNET_2}" \
    DesiredCount="${DESIRED_COUNT}" \
    AwsRegion="${AWS_REGION}" \
    ImageTag="${IMAGE_TAG}" \
  --no-fail-on-empty-changeset

# ---------------------------------------------------------------------------
# 3. Force ECS redeployment
# ---------------------------------------------------------------------------
CLUSTER_NAME="${APP_NAME}-cluster"
SERVICE_NAME="${APP_NAME}-service"

echo "==> Forcing new ECS deployment for ${SERVICE_NAME}"
aws ecs update-service \
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --service "${SERVICE_NAME}" \
  --force-new-deployment \
  --output text \
  --query "service.serviceName"

echo "==> Waiting for ECS service to stabilise…"
aws ecs wait services-stable \
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}"

# ---------------------------------------------------------------------------
# 4. Print outputs
# ---------------------------------------------------------------------------
ALB_DNS="$(aws cloudformation describe-stacks \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" \
  --output text)"

echo ""
echo "================================================================="
echo "  Deployment complete!"
echo "  API endpoint: http://${ALB_DNS}"
echo "================================================================="
