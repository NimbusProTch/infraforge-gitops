#!/bin/bash
# ============================================================================
# Create New Application Script
# ============================================================================
# Quickly scaffold a new application from template
#
# Usage: ./create-app.sh <app-name> [environment]
# Example: ./create-app.sh my-api prod
# ============================================================================

set -e

# Colors
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ -z "$1" ]; then
    log_error "Application name is required"
    echo ""
    echo "Usage: $0 <app-name> [environment]"
    echo ""
    echo "Examples:"
    echo "  $0 my-api prod        # Create production app"
    echo "  $0 my-api dev         # Create development app"
    echo "  $0 my-api             # Interactive mode"
    exit 1
fi

APP_NAME=$1
ENVIRONMENT=${2:-}
TEMPLATE_DIR="applications/_template"
APP_DIR="applications/$APP_NAME"
ARGOCD_DIR="applications/argocd-apps"

# Check if template exists
if [ ! -d "$TEMPLATE_DIR" ]; then
    log_error "Template directory not found: $TEMPLATE_DIR"
    exit 1
fi

# Check if app already exists
if [ -d "$APP_DIR" ]; then
    log_error "Application already exists: $APP_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Create New Application${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Interactive mode if environment not specified
if [ -z "$ENVIRONMENT" ]; then
    echo "Available environments:"
    echo "  1) dev (Development)"
    echo "  2) prod (Production)"
    echo "  3) both (Create both)"
    echo ""
    read -p "Select environment (1-3): " env_choice

    case $env_choice in
        1) ENVIRONMENT="dev" ;;
        2) ENVIRONMENT="prod" ;;
        3) ENVIRONMENT="both" ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
fi

log_info "Creating application: $APP_NAME"
log_info "Environment: $ENVIRONMENT"

# Copy template
log_info "Copying template..."
cp -r "$TEMPLATE_DIR" "$APP_DIR"
log_success "Template copied to $APP_DIR"

# Replace placeholders in all files
log_info "Updating placeholders..."
find "$APP_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i '' "s/app-name/$APP_NAME/g" {} +
log_success "Placeholders updated"

# Create ArgoCD Application manifests
log_info "Creating ArgoCD Application manifests..."
mkdir -p "$ARGOCD_DIR"

create_argocd_app() {
    local env=$1
    local namespace=$env
    if [ "$env" = "prod" ]; then
        namespace="production"
    fi

    cat > "$ARGOCD_DIR/$APP_NAME-$env.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME-$env
  namespace: argocd
  annotations:
    # ArgoCD Image Updater
    argocd-image-updater.argoproj.io/image-list: $APP_NAME=ghcr.io/nimbusproch/$APP_NAME
    argocd-image-updater.argoproj.io/$APP_NAME.update-strategy: semver
    argocd-image-updater.argoproj.io/$APP_NAME.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    argocd-image-updater.argoproj.io/$APP_NAME.kustomize.image-name: ghcr.io/nimbusproch/$APP_NAME
    argocd-image-updater.argoproj.io/write-back-method: git
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/NimbusProTch/infraforge-gitops.git
    targetRevision: main
    path: applications/$APP_NAME/overlays/$env
    kustomize:
      version: v5.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: $namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
EOF

    log_success "Created $ARGOCD_DIR/$APP_NAME-$env.yaml"
}

# Create ArgoCD manifests based on environment choice
if [ "$ENVIRONMENT" = "both" ]; then
    create_argocd_app "dev"
    create_argocd_app "prod"
else
    create_argocd_app "$ENVIRONMENT"
fi

# Remove template argocd-application.yaml (it was just a reference)
rm -f "$APP_DIR/argocd-application.yaml"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Application Created Successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "📁 Application directory: $APP_DIR"
echo "📝 ArgoCD manifests: $ARGOCD_DIR/"
echo ""
echo "Next steps:"
echo ""
echo "1. Customize your application:"
echo "   cd $APP_DIR/base"
echo "   vim deployment.yaml"
echo ""
echo "2. Update image repository:"
echo "   sed -i '' 's|ghcr.io/nimbusproch|ghcr.io/your-org|g' $APP_DIR/base/kustomization.yaml"
echo ""
echo "3. Deploy to ArgoCD:"
if [ "$ENVIRONMENT" = "both" ]; then
    echo "   kubectl apply -f $ARGOCD_DIR/$APP_NAME-dev.yaml"
    echo "   kubectl apply -f $ARGOCD_DIR/$APP_NAME-prod.yaml"
else
    echo "   kubectl apply -f $ARGOCD_DIR/$APP_NAME-$ENVIRONMENT.yaml"
fi
echo ""
echo "4. Check ArgoCD:"
echo "   kubectl get application -n argocd | grep $APP_NAME"
echo ""
echo "5. Access ArgoCD UI:"
echo "   make argocd-ui"
echo ""

log_success "Done! 🎉"
