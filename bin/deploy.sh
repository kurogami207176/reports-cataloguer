#!/usr/bin/env bash
# deploy.sh
# Deploys the full Reports Cataloguer stack to AWS directly from the repo.
#
# Steps performed:
#   1. Fetch VPC outputs from the vpc stack (created by bootstrap.sh)
#   2. Deploy (create or update) the main CloudFormation stack
#   3. Force a new ECS deployment so tasks pick up the latest image
#
# Usage:
#   ./bin/deploy.sh [image-tag]
#
# Required environment variables:
#   BUCKET_SUFFIX  – unique suffix for the S3 submissions bucket (e.g. account ID)
#
# Optional:
#   AWS_REGION               (default: ap-southeast-2)
#   AWS_ACCOUNT_ID           (auto-detected if not set)
#   APP_NAME                 (default: reports-cataloguer)
#   USER_POOL_DOMAIN_PREFIX  (default: reports-cataloguer)
#   DESIRED_COUNT            (default: 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
APP_NAME="${APP_NAME:-reports-cataloguer}"
IMAGE_TAG="${1:-latest}"
STACK_NAME="${APP_NAME}-stack"
VPC_STACK_NAME="${APP_NAME}-vpc"
USER_POOL_DOMAIN_PREFIX="${USER_POOL_DOMAIN_PREFIX:-${APP_NAME}}"
DESIRED_COUNT="${DESIRED_COUNT:-1}"

: "${BUCKET_SUFFIX:?BUCKET_SUFFIX must be set}"

if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

# ---------------------------------------------------------------------------
# 1. Fetch VPC outputs
# ---------------------------------------------------------------------------
echo "==> Fetching network outputs from stack: ${VPC_STACK_NAME}"

get_output() {
  aws cloudformation describe-stacks \
    --region "${AWS_REGION}" \
    --stack-name "${1}" \
    --query "Stacks[0].Outputs[?OutputKey=='${2}'].OutputValue" \
    --output text
}

VPC_ID="$(get_output "${VPC_STACK_NAME}" VpcId)"
PUBLIC_SUBNET_1="$(get_output "${VPC_STACK_NAME}" PublicSubnet1)"
PUBLIC_SUBNET_2="$(get_output "${VPC_STACK_NAME}" PublicSubnet2)"

# ---------------------------------------------------------------------------
# 2. Deploy stack
# ---------------------------------------------------------------------------
echo "==> Deploying CloudFormation stack: ${STACK_NAME}"
aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${REPO_ROOT}/cf/main.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    AppName="${APP_NAME}" \
    EcrRepositoryUri="${ECR_REPOSITORY_URI}" \
    UserPoolDomainPrefix="${USER_POOL_DOMAIN_PREFIX}" \
    BucketSuffix="${BUCKET_SUFFIX}" \
    VpcId="${VPC_ID}" \
    PublicSubnet1="${PUBLIC_SUBNET_1}" \
    PublicSubnet2="${PUBLIC_SUBNET_2}" \
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
ALB_DNS="$(get_output "${STACK_NAME}" AlbDnsName)"

echo ""
echo "================================================================="
echo "  Deployment complete!"
echo "  API endpoint: http://${ALB_DNS}"
echo "================================================================="
