# InfraForge Setup Guide

Complete step-by-step guide to set up InfraForge GitOps platform.

## Prerequisites

### Required Tools

```bash
# AWS CLI
aws --version  # Should be v2.x

# OpenTofu (required)
tofu --version  # >= 1.6.0

# kubectl
kubectl version --client  # >= 1.27

# Helm
helm version  # >= 3.0

# Docker
docker --version  # >= 20.10
```

### Install Missing Tools

**macOS**:
```bash
brew install awscli
brew install opentofu
brew install kubectl
brew install helm
brew install docker
brew install yq  # Optional but recommended
```

**Linux**:
```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# OpenTofu
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | sudo bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Step 1: AWS Configuration

### Configure AWS Credentials

```bash
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: eu-west-1
# Default output format: json
```

### Verify AWS Access

```bash
aws sts get-caller-identity
# Should show your AWS account ID: 715841344657
```

### Verify Route53 Hosted Zone

```bash
aws route53 list-hosted-zones-by-name --dns-name ticarethanem.net
# Should show your hosted zone
```

## Step 2: Clone and Initial Setup

```bash
# Clone repository
git clone https://github.com/gaskin/infraforge-gitops.git
cd infraforge-gitops

# Run setup script
./scripts/setup.sh
```

This script will:
- ✅ Check prerequisites
- ✅ Create S3 bucket for OpenTofu state
- ✅ Create DynamoDB table for state locking
- ✅ Add Helm repositories
- ✅ Initialize OpenTofu

## Step 3: Configure Infrastructure

### Edit OpenTofu Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
```

Update these values:

```hcl
# Database password (IMPORTANT!)
db_password = "YOUR_STRONG_PASSWORD_HERE"  # Change this!

# Git repository URL (if different)
git_repo_url = "https://github.com/gaskin/infraforge-gitops.git"

# Optional: Adjust node configuration
node_desired_size = 2
node_min_size     = 2
node_max_size     = 6
```

### Edit Application Configuration

```bash
vim config/apps.yaml
```

Configure which apps to enable:

```yaml
applications:
  smk:
    enabled: true  # ← Enable this app

  transferhub:
    enabled: false  # ← Disable this app
```

## Step 4: Deploy Infrastructure

### Option A: Using Deploy Script

```bash
./scripts/deploy.sh
```

This will:
1. Run `tofu plan`
2. Ask for confirmation
3. Run `tofu apply`
4. Show next steps

### Option B: Manual Deployment

```bash
cd terraform

# Review what will be created
tofu plan

# Apply (will take 15-20 minutes)
tofu apply

# Get outputs
tofu output
```

### What Gets Created?

**Infrastructure**:
- VPC with 3 public + 3 private subnets
- NAT Gateways (one per AZ)
- VPC Endpoints (S3, ECR)
- EKS Cluster (v1.28)
- Node group with 2 t3.medium nodes
- RDS MySQL (t3.micro, single-AZ)
- RDS PostgreSQL (t3.micro, single-AZ)

**EKS Addons**:
- EBS CSI Driver
- AWS Load Balancer Controller
- ExternalDNS
- Cluster Autoscaler
- Metrics Server

**Per-App Resources** (for enabled apps):
- ECR Repository
- Kubernetes Namespace
- Database Secrets
- ConfigMap

**GitOps**:
- ArgoCD installation
- ArgoCD ApplicationSet

**Security**:
- ACM Wildcard Certificate (`*.ticarethanem.net`)
- Security Groups
- IAM Roles with IRSA

## Step 5: Configure kubectl

```bash
# Get kubeconfig
aws eks update-kubeconfig --region eu-west-1 --name infraforge-eks

# Verify access
kubectl get nodes
# Should show 2 nodes in Ready state

# Check all namespaces
kubectl get namespaces
# Should show: argocd, smk, sonsuzenerji, etc.
```

## Step 6: Verify ArgoCD

```bash
# Check ArgoCD pods
kubectl get pods -n argocd
# All pods should be Running

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
# Save this password!

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser: https://localhost:8080
# Username: admin
# Password: (from above command)
```

## Step 7: Build and Push Application Images

```bash
# Make sure you're in project root
cd /path/to/infraforge-gitops

# Build and push all apps
./scripts/push-images.sh
```

This will:
1. Login to ECR
2. Build Docker images for each app in `apps/` directory
3. Tag images with ECR repository URL
4. Push to ECR

### Verify Images in ECR

```bash
aws ecr describe-repositories --region eu-west-1
# Should show repositories: smk, sonsuzenerji, transferhub, dronesight

# List images
aws ecr list-images --repository-name smk --region eu-west-1
```

## Step 8: Verify Applications

### Check ArgoCD Applications

```bash
# List applications
kubectl get applications -n argocd

# Check specific app
kubectl get application smk -n argocd -o yaml
```

### Access Application

```bash
# Check ingress
kubectl get ingress -n smk

# Check service
kubectl get svc -n smk

# Check pods
kubectl get pods -n smk

# View logs
kubectl logs -n smk -l app.kubernetes.io/name=smk
```

### Verify DNS

```bash
# Check if DNS record was created
nslookup smk.ticarethanem.net

# Or use dig
dig smk.ticarethanem.net
```

## Step 9: Access Applications

Wait 5-10 minutes for DNS propagation, then:

```bash
# Access via HTTPS
curl https://smk.ticarethanem.net/health
# Should return 200 OK

# Access via browser
open https://smk.ticarethanem.net
```

## Troubleshooting

### Issue: OpenTofu fails with "bucket does not exist"

**Solution**: Run setup script again
```bash
./scripts/setup.sh
```

### Issue: kubectl can't connect to cluster

**Solution**: Update kubeconfig
```bash
aws eks update-kubeconfig --region eu-west-1 --name infraforge-eks
```

### Issue: ArgoCD shows "Unknown" status

**Solution**: Check if images exist in ECR
```bash
aws ecr list-images --repository-name smk --region eu-west-1
./scripts/push-images.sh  # If no images found
```

### Issue: DNS not resolving

**Solution**: Check ExternalDNS logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns
```

### Issue: Application pods in CrashLoopBackOff

**Solution**: Check logs and events
```bash
kubectl logs -n smk -l app.kubernetes.io/name=smk
kubectl describe pod -n smk <pod-name>
```

## Next Steps

1. **Configure Monitoring**: Add Prometheus + Grafana
2. **Set up CI/CD**: Add GitHub Actions workflows
3. **Enable Backups**: Configure Velero
4. **Add More Apps**: Follow the "Adding New Application" guide in README

## Useful Commands

```bash
# View all resources
kubectl get all -A

# View infrastructure outputs
cd terraform && tofu output

# Check ArgoCD sync status
kubectl get applications -n argocd

# Force ArgoCD sync
kubectl patch application smk -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Get ACM certificate ARN (for config/apps.yaml)
cd terraform && tofu output acm_certificate_arn

# View RDS endpoints
cd terraform && tofu output rds_mysql_endpoint
cd terraform && tofu output rds_postgresql_endpoint
```

## Cleanup

**⚠️ WARNING**: This will destroy ALL infrastructure and data!

```bash
./scripts/cleanup.sh
# Type 'destroy' to confirm
```

## Getting Help

- Check [Troubleshooting Guide](docs/troubleshooting.md)
- View logs: `kubectl logs -n <namespace> <pod-name>`
- Check ArgoCD UI for app sync status
- Review OpenTofu outputs: `cd terraform && tofu output`

---

For more information, see the main [README.md](README.md)
