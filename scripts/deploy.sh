#!/bin/bash
set -e

echo "🚀 InfraForge Deployment Script"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to terraform directory
cd "$(dirname "$0")/../terraform"

# Check if tofu is available
if ! command -v tofu >/dev/null 2>&1; then
  echo -e "${RED}❌ OpenTofu not found${NC}"
  echo "Install from: https://opentofu.org/docs/intro/install/"
  exit 1
fi

TF_CMD="tofu"
echo "Using: $TF_CMD"
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
  echo -e "${RED}❌ terraform.tfvars not found${NC}"
  echo "Please copy terraform.tfvars.example to terraform.tfvars and update with your values"
  exit 1
fi

# Run plan
echo "📋 Running $TF_CMD plan..."
$TF_CMD plan -out=tfplan

echo ""
read -p "Do you want to apply these changes? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo -e "${YELLOW}⚠️  Deployment cancelled${NC}"
  rm -f tfplan
  exit 0
fi

# Apply
echo ""
echo "🚀 Applying infrastructure changes..."
$TF_CMD apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Get kubeconfig:"
echo "   \$($TF_CMD output -raw kubeconfig_command)"
echo ""
echo "2. Verify cluster access:"
echo "   kubectl get nodes"
echo ""
echo "3. Check ArgoCD status:"
echo "   kubectl get pods -n argocd"
echo ""
echo "4. Get ArgoCD admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "5. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Open: https://localhost:8080"
echo ""
echo "6. View infrastructure outputs:"
echo "   $TF_CMD output"
echo ""
