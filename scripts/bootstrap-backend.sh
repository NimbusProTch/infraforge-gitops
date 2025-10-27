#!/bin/bash
# ============================================================================
# Terraform Backend Bootstrap Script
# ============================================================================
# Creates S3 bucket and DynamoDB table for Terraform state management.
# Run this BEFORE terraform init/plan/apply.
#
# Usage: ./bootstrap-backend.sh
# ============================================================================

set -e

# Configuration
REGION="${AWS_REGION:-eu-west-1}"
PROJECT_NAME="infraforge"
ENVIRONMENT="production"
S3_BUCKET="${PROJECT_NAME}-terraform-state"
DYNAMODB_TABLE="${PROJECT_NAME}-terraform-locks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials are not configured"
        exit 1
    fi

    local account_id=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS account: $account_id"
}

# Create S3 bucket for Terraform state
create_s3_bucket() {
    log_info "Creating S3 bucket: $S3_BUCKET..."

    # Check if bucket exists
    if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
        log_warning "S3 bucket already exists: $S3_BUCKET"
        return 0
    fi

    # Create bucket
    if [ "$REGION" = "us-east-1" ]; then
        # us-east-1 doesn't need LocationConstraint
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$REGION" 2>/dev/null
    else
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null
    fi

    log_success "S3 bucket created: $S3_BUCKET"

    # Enable versioning
    log_info "Enabling versioning on S3 bucket..."
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$REGION"
    log_success "Versioning enabled"

    # Enable encryption
    log_info "Enabling encryption on S3 bucket..."
    aws s3api put-bucket-encryption \
        --bucket "$S3_BUCKET" \
        --region "$REGION" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    log_success "Encryption enabled"

    # Block public access
    log_info "Blocking public access on S3 bucket..."
    aws s3api put-public-access-block \
        --bucket "$S3_BUCKET" \
        --region "$REGION" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    log_success "Public access blocked"

    # Add lifecycle policy (optional - keep last 30 versions)
    log_info "Adding lifecycle policy..."
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --region "$REGION" \
        --lifecycle-configuration '{
            "Rules": [{
                "Id": "ExpireOldVersions",
                "Status": "Enabled",
                "NoncurrentVersionExpiration": {
                    "NoncurrentDays": 30
                }
            }]
        }'
    log_success "Lifecycle policy added"

    # Add tags
    log_info "Adding tags..."
    aws s3api put-bucket-tagging \
        --bucket "$S3_BUCKET" \
        --region "$REGION" \
        --tagging "TagSet=[
            {Key=Project,Value=$PROJECT_NAME},
            {Key=Environment,Value=$ENVIRONMENT},
            {Key=ManagedBy,Value=bootstrap-script},
            {Key=Purpose,Value=terraform-state}
        ]"
    log_success "Tags added"
}

# Create DynamoDB table for state locking
create_dynamodb_table() {
    log_info "Creating DynamoDB table: $DYNAMODB_TABLE..."

    # Check if table exists
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
        log_warning "DynamoDB table already exists: $DYNAMODB_TABLE"
        return 0
    fi

    # Create table
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --region "$REGION" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags \
            Key=Project,Value="$PROJECT_NAME" \
            Key=Environment,Value="$ENVIRONMENT" \
            Key=ManagedBy,Value=bootstrap-script \
            Key=Purpose,Value=terraform-state-locking

    log_success "DynamoDB table created: $DYNAMODB_TABLE"

    # Wait for table to be active
    log_info "Waiting for table to become active..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$REGION"

    log_success "Table is now active"
}

# Verify backend configuration
verify_backend() {
    log_info "Verifying backend configuration..."

    # Check S3 bucket
    if aws s3 ls "s3://$S3_BUCKET" &>/dev/null; then
        log_success "✓ S3 bucket accessible"
    else
        log_error "✗ S3 bucket not accessible"
        exit 1
    fi

    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
        log_success "✓ DynamoDB table accessible"
    else
        log_error "✗ DynamoDB table not accessible"
        exit 1
    fi

    echo ""
    log_success "Backend is ready!"
    echo ""
    echo "Configuration:"
    echo "  Region:          $REGION"
    echo "  S3 Bucket:       $S3_BUCKET"
    echo "  DynamoDB Table:  $DYNAMODB_TABLE"
    echo ""
    echo "Add this to your terraform backend configuration:"
    echo ""
    echo "terraform {"
    echo "  backend \"s3\" {"
    echo "    bucket         = \"$S3_BUCKET\""
    echo "    key            = \"$ENVIRONMENT/terraform.tfstate\""
    echo "    region         = \"$REGION\""
    echo "    dynamodb_table = \"$DYNAMODB_TABLE\""
    echo "    encrypt        = true"
    echo "  }"
    echo "}"
}

# Main function
main() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Terraform Backend Bootstrap${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""

    check_prerequisites

    echo ""
    create_s3_bucket

    echo ""
    create_dynamodb_table

    echo ""
    verify_backend

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Bootstrap Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
}

# Run main function
main
