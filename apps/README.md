# Apps Directory - GitOps Configurations

Bu klasör **sadece GitOps konfigürasyonları** içerir. Uygulama kodu **ayrı repository'lerdedir**.

## 📁 Klasör Yapısı

```
apps/
├── smk/
│   ├── values.yaml          # Helm values (deployment config)
│   ├── secrets.yaml         # ExternalSecret CRDs
│   ├── configmap.yaml       # App-specific configs
│   └── service-monitor.yaml # Prometheus monitoring (optional)
│
├── sonsuzenerji/
│   ├── values.yaml
│   ├── secrets.yaml
│   └── configmap.yaml
│
├── transferhub/
│   └── ...
│
└── dronesight/
    └── ...
```

## 🎯 Ne İçerir?

### ✅ GitOps Configs (Bu Klasör)
- Deployment configurations (replicas, resources, etc.)
- Ingress rules
- ConfigMaps (non-sensitive configs)
- ExternalSecret definitions (secret references)
- Service configurations
- HPA (Horizontal Pod Autoscaler) settings
- ServiceMonitor (Prometheus)

### ❌ Uygulama Kodu (Ayrı Repo)
- Source code (`src/`)
- Dependencies (`package.json`, `requirements.txt`, etc.)
- Dockerfile
- Tests
- CI/CD workflows (build & push image)

## 🔄 Workflow

### 1. App Kodu Değiştiğinde (App Repo):
```bash
# Developer app repo'sunda çalışır
cd ~/smk/
git commit -m "feat: new feature"
git push origin main

# ↓ CI/CD pipeline çalışır
# ↓ Docker image build edilir
# ↓ ECR'a push edilir: smk:main-a1b2c3d4
# ↓ Bu repo'daki values.yaml güncellenir (yq ile)
```

### 2. GitOps Konfigürasyonu Değiştiğinde (Bu Repo):
```bash
# DevOps engineer bu repo'da çalışır
cd ~/infraforge-gitops/apps/smk/
nano values.yaml  # Replicas, resources, etc.
git commit -m "chore: increase replicas to 5"
git push origin main

# ↓ ArgoCD otomatik sync yapar
# ↓ Kubernetes'e deploy eder
```

## 📝 Dosya Açıklamaları

### `values.yaml`
Helm chart'ın value'ları. Deployment konfigürasyonu:
- Image repository ve tag
- Replica count
- Resource limits
- Autoscaling settings
- Ingress configuration
- Environment variables

**Güncellenme:** CI/CD pipeline image tag'ini günceller

### `secrets.yaml`
ExternalSecret CRD'leri. AWS Secrets Manager'dan secret çeker:
- Database passwords
- API keys
- JWT secrets
- Third-party integration credentials

**Güvenlik:** Asıl secret'lar AWS'de, burada sadece reference

### `configmap.yaml`
Non-sensitive konfigürasyonlar:
- Database connection details (host, port)
- Feature flags
- API endpoints
- Logging levels
- CORS settings

**Not:** Sensitive data burada olmamalı!

### `service-monitor.yaml` (Optional)
Prometheus ServiceMonitor CRD:
- Metric endpoints
- Scrape intervals
- Labels

## 🚀 Yeni App Ekleme

### 1. App Klasörü Oluştur:
```bash
cd apps/
mkdir my-new-app
cd my-new-app
```

### 2. Dosyaları Kopyala:
```bash
# Template olarak mevcut bir app kullan
cp ../smk/values.yaml .
cp ../smk/secrets.yaml .
cp ../smk/configmap.yaml .
```

### 3. Özelleştir:
```bash
# values.yaml'da app adını değiştir
sed -i 's/smk/my-new-app/g' *.yaml

# Image repository güncelle
# Ingress hostname güncelle
# Environment variables güncelle
```

### 4. Config'de Etkinleştir:
```yaml
# config/apps.yaml
applications:
  my-new-app:
    enabled: true
    namespace: my-new-app
    subdomain: mynewapp
    # ...
```

### 5. ArgoCD'ye Ekle:
ArgoCD ApplicationSet otomatik olarak yeni app'i algılar ve deploy eder.

## 🔐 Secret Yönetimi

### AWS Secrets Manager'da Secret Oluşturma:
```bash
# Secret oluştur
aws secretsmanager create-secret \
  --name prod/smk/db-password \
  --secret-string "MySecurePassword123!" \
  --region eu-west-1

# Secret güncelle
aws secretsmanager update-secret \
  --secret-id prod/smk/db-password \
  --secret-string "NewPassword456!" \
  --region eu-west-1
```

### ExternalSecret Tanımla:
```yaml
# apps/smk/secrets.yaml
data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: prod/smk/db-password
```

### App'te Kullan:
```yaml
# apps/smk/values.yaml
envFrom:
  - secretRef:
      name: smk-secrets  # ExternalSecret tarafından oluşturulur
```

## 📊 Monitoring

Her app için ServiceMonitor oluşturulabilir:

```yaml
# apps/smk/service-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: smk
  namespace: smk
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: smk
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

## 🔍 Troubleshooting

### App deploy olmuyor?
```bash
# ArgoCD app status kontrol et
kubectl get application -n argocd

# App logs
kubectl logs -n smk -l app.kubernetes.io/name=smk

# Events
kubectl get events -n smk --sort-by='.lastTimestamp'
```

### Secret sync olmuyor?
```bash
# ExternalSecret status
kubectl get externalsecret -n smk

# Secret oluştu mu?
kubectl get secret smk-secrets -n smk
```

### Ingress çalışmıyor?
```bash
# Ingress status
kubectl get ingress -n smk

# ALB oluştu mu?
kubectl describe ingress -n smk

# DNS kaydı oluştu mu?
dig smk.ticarethanem.net
```

## 📚 İlgili Dökümanlar

- [Infrastructure Components](../docs/infrastructure-components.md)
- [GitHub Actions CI/CD](../.github/workflows/README.md)
- [Helm Chart Documentation](../helm/infraforge-app/README.md)
- [ArgoCD Setup](../argocd/README.md)
