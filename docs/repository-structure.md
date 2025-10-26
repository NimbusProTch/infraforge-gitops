# Repository Structure Guide

InfraForge GitOps Platform'un repository yapısı ve kullanım kılavuzu.

## 🏗️ Repository Organizasyonu

### Multi-Repo Yaklaşımı (Önerilen)

```
┌─────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE LAYER                      │
│  github.com/NimbusProTch/infraforge-gitops                  │
│  ├── terraform/         # Infrastructure as Code            │
│  ├── argocd/           # GitOps configs                     │
│  ├── apps/             # App deployment configs             │
│  └── config/apps.yaml  # Single source of truth             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                         │
│                                                              │
│  github.com/NimbusProTch/smk                                │
│  ├── src/              # App code                           │
│  ├── Dockerfile        # Container build                    │
│  └── .github/          # CI/CD pipeline                     │
│                                                              │
│  github.com/NimbusProTch/sonsuzenerji                       │
│  ├── src/              # App code                           │
│  ├── Dockerfile        # Container build                    │
│  └── .github/          # CI/CD pipeline                     │
│                                                              │
│  github.com/NimbusProTch/transferhub                        │
│  └── ...                                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 GitOps Repository Structure

```
infraforge-gitops/
│
├── config/
│   └── apps.yaml                    # ⭐ MASTER CONFIG
│       ├── Infrastructure settings  # (RDS, ElastiCache, etc.)
│       ├── App definitions          # (enabled/disabled)
│       └── Global settings          # (domain, environment)
│
├── terraform/                       # Infrastructure as Code
│   ├── vpc.tf                       # Networking
│   ├── eks.tf                       # Kubernetes cluster
│   ├── rds.tf                       # Databases
│   ├── elasticache.tf               # Cache (optional)
│   ├── monitoring-addons.tf         # Prometheus, Grafana
│   ├── logging-addons.tf            # Loki, OpenTelemetry
│   ├── backup-addons.tf             # Velero
│   └── internal-operators.tf        # CloudNativePG, Redis, etc.
│
├── apps/                            # ⭐ APP GITOPS CONFIGS
│   ├── smk/
│   │   ├── values.yaml              # Helm values (deployment)
│   │   ├── secrets.yaml             # ExternalSecret CRDs
│   │   └── configmap.yaml           # Non-sensitive configs
│   ├── sonsuzenerji/
│   │   ├── values.yaml
│   │   ├── secrets.yaml
│   │   └── configmap.yaml
│   └── transferhub/
│       └── ...
│
├── argocd/
│   ├── applicationset.yaml          # Dynamic app generator
│   ├── argocd-values.yaml           # ArgoCD config
│   └── root-app.yaml                # Root application
│
├── helm/
│   └── infraforge-app/              # Base Helm chart
│       ├── Chart.yaml
│       ├── templates/               # K8s resource templates
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   └── hpa.yaml
│       └── values.yaml              # Default values
│
├── scripts/
│   ├── setup.sh                     # Initial setup
│   ├── deploy.sh                    # Deploy infrastructure
│   └── cleanup.sh                   # Destroy everything
│
├── .github/
│   └── workflows/
│       ├── app-ci-template.yml      # Template for app repos
│       └── README.md                # CI/CD setup guide
│
└── docs/
    ├── infrastructure-components.md # Component docs
    ├── repository-structure.md      # This file
    └── troubleshooting.md           # Debug guide
```

---

## 📦 App Repository Structure

```
smk/  (App repository)
│
├── src/                             # Application code
│   ├── index.js
│   ├── routes/
│   ├── controllers/
│   └── models/
│
├── tests/                           # Unit & integration tests
│   └── ...
│
├── Dockerfile                       # Container build
│
├── package.json                     # Dependencies
│
├── .dockerignore                    # Docker ignore
│
└── .github/
    └── workflows/
        └── ci-cd.yml                # ⭐ CI/CD PIPELINE
            ├── Build Docker image
            ├── Push to ECR
            └── Update GitOps repo
```

---

## 🔄 Complete Workflow

### 1️⃣ Infrastructure Setup (One-time)

```bash
cd infraforge-gitops

# 1. Configure apps
vim config/apps.yaml

# 2. Deploy infrastructure
cd terraform
tofu init
tofu apply

# ✅ Created:
# - VPC, EKS, RDS
# - ArgoCD, Prometheus, Loki
# - Namespaces, Secrets, ConfigMaps
```

### 2️⃣ App Development (Daily)

```bash
cd smk  # App repository

# 1. Code changes
vim src/index.js
git add .
git commit -m "feat: new feature"

# 2. Push to main
git push origin main

# ↓ CI/CD AUTOMATIC STEPS:
# ├── Build: Docker image
# ├── Test: Run tests (if configured)
# ├── Push: ECR push (smk:main-a1b2c3d4)
# └── Update: GitOps repo apps/smk/values.yaml
#
# ↓ ARGOCD AUTOMATIC STEPS:
# ├── Detect: Git change
# ├── Sync: Pull new image tag
# └── Deploy: Kubernetes update
#
# ✅ DEPLOYED in ~2 minutes!
```

### 3️⃣ Configuration Changes (As needed)

```bash
cd infraforge-gitops

# Change deployment config
vim apps/smk/values.yaml
# - Increase replicas
# - Update resources
# - Change environment vars

git commit -m "chore(smk): scale to 5 replicas"
git push origin main

