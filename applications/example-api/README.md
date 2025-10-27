# Example API Application

This is an example microservice demonstrating GitOps best practices with ArgoCD.

## Structure

```
example-api/
├── base/                           # Base Kubernetes manifests
│   ├── deployment.yaml            # Main deployment
│   ├── service.yaml               # ClusterIP service
│   └── kustomization.yaml         # Kustomize config (image version here)
└── overlays/                       # Environment-specific configs
    ├── dev/                       # Development environment
    │   └── kustomization.yaml
    └── prod/                      # Production environment
        ├── kustomization.yaml
        └── hpa.yaml              # Auto-scaling for prod
```

## Image Versioning

The current image version is managed in `base/kustomization.yaml`:

```yaml
images:
  - name: ghcr.io/nimbusproch/example-api
    newTag: v1.0.0  # ← CI/CD updates this
```

### How It Works

1. **Developer pushes code** to application repo
2. **CI/CD builds Docker image** (e.g., `v1.2.3`)
3. **CI/CD pushes image** to GHCR
4. **CI/CD updates this file** (`kustomization.yaml`)
5. **ArgoCD detects change** and deploys automatically

## GitOps Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Git Push  │────▶│  CI/CD      │────▶│  Update     │────▶│  ArgoCD     │
│   to main   │     │  Build      │     │  GitOps     │     │  Auto Sync  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                           │                    │                    │
                           ▼                    ▼                    ▼
                    ghcr.io/org/app:v1.2.3  kustomization.yaml  Deploy to K8s
```

## Environments

### Development
- **Namespace**: `dev`
- **Replicas**: 1
- **Resources**: Lower (50m CPU, 64Mi RAM)
- **Auto-sync**: Enabled
- **Debug**: Enabled

### Production
- **Namespace**: `production`
- **Replicas**: 3 (min) - 10 (max with HPA)
- **Resources**: Higher (200m CPU, 256Mi RAM)
- **Auto-sync**: Enabled with self-heal
- **Debug**: Disabled

## Deploy to Cluster

```bash
# Deploy production
kubectl apply -f ../argocd-apps/example-api-prod.yaml

# Check status
kubectl get application -n argocd example-api-prod

# View in ArgoCD UI
make argocd-ui
```

## Update Image Version

### Manual Update
```bash
cd base
kustomize edit set image ghcr.io/nimbusproch/example-api:v1.2.3
git commit -m "Update example-api to v1.2.3"
git push
# ArgoCD will auto-deploy
```

### CI/CD Update (Automated)
```bash
# In your application repo's GitHub Actions:
kustomize edit set image ghcr.io/nimbusproch/example-api:$VERSION
```

## Monitoring

### Prometheus Metrics
Automatically scraped from `/metrics` endpoint on port 8080.

### Logs
```bash
# View logs
kubectl logs -n production -l app=example-api -f

# Last 100 lines
kubectl logs -n production -l app=example-api --tail=100
```

### Tracing
Integrated with Jaeger via OpenTelemetry.

## Health Checks

### Liveness Probe
`GET /health` on port 8080

### Readiness Probe
`GET /ready` on port 8080

## Scaling

### Manual Scaling
```bash
kubectl scale deployment example-api -n production --replicas=5
```

### Auto-scaling (Production Only)
HPA configured to scale between 3-10 replicas based on:
- CPU: 70% threshold
- Memory: 80% threshold

## Testing Locally

```bash
# Build kustomize output
cd base
kustomize build .

# Apply to local cluster
kustomize build . | kubectl apply -f -
```

## Troubleshooting

### Pod not starting
```bash
kubectl describe pod -n production -l app=example-api
kubectl logs -n production -l app=example-api
```

### Image pull errors
```bash
# Check if image exists
docker pull ghcr.io/nimbusproch/example-api:v1.0.0

# Check imagePullSecrets if private
kubectl get secret -n production
```

### ArgoCD not syncing
```bash
# Check application status
kubectl describe application example-api-prod -n argocd

# Force sync
kubectl patch application example-api-prod -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

## Customization

To customize for your own application:

1. **Update deployment.yaml** with your container configuration
2. **Update service.yaml** with your service ports
3. **Update kustomization.yaml** with your image repository
4. **Adjust resources** in overlays for your needs
5. **Commit and push** - ArgoCD handles the rest!

## Best Practices

✅ Use semantic versioning (v1.2.3)
✅ Never use `:latest` tag
✅ Test in dev before prod
✅ Small, incremental changes
✅ Monitor after deployment
✅ Have rollback plan

## Related Documentation

- [Applications README](../README.md)
- [CI/CD Pipeline](.github/workflows/app-ci-cd.yaml)
- [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io/)
