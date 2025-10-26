#!/bin/bash
set -e

echo "🚀 InfraForge Setup Script"
echo "=========================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUCKET_NAME="infraforge-terraform-state"
DYNAMODB_TABLE="infraforge-terraform-locks"
AWS_REGION="eu-west-1"

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ AWS CLI not found${NC}"; exit 1; }
command -v tofu >/dev/null 2>&1 || { echo -e "${RED}❌ OpenTofu not found${NC}"; echo "Install from: https://opentofu.org/docs/intro/install/"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}❌ kubectl not found${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}❌ Helm not found${NC}"; exit 1; }
echo -e "${GREEN}✅ All prerequisites installed${NC}"
echo ""

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
aws sts get-caller-identity >/dev/null 2>&1 || { echo -e "${RED}❌ AWS credentials not configured${NC}"; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ AWS credentials valid (Account: $ACCOUNT_ID)${NC}"
echo ""

# Create S3 bucket for OpenTofu state
echo "📦 Creating S3 bucket for OpenTofu state..."
if aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null; then
  echo -e "${YELLOW}⚠️  Bucket already exists${NC}"
else
  aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $AWS_REGION \
    --create-bucket-configuration LocationConstraint=$AWS_REGION

  echo -e "${GREEN}✅ S3 bucket created${NC}"
fi

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo -e "${GREEN}✅ S3 bucket configured${NC}"
echo ""

# Create DynamoDB table for state locking
echo "🔒 Creating DynamoDB table for state locking..."
if aws dynamodb describe-table --table-name $DYNAMODB_TABLE --region $AWS_REGION >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  DynamoDB table already exists${NC}"
else
  aws dynamodb create-table \
    --table-name $DYNAMODB_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $AWS_REGION

  echo -e "${GREEN}✅ DynamoDB table created${NC}"
fi
echo ""

# Add Helm repositories
echo "📚 Adding Helm repositories..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update
echo -e "${GREEN}✅ Helm repositories added${NC}"
echo ""

# Check if config/apps.yaml exists
echo "📝 Checking configuration file..."
if [ ! -f "../config/apps.yaml" ]; then
  echo -e "${RED}❌ config/apps.yaml not found${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Configuration file found${NC}"
echo ""

# Initialize OpenTofu
echo "🏗️  Initializing OpenTofu..."
cd ../terraform
tofu init
echo -e "${GREEN}✅ OpenTofu initialized${NC}"
echo ""

echo "=========================================="
echo -e "${GREEN}✅ Setup complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Copy terraform.tfvars.example to terraform.tfvars"
echo "   cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
echo ""
echo "2. Edit terraform.tfvars and update with your values"
echo "   vim terraform/terraform.tfvars"
echo ""
echo "3. Review and edit config/apps.yaml"
echo "   vim config/apps.yaml"
echo ""
echo "4. Run OpenTofu plan to see what will be created"
echo "   cd terraform && tofu plan"
echo ""
echo "5. Apply the infrastructure"
echo "   tofu apply"
echo ""
echo "6. Build and push application images to ECR"
echo "   ../scripts/push-images.sh"
echo ""
