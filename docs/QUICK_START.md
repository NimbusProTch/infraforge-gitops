# InfraForge GitOps - Quick Start Guide

## 🚀 Get Started in 3 Commands

```bash
# 1. Bootstrap (creates S3 bucket + DynamoDB table)
make bootstrap

# 2. Initialize Terraform
make init

# 3. Deploy Infrastructure
make apply
```

That's it! 🎉

## Prerequisites

- [x] AWS CLI configured (`aws configure`)
- [x] OpenTofu installed (`brew install opentofu`)
- [x] kubectl installed (`brew install kubectl`)
- [x] Valid AWS credentials with admin permissions

## Step-by-Step Guide

### 1️⃣ Bootstrap Backend

This creates the S3 bucket and DynamoDB table for Terraform state:

```bash
make bootstrap
```

**Output:**
```
============================================
  Terraform Backend Bootstrap
============================================

[INFO] Checking prerequisites...
[SUCCESS] AWS account: 715841344657
[INFO] Creating S3 bucket: infraforge-terraform-state...
[SUCCESS] S3 bucket created
[SUCCESS] Versioning enabled
[SUCCESS] Encryption enabled
[SUCCESS] Public access blocked
[INFO] Creating DynamoDB table: infraforge-terraform-locks...
[SUCCESS] DynamoDB table created
[SUCCESS] Backend is ready!
```

### 2️⃣ Initialize Terraform

```bash
make init
```

This runs `terraform init` and downloads providers.

### 3️⃣ Plan Changes

See what will be created:

```bash
make plan
```

**Expected resources:**
- ✅ VPC with 3 public + 3 private subnets
- ✅ EKS cluster with managed node group
- ✅ NAT Gateways for private subnets
- ✅ ALB ingress controller
- ✅ External DNS
- ✅ cert-manager
- ✅ ArgoCD
- ✅ Prometheus + Grafana
- ✅ CloudNativePG operator
- ✅ Strimzi Kafka operator
- ✅ OpenTelemetry operator

### 4️⃣ Apply Changes

Deploy the infrastructure:

```bash
make apply
```

This will:
1. Show you the plan again
2. Ask for confirmation
3. Apply all changes (~15-20 minutes)

### 5️⃣ Configure kubectl

Once apply completes:

```bash
make kubeconfig
```

This runs: `aws eks update-kubeconfig --region eu-west-1 --name infraforge-eks`

### 6️⃣ Check Cluster Status

```bash
make k8s-status
```

You should see:
- ✅ Nodes: Ready
- ✅ Namespaces: argocd, monitoring, opentelemetry, etc.
- ✅ Pods: Running

### 7️⃣ Access UIs

**ArgoCD UI:**
```bash
make argocd-ui
# Opens at http://localhost:8080
# Username: admin
# Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

**Grafana UI:**
```bash
make grafana-ui
# Opens at http://localhost:3000
# Username: admin
# Password: From AWS Secrets Manager
```

**Prometheus UI:**
```bash
make prometheus-ui
# Opens at http://localhost:9090
```

## What Gets Created?

### Infrastructure (AWS)

| Resource | Count | Cost/Month (approx) |
|----------|-------|---------------------|
| EKS Cluster | 1 | $73 |
| EKS Nodes (t3.medium) | 3 | ~$90 |
| NAT Gateways | 3 | ~$100 |
| ALB | 2-3 | ~$45 |
| Total | - | **~$308/month** |

### Kubernetes Components

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| ArgoCD | GitOps CD | argocd |
| Prometheus | Metrics | monitoring |
| Grafana | Dashboards | monitoring |
| Alertmanager | Alerts | monitoring |
| CloudNativePG | PostgreSQL operator | cnpg-system |
| Strimzi Kafka | Kafka operator | kafka |
| OpenTelemetry | Observability | opentelemetry |
| Jaeger | Tracing | opentelemetry |
| cert-manager | TLS certs | cert-manager |
| External DNS | DNS automation | kube-system |
| AWS LB Controller | Load balancers | kube-system |

## Configuration

All configuration is in **`config/apps.yaml`** - single source of truth!

### Enable/Disable Applications

```yaml
applications:
  otel-demo:
    enabled: true  # ← Change to false to disable