# ↓ ArgoCD detects change
# ↓ Applies to cluster
# ✅ Updated!
```

---

## 🎯 Separation of Concerns

### What Goes Where?

| Type | Location | Who Manages | Example |
|------|----------|-------------|---------|
| **App Code** | App Repo (`smk/src/`) | Developers | Business logic, API routes |
| **Container Build** | App Repo (`smk/Dockerfile`) | Developers | Image definition |
| **Deployment Config** | GitOps Repo (`apps/smk/values.yaml`) | DevOps | Replicas, resources |
| **Secrets** | AWS Secrets Manager | DevOps | DB passwords, API keys |
| **Secret References** | GitOps Repo (`apps/smk/secrets.yaml`) | DevOps | ExternalSecret CRDs |
| **Infrastructure** | GitOps Repo (`terraform/`) | DevOps | VPC, EKS, RDS |
| **Master Config** | GitOps Repo (`config/apps.yaml`) | DevOps | App enable/disable |

---

## 📝 File Responsibilities

### `config/apps.yaml` (Master Config)
```yaml
# Defines:
# - Which apps are enabled
# - Infrastructure components
# - Global settings
```
**Updated by:** DevOps team
**Frequency:** Rarely (new apps, infra changes)

### `apps/{name}/values.yaml` (Deployment Config)
```yaml
# Defines:
# - Docker image tag (updated by CI/CD)
# - Replicas, resources
# - Ingress rules
# - Health checks
```
**Updated by:** CI/CD (image tag) + DevOps (config)
**Frequency:** Every deployment (tag), occasional (config)

### `apps/{name}/secrets.yaml` (Secret References)
```yaml
# Defines:
# - References to AWS Secrets Manager
# - Which secrets to sync
```
**Updated by:** DevOps team
**Frequency:** Rarely (new secrets)

### `apps/{name}/configmap.yaml` (App Config)
```yaml
# Defines:
# - Non-sensitive configs
# - Feature flags
# - Environment variables
```
**Updated by:** DevOps or Developers
**Frequency:** As needed

---

## 🚀 Adding a New App

### Step 1: Create App Repository
```bash
# Create new repo
gh repo create smk --private
cd smk

# Add Dockerfile, src/, etc.
# Copy CI/CD workflow
cp ../infraforge-gitops/.github/workflows/app-ci-template.yml \
   .github/workflows/ci-cd.yml

# Customize workflow
vim .github/workflows/ci-cd.yml
# - APP_NAME: smk
# - HELM_VALUES_PATH: apps/smk/values.yaml
```

### Step 2: Add to GitOps Repo
```bash
cd infraforge-gitops

# 1. Create app directory
mkdir -p apps/smk

# 2. Create values.yaml
cp apps/sonsuzenerji/values.yaml apps/smk/values.yaml
vim apps/smk/values.yaml  # Customize

# 3. Create secrets.yaml
cp apps/sonsuzenerji/secrets.yaml apps/smk/secrets.yaml
vim apps/smk/secrets.yaml  # Update secret paths

# 4. Create configmap.yaml
vim apps/smk/configmap.yaml  # Add configs

# 5. Enable in master config
vim config/apps.yaml
```
```yaml
applications:
  smk:
    enabled: true
    namespace: smk
    subdomain: smk
    # ... other settings
```

### Step 3: Deploy Infrastructure
```bash
cd terraform
tofu apply  # Creates namespace, configmap, secrets
```

### Step 4: Push App Code
```bash
cd ../smk  # App repo
git push origin main

# ✅ CI/CD builds and deploys!
```

---

## 🔐 Secret Management Flow

### 1. Create Secret in AWS
```bash
aws secretsmanager create-secret \
  --name prod/smk/db-password \
  --secret-string "MySecurePassword" \
  --region eu-west-1
```

### 2. Reference in GitOps
```yaml
# apps/smk/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: smk-secrets
spec:
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: prod/smk/db-password
```

### 3. Use in App
```yaml
# apps/smk/values.yaml
envFrom:
  - secretRef:
      name: smk-secrets  # Created by ExternalSecret
```

### 4. App Reads Secret
```javascript
// App code
const dbPassword = process.env.DB_PASSWORD;
```

---

## 📊 Repository Comparison

### ✅ Multi-Repo (Current Setup)

**Pros:**
- ✅ Clear separation (code vs config)
- ✅ Independent CI/CD per app
- ✅ Fast git operations
- ✅ Team ownership per repo
- ✅ Industry best practice

**Cons:**
- ❌ More repos to manage
- ❌ Need token for cross-repo updates

### ❌ Monorepo (NOT Recommended)

**Pros:**
- ✅ Single repo
- ✅ Easier initial setup

**Cons:**
- ❌ Mixed code and config
- ❌ Complex CI/CD (path filters)
- ❌ Slow git clone
- ❌ Messy git history
- ❌ Hard to scale

---

## 📚 Related Docs

- [Infrastructure Components](./infrastructure-components.md)
- [GitHub Actions Setup](../.github/workflows/README.md)
- [Apps Directory Guide](../apps/README.md)
- [Troubleshooting](./troubleshooting.md)

---

## 💡 Best Practices

1. **Keep app code separate** - Never mix in GitOps repo
2. **Use External Secrets** - No secrets in Git
3. **Single source of truth** - `config/apps.yaml` for master config
4. **Per-app values** - `apps/{name}/values.yaml` for deployment
5. **Automate everything** - CI/CD for image updates
6. **Monitor everything** - Prometheus + Grafana
7. **Test before merge** - Use PR environments
8. **Document changes** - Clear commit messages

---

**Last Updated:** 2025-10-26
**Maintainer:** DevOps Team
