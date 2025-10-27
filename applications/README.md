# Applications Directory

This directory contains your application manifests managed by ArgoCD.

## Structure

```
applications/
├── _template/              # Template for new applications
│   ├── base/              # Base Kubernetes manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   └── overlays/          # Environment-specific configs
│       ├── dev/           # Development environment
│       └── prod/          # Production environment
├── example-api/           # Example microservice
└── argocd-apps/           # ArgoCD Application definitions
```

## GitOps Workflow

### 1. Developer Workflow
```bash
# 1. Build & Push Image
docker build -t ghcr.io/nimbusproch/my-app:v1.2.3 .
docker push ghcr.io/nimbusproch/my-app:v1.2.3

# 2. CI/CD Updates Image Tag
# GitHub Actions automatically updates kustomization.yaml
```

### 2. ArgoCD Workflow
```
CI/CD pushes new tag → Image Updater detects → Updates Git → ArgoCD syncs → Deploys
```

## Image Versioning Strategy

### ✅ Recommended: Semantic Versioning
```yaml
image: ghcr.io/nimbusproch/my-app:v1.2.3
# v1.2.3 = MAJOR.MINOR.PATCH
```

### ❌ Avoid: 'latest' Tag
```yaml
image: ghcr.io/nimbusproch/my-app:latest  # ❌ Bad practice
```

**Why?**
- No rollback capability
- Can't track what's deployed
- Cache issues

## ArgoCD Image Updater

Automatically updates image tags when new versions are pushed.

### Annotations Required:
```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: my-app=ghcr.io/nimbusproch/my-app
    argocd-image-updater.argoproj.io/my-app.update-strategy: semver
    argocd-image-updater.argoproj.io/my-app.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
```

## Creating New Application

### Option 1: Use Template
```bash
cp -r _template my-new-app
cd my-new-app
# Edit manifests
```

### Option 2: Use Script (Coming Soon)
```bash
./scripts/create-app.sh my-new-app
```

## Environment Management

### Development (dev)
- Auto-sync enabled
- Lower resources
- Debug logging enabled

### Production (prod)
- Manual sync or approval required
- Higher resources
- Production-grade settings

## Best Practices

1. **Never commit secrets** - Use External Secrets Operator
2. **Use semantic versioning** - v1.2.3 format
3. **Test in dev first** - Then promote to prod
4. **Small changes** - One service per PR
5. **Document changes** - Clear commit messages

## Monitoring

All applications automatically get:
- ✅ Prometheus metrics
- ✅ Grafana dashboards
- ✅ Jaeger tracing (if instrumented)
- ✅ Logs aggregation

## Troubleshooting

### Application Not Syncing
```bash
kubectl get application -n argocd
kubectl describe application my-app -n argocd
```

### Check ArgoCD Logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Force Sync
```bash
argocd app sync my-app --force
```

## Examples

See `example-api/` for a complete example microservice.