```

### Enable/Disable Operators

```yaml
infrastructure:
  internal_operators:
    cloudnative_pg:
      enabled: true  # ← PostgreSQL operator
    redis_operator:
      enabled: false # ← Disabled
```

After changing config:

```bash
make plan   # See changes
make apply  # Apply changes
```

## Common Commands

```bash
# Infrastructure
make quickstart     # Bootstrap + init + validate (first time)
make deploy         # Full deployment
make plan           # Preview changes
make apply          # Apply changes
make destroy        # Destroy everything (interactive)
make outputs        # Show outputs (URLs, endpoints)

# Kubernetes
make kubeconfig     # Update kubeconfig
make k8s-status     # Cluster status
make argocd-ui      # ArgoCD UI (port-forward)
make grafana-ui     # Grafana UI (port-forward)

# Maintenance
make validate       # Validate config
make fmt            # Format Terraform files
make check          # Run all checks
make clean          # Clean cache files

# Cleanup
make cleanup-ns     # Fix stuck namespaces
make full-cleanup   # Complete destroy (includes VPC cleanup)
```

## Troubleshooting

### "S3 bucket does not exist"

**Solution:** Run `make bootstrap` first!

```bash
make bootstrap
make init
```

### Namespace stuck in "Terminating"

**Solution:**

```bash
make cleanup-ns monitoring
# or
./scripts/cleanup-namespaces.sh monitoring
```

### VPC won't delete

**Cause:** EKS not fully deleted yet

**Solution:**

```bash
make full-cleanup  # This waits for EKS deletion
```

### Plan fails with state lock error

**Solution:**

```bash
cd terraform
tofu force-unlock <lock-id>
```

## Cost Optimization

### Development Environment

For testing, reduce costs:

```yaml
# config/apps.yaml
infrastructure:
  rds:
    mysql:
      enabled: false  # Use CloudNativePG instead
  elasticache:
    enabled: false    # Not needed for dev
```

**Savings:** ~$100/month

### Production Optimizations

1. **Reserved Instances** for EKS nodes (~40% savings)
2. **Spot Instances** for non-critical workloads (~70% savings)
3. **Single NAT Gateway** (saves ~$66/month, but less HA)

## Next Steps

1. ✅ Deploy infrastructure
2. ✅ Configure kubectl
3. ✅ Access ArgoCD UI
4. 📝 Read [Atlantis Guide](ATLANTIS.md) for PR-based workflow
5. 📝 Configure applications in `config/apps.yaml`
6. 📝 Add your applications to `applications/` directory
7. 📝 Set up CI/CD with Atlantis or GitHub Actions

## Daily Workflow

### Option A: Direct Apply (Quick)

```bash
# 1. Make changes
vim config/apps.yaml

# 2. Plan
make plan

# 3. Apply
make apply
```

### Option B: PR-based (Team)

```bash
# 1. Create branch
git checkout -b feature/enable-redis

# 2. Make changes
vim config/apps.yaml

# 3. Commit and push
git add config/apps.yaml
git commit -m "Enable Redis operator"
git push

# 4. Open PR
# → Atlantis auto-plans
# → Team reviews
# → Comment "atlantis apply"
# → Merge PR
```

## Support

- 📖 [Full Documentation](../README.md)
- 🤝 [Atlantis Guide](ATLANTIS.md)
- 🛠️ [Scripts README](../scripts/README.md)
- ⚙️ [Configuration Guide](../config/apps.yaml)

## Tips

💡 **Use make commands** - They're safer and more convenient than raw terraform commands

💡 **Always plan before apply** - No surprises!

💡 **Enable apps gradually** - Start with monitoring, then add apps one by one

💡 **Use Atlantis for teams** - PR-based workflow is much safer

💡 **Monitor costs** - Run `make cost` (requires infracost)

Happy deploying! 🚀
