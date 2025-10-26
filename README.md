# InfraForge GitOps Platform

Production-ready Kubernetes platform on AWS with **single-config-file management** and full automation.

## 🎯 Features

- ✅ **Config-Driven**: One file (`config/apps.yaml`) controls everything
- ✅ **Full Automation**: DNS, certificates, namespaces, ECR repos → auto-created
- ✅ **GitOps**: ArgoCD for continuous deployment
- ✅ **AWS Native**: ACM certificates, ALB ingress, Route53 DNS
- ✅ **Auto-Scaling**: Cluster Autoscaler + HPA for pods
- ✅ **Secure**: Private subnets, encrypted RDS, RBAC, security groups
- ✅ **Cost-Optimized**: VPC endpoints, minimal RDS instances, auto-scaling

## 🏗️ Architecture

```
config/apps.yaml (SINGLE SOURCE OF TRUTH)
    ↓
OpenTofu/Terraform:
  ├─ Infrastructure (VPC, EKS, RDS)
  ├─ AWS Controllers (EBS CSI, LB Controller, ExternalDNS)
  ├─ Per-app Resources (ECR, Namespaces, Secrets, DNS)
  └─ ArgoCD + ApplicationSet
    ↓
ArgoCD reads config/apps.yaml
    ↓
Deploys enabled apps automatically
```

**Domain**: `ticarethanem.net`
**AWS Account**: `715841344657`

## 📋 Prerequisites

- AWS CLI configured with credentials
- **OpenTofu >= 1.6** (https://opentofu.org/docs/intro/install/)
- kubectl >= 1.27
- Helm 3.x
- Docker (for building images)
- yq (optional, for parsing YAML)

## 🚀 Quick Start

### 1. Initial Setup

```bash
# Clone repository
git clone https://github.com/gaskin/infraforge-gitops.git
cd infraforge-gitops

# Run setup script (creates S3 bucket, DynamoDB table, initializes OpenTofu)
./scripts/setup.sh
```

### 2. Configure

```bash
# Copy and edit OpenTofu variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars

# Edit application configuration
vim config/apps.yaml
```

### 3. Deploy Infrastructure

```bash
# Deploy all infrastructure
./scripts/deploy.sh

# Or manually:
cd terraform
tofu plan
tofu apply
```

### 4. Build and Push Application Images

```bash
# Build and push all application Docker images to ECR
./scripts/push-images.sh
```

### 5. Access Your Cluster

```bash
# Get kubeconfig
aws eks update-kubeconfig --region eu-west-1 --name infraforge-eks

# Verify cluster access
kubectl get nodes

# Check ArgoCD
kubectl get pods -n argocd

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Access ArgoCD UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

## 📝 Enable/Disable Applications

Simply edit `config/apps.yaml`:

```yaml
applications:
  smk:
    enabled: true  # ← Application is deployed

  transferhub:
    enabled: false  # ← Application is NOT deployed
```

Then apply:

```bash
cd terraform
tofu apply  # Updates namespaces, secrets, DNS, ApplicationSet
# ArgoCD automatically deploys/removes apps within 30 seconds
```

## 🏗️ Adding a New Application

1. **Add to `config/apps.yaml`**:

```yaml
applications:
  myapp:
    enabled: true
    namespace: myapp
    subdomain: myapp
    replicas: 2
    image:
      repository_name: myapp
      tag: latest
    resources:
      cpu: "500m"
      memory: "512Mi"
    ingress:
      enabled: true
    database:
      type: postgresql
      name: myapp_db
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 10
```

2. **Create application directory**:

```bash
mkdir apps/myapp
# Add Dockerfile and source code
```

3. **Apply infrastructure**:

```bash
cd terraform
tofu apply  # Creates ECR repo, namespace, secrets
```

4. **Build and push image**:

```bash
./scripts/push-images.sh
```

5. **Done!** ArgoCD will automatically deploy your app in ~30 seconds.

## 📊 Cost Estimation

### Base Infrastructure (Always Running)
- EKS Control Plane: ~$73/month
- 2x t3.medium nodes: ~$60/month
- NAT Gateways (3): ~$105/month
- RDS MySQL t3.micro: ~$15/month
- RDS PostgreSQL t3.micro: ~$15/month
- **Total**: ~$268/month

### Per Application (When Enabled)
- Additional t3.medium node: ~$30/month (if needed)
- ALB: ~$18/month
- Data transfer: Variable

## 🛠️ Scripts

- `./scripts/setup.sh` - Initial setup (S3, DynamoDB, Helm repos)
- `./scripts/deploy.sh` - Deploy infrastructure with confirmation
- `./scripts/push-images.sh` - Build and push Docker images to ECR
- `./scripts/cleanup.sh` - Destroy all infrastructure

## 📚 Documentation

- [Architecture](docs/architecture.md) - Detailed architecture overview
- [Setup Guide](SETUP_GUIDE.md) - Step-by-step setup instructions
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## 🔧 Project Structure

```
infraforge-gitops/
├── config/
│   └── apps.yaml              # ← Single source of truth
├── terraform/                 # Infrastructure as Code (OpenTofu)
│   ├── main.tf                # Main orchestrator
│   ├── versions.tf            # Provider versions
│   ├── variables.tf           # Input variables
│   ├── locals.tf              # Local values
│   ├── vpc.tf                 # VPC, subnets, NAT
│   ├── eks.tf                 # EKS cluster
│   ├── rds.tf                 # RDS databases
│   ├── ecr.tf                 # ECR repositories
│   ├── addons.tf              # EKS addons
│   ├── route53.tf             # Route53 DNS
│   ├── acm.tf                 # ACM certificates
│   ├── app-resources.tf       # Per-app resources
│   ├── argocd.tf              # ArgoCD installation
│   └── outputs.tf             # Output values
├── argocd/                    # ArgoCD configuration
│   ├── argocd-values.yaml     # ArgoCD Helm values
│   ├── applicationset.yaml    # ApplicationSet manifest
│   └── root-app.yaml          # Root application
├── helm/infraforge-app/       # Generic Helm chart for all apps
├── apps/                      # Application source code + Dockerfiles
├── scripts/                   # Automation scripts
└── docs/                      # Documentation
```

## 🔐 Security Features

- Private subnets for EKS nodes and RDS
- Encrypted RDS storage
- Encrypted OpenTofu state in S3
- TLS termination at ALB with AWS ACM certificates
- Security groups restricting traffic
- RBAC with Kubernetes ServiceAccounts
- VPC endpoints to reduce NAT costs

## 📈 Monitoring

- Metrics Server for resource metrics
- HPA (Horizontal Pod Autoscaler) for pod scaling
- Cluster Autoscaler for node scaling
- CloudWatch logs export from RDS
- Ready for Prometheus/Grafana integration

## 🤝 Contributing

This is a personal project for managing infrastructure. If you find it useful:

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📄 License

MIT License - See LICENSE file for details

## 🆘 Support

For issues and questions:
- GitHub Issues: https://github.com/gaskin/infraforge-gitops/issues
- Documentation: Check `docs/` folder

## 🎯 Roadmap

- [ ] Add Prometheus + Grafana monitoring stack
- [ ] Add Loki for log aggregation
- [ ] Add OpenTelemetry for distributed tracing
- [ ] Add Karpenter for better node auto-scaling
- [ ] Add Velero for backup/restore
- [ ] Add GitHub Actions for CI/CD
- [ ] Add environment separation (dev/staging/prod)

---

Made with ❤️ by Gökhan
