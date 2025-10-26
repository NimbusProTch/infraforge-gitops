#!/bin/bash
set -e

echo "🐳 Building and pushing Docker images to ECR"
echo "============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="eu-west-1"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "📋 Configuration:"
echo "  AWS Account ID: $AWS_ACCOUNT_ID"
echo "  AWS Region: $AWS_REGION"
echo "  ECR Registry: $ECR_REGISTRY"
echo ""

# Login to ECR
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
echo -e "${GREEN}✅ Logged in to ECR${NC}"
echo ""

# Change to project root
cd "$(dirname "$0")/.."

# Check if yq is available
if ! command -v yq >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  yq not found, processing all apps in apps/ directory${NC}"
  # Process all directories in apps/
  APPS=$(find apps -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
else
  # Read apps from config file
  APPS=$(yq eval '.applications | keys | .[]' config/apps.yaml)
fi

# Counter for tracking
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# Process each app
for APP in $APPS; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 Processing: $APP"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  APP_DIR="apps/$APP"

  if [ ! -d "$APP_DIR" ]; then
    echo -e "${YELLOW}⚠️  Directory $APP_DIR not found, skipping...${NC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo ""
    continue
  fi

  if [ ! -f "$APP_DIR/Dockerfile" ]; then
    echo -e "${YELLOW}⚠️  Dockerfile not found in $APP_DIR, skipping...${NC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo ""
    continue
  fi

  # Build image
  echo "🔨 Building Docker image..."
  if docker build -t $APP:latest $APP_DIR; then
    echo -e "${GREEN}✅ Build successful${NC}"
  else
    echo -e "${RED}❌ Build failed${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # Tag for ECR
  echo "🏷️  Tagging image for ECR..."
  docker tag $APP:latest $ECR_REGISTRY/$APP:latest
  echo -e "${GREEN}✅ Tagged${NC}"

  # Push to ECR
  echo "⬆️  Pushing to ECR..."
  if docker push $ECR_REGISTRY/$APP:latest; then
    echo -e "${GREEN}✅ $APP pushed to ECR successfully${NC}"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo -e "${RED}❌ Failed to push $APP${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  echo ""
done

# Summary
echo "=========================================="
echo "📊 Summary"
echo "=========================================="
echo -e "${GREEN}✅ Successful: $SUCCESS_COUNT${NC}"
echo -e "${YELLOW}⚠️  Skipped: $SKIP_COUNT${NC}"
echo -e "${RED}❌ Failed: $FAIL_COUNT${NC}"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
  echo -e "${GREEN}✅ Images pushed successfully!${NC}"
  echo ""
  echo "View images in ECR:"
  for APP in $APPS; do
    if [ -d "apps/$APP" ] && [ -f "apps/$APP/Dockerfile" ]; then
      echo "  $ECR_REGISTRY/$APP:latest"
    fi
  done
fi

if [ $FAIL_COUNT -gt 0 ]; then
  exit 1
fi
