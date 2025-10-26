# GitHub Actions CI/CD Setup Guide

Bu döküman, InfraForge GitOps Platform için GitHub Actions CI/CD pipeline'ının nasıl kurulacağını açıklar.

## 📋 Genel Bakış

Her mikroservis kendi repository'sinde:
1. **Build** - Docker image oluşturulur
2. **Test** - Testler çalıştırılır (optional)
3. **Push** - ECR'a push edilir
4. **Update** - GitOps repo'sunda image tag güncellenir
5. **Deploy** - ArgoCD otomatik sync yapar

## 🚀 Kurulum Adımları

### 1. App Repository'nizi Hazırlayın

Her mikroservis için ayrı bir GitHub repository oluşturun:
```
smk/
├── Dockerfile
├── src/
├── .github/
│   └── workflows/
│       └── ci-cd.yml  # Bu dosyayı oluşturacaksınız
└── ...
```

### 2. GitHub Secrets Ekleyin

App repository'nizde **Settings → Secrets and variables → Actions** bölümünden şu secrets'ları ekleyin:

#### Required Secrets:
- **`AWS_ACCESS_KEY_ID`** - AWS IAM kullanıcısı access key
- **`AWS_SECRET_ACCESS_KEY`** - AWS IAM kullanıcısı secret key
- **`GITOPS_REPO_TOKEN`** - GitOps repo'ya write erişimi olan GitHub Personal Access Token

#### `GITOPS_REPO_TOKEN` Oluşturma:
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" tıklayın
3. Scopes: `repo` (Full control of private repositories)
4. Token'ı kopyalayıp secret olarak ekleyin

### 3. Workflow Dosyasını Kopyalayın

```bash
# GitOps repo'dan template'i kopyalayın
cp infraforge-gitops/.github/workflows/app-ci-template.yml your-app/.github/workflows/ci-cd.yml
```

### 4. Workflow'u Özelleştirin

`ci-cd.yml` dosyasını açın ve şu değişkenleri güncelleyin:

```yaml
env:
  AWS_REGION: eu-west-1
  APP_NAME: smk                          # ← App adınız (config/apps.yaml'dakiyle aynı)
  ECR_REPOSITORY: smk                    # ← ECR repository adınız
  GITOPS_REPO: NimbusProTch/infraforge-gitops # ← GitOps repo'nuz
  HELM_VALUES_PATH: helm/infraforge-app/values-smk.yaml # ← Values dosya yolu
```

### 5. Helm Values Dosyası Oluşturun

GitOps repository'sinde app'iniz için values dosyası oluşturun:

```bash
cd infraforge-gitops
cp helm/infraforge-app/values.yaml helm/infraforge-app/values-smk.yaml
```

`values-smk.yaml` dosyasını düzenleyin:
```yaml
nameOverride: "smk"
fullnameOverride: "smk"

image:
  repository: 715841344657.dkr.ecr.eu-west-1.amazonaws.com/smk
  tag: "latest"  # CI/CD bu değeri güncelleyecek
  pullPolicy: Always

# ... diğer ayarlar
```

## 📝 Image Tag Stratejisi

Workflow otomatik olarak image tag'leri oluşturur:

| Branch/Ref Type | Image Tag Format | Example |
|----------------|------------------|---------|
| Git Tag (v*) | Tag name | `v1.0.0`, `v2.1.3` |
| main branch | `main-{commit-sha}` | `main-a1b2c3d4` |
| develop branch | `dev-{commit-sha}` | `dev-e5f6g7h8` |
| Feature branch | `{branch}-{commit-sha}` | `feature-auth-i9j0k1l2` |

## 🔄 Workflow Tetikleme

Workflow şu durumlarda tetiklenir:

### Push Events (Build + Deploy):
- `main` branch'e push
- `develop` branch'e push
- Git tag push (örn: `v1.0.0`)

### Pull Request (Sadece Build):
- `main` veya `develop`'a açılan PR'lar
- Sadece build ve test çalışır, deploy yapılmaz

## 🎯 Örnek Kullanım

### Yeni Feature Deploy Etme:

```bash
# 1. Feature branch'inde çalışın
git checkout -b feature/new-api
# ... kod değişiklikleri ...
git commit -m "feat: add new API endpoint"
git push origin feature/new-api

# 2. PR açın (CI otomatik build ve test yapar)
gh pr create --title "feat: new API endpoint"

# 3. PR'ı merge edin (CI otomatik deploy yapar)
gh pr merge

# 4. ArgoCD otomatik sync yapar (30 saniye içinde)
```

### Production Release:

```bash
# 1. main branch'te tag oluşturun
git checkout main
git pull origin main
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# 2. CI/CD pipeline çalışır ve v1.0.0 tag'iyle deploy eder
```

## 🧪 Test Ekleme (Optional)

Workflow'a test adımları eklemek için:

```yaml
# Build stage'de uncomment edin:
- name: Run tests
  run: |
    docker run --rm ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ steps.generate-tag.outputs.tag }} npm test
```

Veya farklı test framework'leri için:

```yaml
# Python
- name: Run Python tests
  run: |
    docker run --rm ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ steps.generate-tag.outputs.tag }} pytest

# Go
- name: Run Go tests
  run: |
    docker run --rm ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ steps.generate-tag.outputs.tag }} go test ./...
```

## 🔍 Troubleshooting

### Issue: "Permission denied" hatası

**Çözüm:** `GITOPS_REPO_TOKEN` secret'ının doğru scope'larla oluşturulduğundan emin olun (`repo` scope gerekli).

### Issue: ECR'a push edilemiyor

**Çözüm:**
1. AWS IAM kullanıcısının ECR write permission'ı olduğundan emin olun
2. ECR repository'sinin oluşturulduğunu kontrol edin
3. AWS secrets'larının doğru olduğunu kontrol edin

### Issue: yq bulunamıyor hatası

**Çözüm:** Workflow'daki yq installation step'inin doğru çalıştığını kontrol edin.

### Issue: ArgoCD sync yapmıyor

**Çözüm:**
1. ArgoCD Application'ın `syncPolicy.automated.prune: true` ve `selfHeal: true` olduğundan emin olun
2. GitOps repo'daki values dosyasının doğru path'te olduğunu kontrol edin
3. ArgoCD UI'da manuel sync deneyin

## 📊 Workflow Status

GitHub repository'nizde workflow status'unu görebilirsiniz:
- **Actions** tab → Workflow runs
- README'ye badge ekleyebilirsiniz:

```markdown
![CI/CD](https://github.com/your-username/your-app/actions/workflows/ci-cd.yml/badge.svg)
```

## 🔗 İlgili Dökümanlar

- [ArgoCD Documentation](../../argocd/README.md)
- [Helm Chart Documentation](../../helm/infraforge-app/README.md)
- [InfraForge GitOps Platform](../../README.md)
