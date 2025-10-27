# GitOps Workflow Guide

Complete guide to the GitOps workflow for InfraForge platform.

## Table of Contents

1. [Overview](#overview)
2. [Complete Workflow](#complete-workflow)
3. [Developer Workflow](#developer-workflow)
4. [CI/CD Pipeline](#cicd-pipeline)
5. [ArgoCD Deployment](#argocd-deployment)
6. [Troubleshooting](#troubleshooting)

## Overview

### What is GitOps?

**GitOps** is a way to manage infrastructure and applications where:
- **Git is the single source of truth**
- **All changes go through Git**
- **Automated processes sync cluster state with Git**

### Why GitOps?

✅ **Version Control** - Every change tracked in Git
✅ **Audit Trail** - Who changed what, when
✅ **Rollback** - Easy rollback with `git revert`
✅ **Collaboration** - Team reviews via Pull Requests
✅ **Automation** - No manual kubectl commands
✅ **Security** - No direct cluster access needed

## Complete Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Developer writes code                                       │
│     - Implement feature                                         │
│     - Write tests                                               │
│     - Commit & push to feature branch                          │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. CI/CD Pipeline (GitHub Actions)                             │
│     a) Build Docker image                                       │
│     b) Run tests                                                │
│     c) Security scan (Trivy)                                    │
│     d) Push to GHCR                                            │
│     e) Tag with semantic version                               │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Update GitOps Repo                                          │
│     - Clone infraforge-gitops                                   │
│     - Update kustomization.yaml with new image tag            │
│     - Commit & push to main                                    │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. ArgoCD Detects Change                                       │
│     - Polls Git every 3 minutes                                 │
│     - Detects new image tag                                     │
│     - Compares with cluster state                              │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. ArgoCD Auto-Syncs                                           │
│     - Applies Kubernetes manifests                              │
│     - Performs rolling update                                   │
│     - Monitors health checks                                    │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. Verification                                                 │
│     - Check pods are running                                    │
│     - View logs in Grafana                                      │
│     - Monitor metrics in Prometheus                             │
│     - View traces in Jaeger                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Developer Workflow

### Scenario: Adding New Feature

#### Step 1: Create Application (First Time)

```bash
# Create new application from template
make create-app

# Or manually:
./scripts/create-app.sh my-service prod
```

This creates:
```
applications/my-service/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml  # ← Image version managed here
└── overlays/
    ├── dev/
    └── prod/

applications/argocd-apps/
└── my-service-prod.yaml  # ← ArgoCD Application definition
```

#### Step 2: Develop Feature

In your application repository (e.g., `my-service` repo):

```bash
# 1. Create feature branch
git checkout -b feature/add-caching

# 2. Implement feature
vim src/cache.go

# 3. Update Dockerfile if needed
vim Dockerfile

# 4. Write tests
vim src/cache_test.go

# 5. Commit changes
git add .
git commit -m "feat: Add Redis caching"

# 6. Push to GitHub
git push origin feature/add-caching
```

#### Step 3: Create Pull Request

1. Open PR on GitHub
2. CI/CD runs automatically:
   - Builds Docker image
   - Runs tests
   - Security scan
   - Pushes to GHCR with tag `dev-abc1234`

#### Step 4: Merge & Release

```bash
# After PR is approved and merged to main:

# Create release tag (triggers production build)
git tag v1.2.3
git push origin v1.2.3
```

#### Step 5: CI/CD Updates GitOps

CI/CD automatically:
1. Builds production image: `ghcr.io/nimbusproch/my-service:v1.2.3`
2. Clones `infraforge-gitops` repo
3. Updates `applications/my-service/base/kustomization.yaml`:
   ```yaml
   images:
     - name: ghcr.io/nimbusproch/my-service
       newTag: v1.2.3  # ← Updated by CI/CD
   ```
4. Commits & pushes to main

#### Step 6: ArgoCD Deploys

Within 3 minutes, ArgoCD:
1. Detects Git change
2. Syncs to cluster
3. Performs rolling update
4. Monitors health

#### Step 7: Verify Deployment

```bash
# Check application status
make app-status
# Enter: my-service-prod

# View logs
make app-logs
# Enter: my-service, production

# Access Grafana for metrics
make grafana-ui

# View traces in Jaeger
kubectl port-forward -n opentelemetry svc/jaeger-query 16686:16686
```

## CI/CD Pipeline

### GitHub Actions Workflow

Located in application repo: `.github/workflows/deploy.yaml`

```yaml
name: Deploy

on:
  push:
    branches: [main]
    tags: ['v*.*.*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # 1. Determine version
      - name: Get version
        id: version
        run: |
          if [[ "${{ github.ref }}" == refs/tags/* ]]; then
            VERSION=${GITHUB_REF#refs/tags/}
          else
            VERSION=dev-${{ github.sha::7 }}
          fi
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      # 2. Build & push image
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ steps.version.outputs.version }}

      # 3. Update GitOps repo
      - name: Update GitOps
        run: |
          git clone https://github.com/NimbusProTch/infraforge-gitops.git
          cd infraforge-gitops/applications/${{ github.event.repository.name }}/base
          kustomize edit set image ghcr.io/${{ github.repository }}:${{ steps.version.outputs.version }}
          git commit -am "Update to ${{ steps.version.outputs.version }}"
          git push
```

### Semantic Versioning

Use semantic versioning for releases:

```bash
# Bug fix (1.0.0 → 1.0.1)
git tag v1.0.1

# New feature (1.0.1 → 1.1.0)
git tag v1.1.0

# Breaking change (1.1.0 → 2.0.0)
git tag v2.0.0

# Push tag
git push origin v2.0.0
```

## ArgoCD Deployment

### Application States

| State | Meaning | Action Needed |
|-------|---------|---------------|
| ✅ **Synced** | Cluster matches Git | None |
| ⚠️ **OutOfSync** | Cluster differs from Git | Auto-sync or manual sync |
| 🔄 **Progressing** | Deployment in progress | Wait |
| ❌ **Degraded** | Health check failing | Investigate logs |
| ⏸️ **Suspended** | Auto-sync disabled | Manual intervention |

### Manual Operations

```bash
# View all applications
kubectl get applications -n argocd

# Describe specific application
kubectl describe application my-service-prod -n argocd

# Force sync (if auto-sync disabled)
kubectl patch application my-service-prod -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'

# Rollback to previous version
# 1. Find previous image tag in Git history
git log -- applications/my-service/base/kustomization.yaml

# 2. Revert commit
git revert <commit-hash>

# 3. Push
git push

# 4. ArgoCD will automatically rollback
```

### Access ArgoCD UI

```bash
# Port-forward ArgoCD
make argocd-ui

# Opens at: http://localhost:8080

# Get admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

In ArgoCD UI you can:
- ✅ View application topology
- ✅ See sync status
- ✅ View logs and events
- ✅ Manually sync/rollback
- ✅ Compare Git vs Cluster state

## Environment Management

### Development Environment

**Characteristics:**
- Namespace: `dev`
- Lower resources
- Debug logging enabled
- Auto-sync enabled
- Fast iteration

**Deploy to Dev:**
```bash
# 1. Merge to main (no tag)
git push origin main

# 2. CI/CD builds dev image
# Image: ghcr.io/org/app:dev-abc1234

# 3. ArgoCD syncs to dev namespace
kubectl get pods -n dev
```

### Production Environment

**Characteristics:**
- Namespace: `production`
- Higher resources
- Production logging
- HPA enabled
- Auto-sync with approval

**Deploy to Prod:**
```bash
# 1. Create release tag
git tag v1.0.0
git push origin v1.0.0

# 2. CI/CD builds prod image
# Image: ghcr.io/org/app:v1.0.0

# 3. ArgoCD syncs to production
kubectl get pods -n production
```

### Promotion Strategy

**Option 1: Tag-based** (Recommended)
```bash
# Dev: Any push to main
# Prod: Only tags matching v*.*.*
```

**Option 2: Branch-based**
```bash
# Dev: develop branch
# Staging: staging branch
# Prod: main branch
```

**Option 3: GitOps Promotion**
```bash
# 1. Deploy to dev
# 2. Test in dev
# 3. Copy kustomization from dev to prod overlay
# 4. Commit & push
```

## Troubleshooting

### Image Not Updating

**Problem:** New image pushed but pod still running old version

**Solution:**
```bash
# 1. Check kustomization.yaml
cat applications/my-app/base/kustomization.yaml
# Verify newTag is updated

# 2. Check ArgoCD sync status
kubectl get application my-app-prod -n argocd

# 3. Force sync
kubectl patch application my-app-prod -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# 4. Check if image exists
docker pull ghcr.io/nimbusproch/my-app:v1.2.3
```

### Pod CrashLoopBackOff

**Problem:** Pod keeps restarting

**Solution:**
```bash
# 1. Check pod status
kubectl get pods -n production -l app=my-app

# 2. View logs
kubectl logs -n production -l app=my-app --tail=100

# 3. Describe pod
kubectl describe pod -n production -l app=my-app

# Common causes:
# - Missing environment variables
# - Database connection issues
# - Health check failures
# - Resource limits too low
```

### ArgoCD Application Stuck "Progressing"

**Problem:** Deployment never completes

**Solution:**
```bash
# 1. Check deployment status
kubectl rollout status deployment my-app -n production

# 2. Check events
kubectl get events -n production --sort-by='.lastTimestamp'

# 3. Check pod issues
kubectl describe pod -n production -l app=my-app

# 4. If stuck, rollback
git revert <commit-hash>
git push
```

### CI/CD Failed to Update GitOps

**Problem:** CI/CD can't push to GitOps repo

**Solution:**
```bash
# 1. Check GitHub PAT (Personal Access Token)
# Go to Settings → Secrets → GITOPS_PAT

# 2. Ensure PAT has repo write permissions

# 3. Manually update if needed
cd infraforge-gitops
cd applications/my-app/base
kustomize edit set image ghcr.io/org/my-app:v1.2.3
git commit -am "Update my-app to v1.2.3"
git push
```

## Best Practices

### 1. Never `kubectl apply` Directly
❌ Bad:
```bash
kubectl apply -f deployment.yaml
```

✅ Good:
```bash
# Commit to Git, let ArgoCD handle it
git add deployment.yaml
git commit -m "Update deployment"
git push
```

### 2. Use Semantic Versioning
❌ Bad:
```bash
docker push my-app:latest
```

✅ Good:
```bash
docker push my-app:v1.2.3
```

### 3. Test in Dev First
```bash
# 1. Deploy to dev
# 2. Test thoroughly
# 3. Then promote to prod
```

### 4. Small, Incremental Changes
❌ Bad: Deploy 10 features at once

✅ Good: Deploy features one by one

### 5. Monitor After Deployment
```bash
# Always check after deployment:
make app-status
make app-logs
make grafana-ui
```

## Next Steps

1. ✅ Read [Quick Start Guide](QUICK_START.md)
2. ✅ Review [Application Structure](../applications/README.md)
3. ✅ Setup [Monitoring](MONITORING.md)
4. ✅ Configure [Atlantis](ATLANTIS.md) (optional, for teams)
5. ✅ Review [Example Application](../applications/example-api/README.md)

## Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [GitOps Principles](https://opengitops.dev/)
- [Semantic Versioning](https://semver.org/)
