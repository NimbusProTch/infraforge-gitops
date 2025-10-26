#!/bin/bash
set -e

echo "🗑️  InfraForge Cleanup Script"
echo "============================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}⚠️  WARNING: This will destroy ALL infrastructure!${NC}"
echo ""
echo "This includes:"
echo "  - EKS Cluster"
echo "  - RDS Databases"
echo "  - VPC and all networking"
echo "  - ECR Repositories (images will be deleted)"
echo "  - All applications and data"
echo ""
read -p "Are you absolutely sure? Type 'destroy' to confirm: " confirm

if [ "$confirm" != "destroy" ]; then
  echo -e "${YELLOW}⚠️  Cleanup cancelled${NC}"
  exit 0
fi

# Change to terraform directory
cd "$(dirname "$0")/../terraform"

# Check if tofu is available
if ! command -v tofu >/dev/null 2>&1; then
  echo -e "${RED}❌ OpenTofu not found${NC}"
  echo "Install from: https://opentofu.org/docs/intro/install/"
  exit 1
fi

TF_CMD="tofu"

echo ""
echo "🗑️  Running $TF_CMD destroy..."
$TF_CMD destroy

echo ""
read -p "Do you want to clean up OpenTofu state in S3? (yes/no): " clean_state

if [ "$clean_state" == "yes" ]; then
  BUCKET_NAME="infraforge-terraform-state"
  DYNAMODB_TABLE="infraforge-terraform-locks"
  AWS_REGION="eu-west-1"

  echo ""
  echo "🗑️  Cleaning up S3 bucket..."

  # Empty S3 bucket
  aws s3 rm s3://$BUCKET_NAME --recursive --region $AWS_REGION || true

  # Delete S3 bucket
  aws s3api delete-bucket --bucket $BUCKET_NAME --region $AWS_REGION || true

  # Delete DynamoDB table
  echo "🗑️  Deleting DynamoDB table..."
  aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION || true

  echo -e "${GREEN}✅ State storage cleaned up${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo "=========================================="
echo ""
