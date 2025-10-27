#!/bin/bash
# ============================================================================
# Full Infrastructure Cleanup Script
# ============================================================================
# This script performs a complete cleanup of the InfraForge infrastructure:
# 1. Cleans up stuck Kubernetes namespaces
# 2. Deletes LoadBalancers created by Kubernetes
# 3. Runs terraform/tofu destroy
# 4. Manual cleanup of remaining AWS resources
#
# Usage: ./full-cleanup.sh [--skip-k8s] [--skip-aws]
#   --skip-k8s: Skip Kubernetes cleanup
#   --skip-aws: Skip AWS cleanup (only run terraform destroy)
# ============================================================================

set -e

# Configuration
REGION="${AWS_REGION:-eu-west-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
SKIP_K8S=false
SKIP_AWS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-k8s)
            SKIP_K8S=true
            shift
            ;;
        --skip-aws)
            SKIP_AWS=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Helper functions
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

    local missing_tools=()

    if [ "$SKIP_K8S" = false ]; then
        command -v kubectl &>/dev/null || missing_tools+=("kubectl")
        command -v jq &>/dev/null || missing_tools+=("jq")
    fi

    if [ "$SKIP_AWS" = false ]; then
        command -v aws &>/dev/null || missing_tools+=("aws-cli")
    fi

    command -v tofu &>/dev/null || missing_tools+=("opentofu")

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Step 1: Cleanup Kubernetes namespaces
cleanup_k8s_namespaces() {
    if [ "$SKIP_K8S" = true ]; then
        log_warning "Skipping Kubernetes cleanup"
        return 0
    fi

    log_info "Step 1: Cleaning up stuck Kubernetes namespaces..."

    if ! kubectl cluster-info &>/dev/null; then
        log_warning "Not connected to Kubernetes cluster, skipping namespace cleanup"
        return 0
    fi

    # Run namespace cleanup script
    if [ -f "${SCRIPT_DIR}/cleanup-namespaces.sh" ]; then
        "${SCRIPT_DIR}/cleanup-namespaces.sh" || log_warning "Some namespaces could not be cleaned up"
    else
        log_warning "Namespace cleanup script not found"
    fi

    log_success "Kubernetes namespace cleanup completed"
}

# Step 2: Delete Kubernetes LoadBalancers
cleanup_k8s_loadbalancers() {
    if [ "$SKIP_K8S" = true ] || [ "$SKIP_AWS" = true ]; then
        log_warning "Skipping LoadBalancer cleanup"
        return 0
    fi

    log_info "Step 2: Deleting Kubernetes LoadBalancers..."

    if ! kubectl cluster-info &>/dev/null; then
        log_warning "Not connected to Kubernetes cluster, skipping LoadBalancer cleanup"
        return 0
    fi

    # Get all LoadBalancer services and delete them
    local lb_services=$(kubectl get svc --all-namespaces -o json | \
        jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"')

    if [ -z "$lb_services" ]; then
        log_info "No LoadBalancer services found"
    else
        echo "$lb_services" | while read -r svc; do
            local namespace=$(echo "$svc" | cut -d'/' -f1)
            local name=$(echo "$svc" | cut -d'/' -f2)
            log_info "Deleting LoadBalancer service: $namespace/$name"
            kubectl delete svc "$name" -n "$namespace" --timeout=60s || log_warning "Failed to delete $namespace/$name"
        done
    fi

    log_success "LoadBalancer cleanup completed"
}

# Step 3: Run terraform destroy
run_terraform_destroy() {
    log_info "Step 3: Running Terraform/OpenTofu destroy..."

    cd "$TERRAFORM_DIR"

    # Force unlock if needed
    log_info "Checking for state locks..."
    tofu force-unlock -force $(tofu state list 2>/dev/null | head -1 | cut -d'.' -f1) 2>/dev/null || true

    # Run destroy
    log_info "Starting infrastructure destroy (this may take 10-20 minutes)..."
    if tofu destroy -auto-approve; then
        log_success "Terraform destroy completed successfully"
    else
        log_warning "Terraform destroy completed with errors, continuing with manual cleanup..."
    fi
}

# Step 3.5: Wait for EKS cluster deletion
wait_for_eks_deletion() {
    if [ "$SKIP_AWS" = true ]; then
        log_warning "Skipping EKS deletion wait"
        return 0
    fi

    log_info "Step 3.5: Waiting for EKS cluster deletion..."

    # Check if any EKS clusters exist
    local eks_clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>/dev/null | wc -w)

    if [ "$eks_clusters" -eq 0 ]; then
        log_success "No EKS clusters found, continuing..."
        return 0
    fi

    log_info "Found $eks_clusters EKS cluster(s), waiting for deletion..."

    local max_wait=600  # 10 minutes max
    local waited=0
    local interval=30

    while [ $waited -lt $max_wait ]; do
        eks_clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>/dev/null | wc -w)

        if [ "$eks_clusters" -eq 0 ]; then
            log_success "EKS cluster(s) deleted successfully"
            return 0
        fi

        log_info "Still waiting... ($waited/$max_wait seconds elapsed)"
        sleep $interval
        waited=$((waited + interval))
    done

    log_warning "EKS cluster deletion timeout reached, continuing anyway..."
}

# Step 4: Manual AWS resource cleanup
cleanup_aws_resources() {
    if [ "$SKIP_AWS" = true ]; then
        log_warning "Skipping AWS cleanup"
        return 0
    fi

    log_info "Step 4: Manual AWS resource cleanup..."

    # Get VPC ID from remaining resources
    local vpc_id=$(aws ec2 describe-vpcs --region "$REGION" \
        --filters "Name=tag:Project,Values=infraforge-eks" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")

    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
        log_info "No VPC found, skipping VPC cleanup"
        return 0
    fi

    log_info "Found VPC: $vpc_id"

    # Delete LoadBalancers in VPC
    log_info "Checking for LoadBalancers in VPC..."
    local lbs=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" --output text 2>/dev/null || echo "")

    if [ -n "$lbs" ]; then
        echo "$lbs" | tr '\t' '\n' | while read -r lb_arn; do
            [ -z "$lb_arn" ] && continue
            log_info "Deleting LoadBalancer: $lb_arn"
            aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$lb_arn" 2>/dev/null || log_warning "Failed to delete LoadBalancer"
        done
        log_info "Waiting for LoadBalancers to be deleted..."
        sleep 30
    fi

    # Delete Security Groups (except default)
    log_info "Cleaning up security groups..."
    local security_groups=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")

    if [ -n "$security_groups" ]; then
        echo "$security_groups" | tr '\t' '\n' | while read -r sg_id; do
            [ -z "$sg_id" ] && continue
            log_info "Deleting security group: $sg_id"
            aws ec2 delete-security-group --region "$REGION" --group-id "$sg_id" 2>/dev/null || log_warning "Failed to delete security group $sg_id"
        done
    fi

    # Try to delete VPC
    log_info "Attempting to delete VPC..."
    if aws ec2 delete-vpc --region "$REGION" --vpc-id "$vpc_id" 2>/dev/null; then
        log_success "VPC deleted successfully"
    else
        log_warning "VPC could not be deleted (may have dependencies)"
    fi

    log_success "AWS resource cleanup completed"
}

# Step 5: Verify cleanup
verify_cleanup() {
    log_info "Step 5: Verifying cleanup..."

    local issues=0

    # Check EKS clusters
    local eks_clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>/dev/null | wc -w)
    if [ "$eks_clusters" -gt 0 ]; then
        log_warning "Found $eks_clusters EKS cluster(s) still running"
        ((issues++))
    else
        log_success "No EKS clusters found"
    fi

    # Check EC2 instances
    local ec2_instances=$(aws ec2 describe-instances --region "$REGION" \
        --filters "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null | wc -w)
    if [ "$ec2_instances" -gt 0 ]; then
        log_warning "Found $ec2_instances EC2 instance(s) still running"
        ((issues++))
    else
        log_success "No EC2 instances found"
    fi

    # Check LoadBalancers
    local lbs=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query 'LoadBalancers' --output text 2>/dev/null | wc -l)
    if [ "$lbs" -gt 0 ]; then
        log_warning "Found $lbs LoadBalancer(s) still active"
        ((issues++))
    else
        log_success "No LoadBalancers found"
    fi

    # Check NAT Gateways
    local nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
        --filter "Name=state,Values=available" \
        --query 'NatGateways' --output text 2>/dev/null | wc -l)
    if [ "$nat_gws" -gt 0 ]; then
        log_warning "Found $nat_gws NAT Gateway(s) still available"
        ((issues++))
    else
        log_success "No NAT Gateways found"
    fi

    # Check RDS instances
    local rds_instances=$(aws rds describe-db-instances --region "$REGION" \
        --query 'DBInstances' --output text 2>/dev/null | wc -l)
    if [ "$rds_instances" -gt 0 ]; then
        log_warning "Found $rds_instances RDS instance(s) still running"
        ((issues++))
    else
        log_success "No RDS instances found"
    fi

    echo ""
    if [ $issues -eq 0 ]; then
        log_success "✓ All cost-generating resources have been cleaned up!"
    else
        log_warning "⚠ Found $issues issue(s). Please check AWS console for remaining resources."
    fi
}

# Main function
main() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  InfraForge Full Cleanup Script${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""

    log_warning "This script will destroy ALL infrastructure!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ ! "${confirm}" =~ ^(yes|y|Y)$ ]]; then
        echo "Aborted"
        exit 0
    fi

    echo ""
    check_prerequisites

    echo ""
    cleanup_k8s_namespaces

    echo ""
    cleanup_k8s_loadbalancers

    echo ""
    run_terraform_destroy

    echo ""
    wait_for_eks_deletion

    echo ""
    cleanup_aws_resources

    echo ""
    verify_cleanup

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Cleanup Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
}

# Run main function
main
