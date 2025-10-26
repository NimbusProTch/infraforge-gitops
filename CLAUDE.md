# InfraForge GitOps Platform - Technical Specification

You are a Senior DevOps Engineer building **InfraForge**, a production-ready Kubernetes platform on AWS with **single-config-file management** and full automation.

---

## 🎯 PRIMARY OBJECTIVE

Build a **config-driven, fully automated** Kubernetes platform where:
- **ONE CONFIG FILE** (`config/apps.yaml`) controls everything
- Enable/disable apps by changing `enabled: true/false`
- DNS, certificates, namespaces, ECR repos → all auto-created
- Zero manual intervention after initial setup

---

## 🏗️ ARCHITECTURE OVERVIEW

```
config/apps.yaml (SINGLE SOURCE OF TRUTH)
    ↓
OpenTofu:
  ├─ Infrastructure (VPC, EKS, RDS)
  ├─ AWS Controllers:
  │   ├─ EBS CSI Driver
  │   ├─ AWS Load Balancer Controller
  │   ├─ ExternalDNS (Route53)
  │   └─ NO Cert-Manager (AWS ACM only!)
  ├─ Per-app (if enabled=true):
  │   ├─ ECR Repository
  │   ├─ Route53 DNS record
  │   ├─ K8s Namespace
  │   └─ K8s Secrets (DB)
  └─ ArgoCD + ApplicationSet
    ↓
ArgoCD ApplicationSet reads config/apps.yaml
    ↓
Deploys enabled apps automatically
```

**Domain:** `ticarethanem.net`
**Wildcard Certificate:** `*.ticarethanem.net` (AWS ACM - created automatically via OpenTofu)

---

## 📁 PROJECT STRUCTURE

```
infraforge-gitops/
├── config/
│   └── apps.yaml                    # ← SINGLE SOURCE OF TRUTH
│
├── terraform/
│   ├── versions.tf                  # Providers (AWS, Kubernetes, Helm, kubectl)
│   ├── variables.tf                 # Input variables
│   ├── locals.tf                    # Local values (parse config, filter enabled apps)
│   ├── main.tf                      # Main orchestrator
│   ├── vpc.tf                       # VPC, subnets, NAT, IGW
│   ├── eks.tf                       # EKS cluster, node groups
│   ├── rds.tf                       # RDS MySQL + PostgreSQL (or Aurora Serverless)
│   ├── route53.tf                   # Route53 zone, records
│   ├── acm.tf                       # ACM wildcard certificate
│   ├── ecr.tf                       # ECR repositories (per app)
│   ├── addons.tf                    # EBS CSI, AWS LBC, ExternalDNS
│   ├── argocd.tf                    # ArgoCD installation + ApplicationSet
│   ├── app-resources.tf             # Per-app: namespaces, secrets, DNS
│   ├── outputs.tf                   # Outputs (endpoints, kubeconfig, etc)
│   ├── terraform.tfvars.example     # Example configuration
│   └── .gitignore
│
├── argocd/
│   ├── argocd-values.yaml           # ArgoCD Helm values
│   ├── root-app.yaml                # Root Application
│   └── applicationset.yaml          # ApplicationSet (reads config/apps.yaml)
│
├── helm/
│   └── infraforge-app/              # Generic Helm chart for all apps
│       ├── Chart.yaml
│       ├── values.yaml              # Default values
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml      # Deployment with env, probes, resources
│           ├── service.yaml         # ClusterIP service
│           ├── ingress.yaml         # Ingress with AWS ALB annotations + ACM cert
│           ├── hpa.yaml             # HorizontalPodAutoscaler
│           ├── serviceaccount.yaml  # ServiceAccount
│           └── configmap.yaml       # ConfigMap (optional)
│
├── apps/
│   ├── smk/
│   │   ├── Dockerfile               # Multi-stage build
│   │   ├── src/                     # Application code
│   │   └── .github/workflows/
│   │       └── ci-cd.yaml           # Build → Push to ECR → Update image tag
│   ├── sonsuzenerji/
│   ├── transferhub/
│   ├── dronesight/
│   └── muhasebe/                    # Example new app
│
├── monitoring/
│   ├── prometheus-values.yaml       # Prometheus + Grafana
│   ├── loki-values.yaml             # Loki + Promtail
│   └── kube-prometheus-stack.yaml   # Full monitoring stack
│
├── scripts/
│   ├── setup.sh                     # Initial setup (S3, backend, Helm repos, tofu init)
│   ├── deploy.sh                    # Deploy infrastructure
│   ├── push-images.sh               # Build & push app images to ECR
│   ├── cleanup.sh                   # Cleanup (destroy infrastructure)
│   └── validate-config.sh           # Validate apps.yaml schema
│
├── docs/
│   ├── architecture.md              # Architecture overview
│   ├── setup-guide.md               # Step-by-step setup
│   ├── app-onboarding.md            # How to add new app
│   └── troubleshooting.md           # Common issues
│
├── README.md                        # Project overview
├── SETUP_GUIDE.md                   # Quick start guide
└── .gitignore
```

---

## 📝 CONFIG FILE STRUCTURE

### `config/apps.yaml` (SINGLE SOURCE OF TRUTH)

```yaml
# Global settings
domain: "ticarethanem.net"
environment: "production"

aws:
  region: "eu-west-1"
  acm_certificate_arn: "arn:aws:acm:eu-west-1:ACCOUNT_ID:certificate/CERT_ID"  # *.ticarethanem.net

# Database settings
database:
  mysql:
    engine_version: "8.0"
    instance_class: "db.t3.small"
    allocated_storage: 20
  postgresql:
    engine_version: "15"
    instance_class: "db.t3.small"
    allocated_storage: 20

# Applications
applications:
  smk:
    enabled: true
    namespace: smk
    subdomain: smk                    # → smk.ticarethanem.net
    replicas: 2
    image:
      repository_name: smk            # ECR repo name
      tag: latest
    resources:
      cpu: "500m"
      memory: "512Mi"
    ingress:
      enabled: true
      path: /
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/certificate-arn: "${aws.acm_certificate_arn}"
        alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
        alb.ingress.kubernetes.io/ssl-redirect: "443"
    database:
      type: mysql                     # mysql or postgresql
      name: smk_db
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 10
      targetCPUUtilizationPercentage: 75

  sonsuzenerji:
    enabled: true
    namespace: sonsuzenerji
    subdomain: sonsuz
    replicas: 3
    image:
      repository_name: sonsuzenerji
      tag: latest
    resources:
      cpu: "1000m"
      memory: "1Gi"
    ingress:
      enabled: true
    database:
      type: postgresql
      name: sonsuzenerji_db
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 15

  transferhub:
    enabled: false                    # ← DISABLED (no resources created)
    namespace: transferhub
    subdomain: transfer
    replicas: 2
    image:
      repository_name: transferhub
    database:
      type: mysql

  dronesight:
    enabled: false                    # ← DISABLED
    namespace: dronesight
    subdomain: drone
    database:
      type: postgresql

  muhasebe:
    enabled: true                     # ← NEW APP (auto-deployed)
    namespace: muhasebe
    subdomain: muhasebe
    replicas: 2
    image:
      repository_name: muhasebe
      tag: v1.0.0
    resources:
      cpu: "250m"
      memory: "256Mi"
    ingress:
      enabled: true
    database:
      type: postgresql
      name: muhasebe_db
    autoscaling:
      enabled: false
```

---

## 🛠️ TERRAFORM IMPLEMENTATION

### 1. `terraform/versions.tf`

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  backend "s3" {
    bucket         = "infraforge-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "infraforge-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.default_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
```

### 2. `terraform/locals.tf`

```hcl
locals {
  # Parse config file
  apps_config = yamldecode(file("${path.root}/../config/apps.yaml"))

  # Filter only enabled apps
  enabled_apps = {
    for k, v in local.apps_config.applications : k => v
    if v.enabled == true
  }

  # All apps (for ECR - create repos even if disabled for future use)
  all_apps = keys(local.apps_config.applications)

  # Apps with ingress enabled
  ingress_enabled_apps = {
    for k, v in local.enabled_apps : k => v
    if try(v.ingress.enabled, false)
  }

  # Common tags
  common_tags = merge(
    var.default_tags,
    {
      Environment = local.apps_config.environment
      ManagedBy   = "terraform"
      Project     = "infraforge"
    }
  )
}
```

### 3. `terraform/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "infraforge-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "node_instance_types" {
  description = "Node instance types"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 6
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD"
  type        = string
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    Project   = "infraforge"
    ManagedBy = "terraform"
  }
}
```

### 4. `terraform/ecr.tf`

```hcl
# ECR repositories for ALL apps (even disabled ones - for future use)
resource "aws_ecr_repository" "apps" {
  for_each = toset(local.all_apps)

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name        = each.key
      Application = each.key
    }
  )
}

# Lifecycle policy (keep last 10 images)
resource "aws_ecr_lifecycle_policy" "apps" {
  for_each = aws_ecr_repository.apps

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Output ECR URLs
output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    for k, v in aws_ecr_repository.apps : k => v.repository_url
  }
}
```

### 5. `terraform/route53.tf`

```hcl
# Route53 hosted zone (assuming it already exists)
data "aws_route53_zone" "main" {
  name         = "${local.apps_config.domain}."
  private_zone = false
}

# DNS records for enabled apps with ingress
resource "aws_route53_record" "apps" {
  for_each = local.ingress_enabled_apps

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${each.value.subdomain}.${local.apps_config.domain}"
  type    = "A"

  alias {
    name                   = data.kubernetes_service.aws_lb.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.kubernetes_service.aws_lb.status[0].load_balancer[0].ingress[0].zone_id
    evaluate_target_health = true
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubectl_manifest.argocd_applicationset
  ]
}

# Get ALB info from Ingress service
data "kubernetes_service" "aws_lb" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
```

### 6. `terraform/acm.tf`

```hcl
# Wildcard certificate for *.ticarethanem.net
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${local.apps_config.domain}"
  validation_method = "DNS"

  subject_alternative_names = [
    local.apps_config.domain  # Root domain
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "wildcard-${local.apps_config.domain}"
    }
  )
}

# DNS validation records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Output certificate ARN (to be used in apps.yaml)
output "acm_certificate_arn" {
  description = "ACM wildcard certificate ARN"
  value       = aws_acm_certificate.wildcard.arn
}
```

### 7. `terraform/addons.tf`

```hcl
# EBS CSI Driver
module "ebs_csi_driver" {
  source  = "terraform-aws-modules/eks/aws//modules/ebs-csi-driver"
  version = "~> 19.0"

  cluster_name = module.eks.cluster_name

  irsa_role_arn = module.ebs_csi_irsa.iam_role_arn

  tags = local.common_tags
}

# IRSA for EBS CSI Driver
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_lb_controller_irsa.iam_role_arn
  }

  depends_on = [module.eks]
}

# IRSA for AWS Load Balancer Controller
module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-aws-lb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

# ExternalDNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = "1.13.1"

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_dns_irsa.iam_role_arn
  }

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "domainFilters[0]"
    value = local.apps_config.domain
  }

  set {
    name  = "txtOwnerId"
    value = data.aws_route53_zone.main.zone_id
  }

  depends_on = [module.eks]
}

# IRSA for ExternalDNS
module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [data.aws_route53_zone.main.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = local.common_tags
}
```

### 8. `terraform/app-resources.tf`

```hcl
# Kubernetes namespaces for enabled apps
resource "kubernetes_namespace" "apps" {
  for_each = local.enabled_apps

  metadata {
    name = each.value.namespace

    labels = {
      "app.kubernetes.io/name"       = each.key
      "app.kubernetes.io/managed-by" = "terraform"
      "infraforge.io/app"            = each.key
    }

    annotations = {
      "infraforge.io/subdomain" = each.value.subdomain
    }
  }
}

# Database secrets for enabled apps
resource "kubernetes_secret" "db_credentials" {
  for_each = local.enabled_apps

  metadata {
    name      = "db-credentials"
    namespace = kubernetes_namespace.apps[each.key].metadata[0].name
  }

  data = {
    DATABASE_URL = each.value.database.type == "mysql" ? (
      "mysql://${var.db_username}:${var.db_password}@${aws_db_instance.mysql[0].endpoint}/${try(each.value.database.name, "${each.key}_db")}"
    ) : (
      "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgresql[0].endpoint}/${try(each.value.database.name, "${each.key}_db")}"
    )
    DB_HOST     = each.value.database.type == "mysql" ? aws_db_instance.mysql[0].address : aws_db_instance.postgresql[0].address
    DB_PORT     = each.value.database.type == "mysql" ? tostring(aws_db_instance.mysql[0].port) : tostring(aws_db_instance.postgresql[0].port)
    DB_NAME     = try(each.value.database.name, "${each.key}_db")
    DB_USERNAME = var.db_username
    DB_PASSWORD = var.db_password
  }

  type = "Opaque"
}

# ConfigMap with app-specific configuration
resource "kubernetes_config_map" "app_config" {
  for_each = local.enabled_apps

  metadata {
    name      = "${each.key}-config"
    namespace = kubernetes_namespace.apps[each.key].metadata[0].name
  }

  data = {
    APP_NAME    = each.key
    ENVIRONMENT = local.apps_config.environment
    DOMAIN      = "${each.value.subdomain}.${local.apps_config.domain}"
  }
}
```

### 9. `terraform/argocd.tf`

```hcl
# ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# ArgoCD Helm release
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.6"

  values = [file("${path.root}/../argocd/argocd-values.yaml")]

  depends_on = [module.eks]
}

# Wait for ArgoCD to be ready
resource "time_sleep" "wait_for_argocd" {
  create_duration = "60s"
  depends_on      = [helm_release.argocd]
}

# ArgoCD ApplicationSet
resource "kubectl_manifest" "argocd_applicationset" {
  yaml_body = templatefile("${path.root}/../argocd/applicationset.yaml", {
    repo_url = var.git_repo_url
    domain   = local.apps_config.domain
    cert_arn = aws_acm_certificate.wildcard.arn
  })

  depends_on = [time_sleep.wait_for_argocd]
}

# ArgoCD root application
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = file("${path.root}/../argocd/root-app.yaml")

  depends_on = [time_sleep.wait_for_argocd]
}
```

---

## 🔄 ARGOCD CONFIGURATION

### `argocd/argocd-values.yaml`

```yaml
global:
  domain: argocd.ticarethanem.net

server:
  replicas: 2
  service:
    type: LoadBalancer
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/certificate-arn: "ACM_CERT_ARN_HERE"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      external-dns.alpha.kubernetes.io/hostname: argocd.ticarethanem.net
    hosts:
      - argocd.ticarethanem.net
    tls:
      - hosts:
          - argocd.ticarethanem.net

controller:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

repoServer:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

applicationSet:
  enabled: true
  replicas: 2

configs:
  params:
    server.insecure: true
  cm:
    timeout.reconciliation: 30s
```

### `argocd/applicationset.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infraforge-apps
  namespace: argocd
spec:
  generators:
    # Git file generator - reads config/apps.yaml
    - git:
        repoURL: ${repo_url}
        revision: main
        files:
          - path: "config/apps.yaml"

  # Only generate Applications for enabled apps
  template:
    metadata:
      name: '{{path.basename}}'
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io

    spec:
      project: default

      source:
        repoURL: ${repo_url}
        targetRevision: main
        path: helm/infraforge-app
        helm:
          releaseName: '{{path.basename}}'
          values: |
            nameOverride: {{path.basename}}
            fullnameOverride: {{path.basename}}

            replicaCount: {{applications.[path.basename].replicas}}

            image:
              repository: AWS_ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com/{{applications.[path.basename].image.repository_name}}
              tag: {{applications.[path.basename].image.tag}}
              pullPolicy: Always

            service:
              type: ClusterIP
              port: 80
              targetPort: 8080

            ingress:
              enabled: {{applications.[path.basename].ingress.enabled}}
              className: alb
              annotations:
                alb.ingress.kubernetes.io/scheme: internet-facing
                alb.ingress.kubernetes.io/target-type: ip
                alb.ingress.kubernetes.io/certificate-arn: ${cert_arn}
                alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
                alb.ingress.kubernetes.io/ssl-redirect: "443"
                external-dns.alpha.kubernetes.io/hostname: {{applications.[path.basename].subdomain}}.${domain}
              hosts:
                - host: {{applications.[path.basename].subdomain}}.${domain}
                  paths:
                    - path: /
                      pathType: Prefix

            resources:
              requests:
                cpu: {{applications.[path.basename].resources.cpu}}
                memory: {{applications.[path.basename].resources.memory}}
              limits:
                cpu: {{applications.[path.basename].resources.cpu}}
                memory: {{applications.[path.basename].resources.memory}}

            autoscaling:
              enabled: {{applications.[path.basename].autoscaling.enabled}}
              minReplicas: {{applications.[path.basename].autoscaling.minReplicas}}
              maxReplicas: {{applications.[path.basename].autoscaling.maxReplicas}}
              targetCPUUtilizationPercentage: {{applications.[path.basename].autoscaling.targetCPUUtilizationPercentage}}

            env:
              - name: APP_NAME
                valueFrom:
                  configMapKeyRef:
                    name: {{path.basename}}-config
                    key: APP_NAME
              - name: ENVIRONMENT
                valueFrom:
                  configMapKeyRef:
                    name: {{path.basename}}-config
                    key: ENVIRONMENT
              - name: DATABASE_URL
                valueFrom:
                  secretKeyRef:
                    name: db-credentials
                    key: DATABASE_URL
              - name: DB_HOST
                valueFrom:
                  secretKeyRef:
                    name: db-credentials
                    key: DB_HOST
              - name: DB_PORT
                valueFrom:
                  secretKeyRef:
                    name: db-credentials
                    key: DB_PORT
              - name: DB_NAME
                valueFrom:
                  secretKeyRef:
                    name: db-credentials
                    key: DB_NAME
              - name: DB_USERNAME
                valueFrom:
                  secretKeyRef:
                    name: db-credentials
                    key: DB_USERNAME
              - name: DB_PASSWORD
                valueFrom:
                  secretKeyRef:
                    name: db-credentials
                    key: DB_PASSWORD

      destination:
        server: https://kubernetes.default.svc
        namespace: '{{applications.[path.basename].namespace}}'

      syncPolicy:
        automated:
          prune: true       # Delete resources when app is disabled
          selfHeal: true    # Auto-sync on drift
          allowEmpty: false
        syncOptions:
          - CreateNamespace=false  # Terraform already created it
          - PrunePropagationPolicy=foreground
          - PruneLast=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
```

### `argocd/root-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infraforge-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: GIT_REPO_URL_HERE
    targetRevision: main
    path: argocd

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 📦 HELM CHART

### `helm/infraforge-app/Chart.yaml`

```yaml
apiVersion: v2
name: infraforge-app
description: Generic Helm chart for InfraForge applications
type: application
version: 1.0.0
appVersion: "1.0.0"
```

### `helm/infraforge-app/values.yaml`

```yaml
replicaCount: 2

image:
  repository: nginx  # Override in ApplicationSet
  tag: latest
  pullPolicy: Always

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false
  className: alb
  annotations: {}
  hosts:
    - host: app.ticarethanem.net
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 75
  targetMemoryUtilizationPercentage: 80

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

env: []

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"

nodeSelector: {}

tolerations: []

affinity: {}
```

### `helm/infraforge-app/templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "infraforge-app.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "infraforge-app.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "infraforge-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "infraforge-app.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "infraforge-app.serviceAccountName" . }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
          readinessProbe:
            {{- toYaml .Values.readinessProbe | nindent 12 }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          env:
            {{- range .Values.env }}
            - name: {{ .name }}
              {{- if .value }}
              value: {{ .value | quote }}
              {{- else if .valueFrom }}
              valueFrom:
                {{- toYaml .valueFrom | nindent 16 }}
              {{- end }}
            {{- end }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

### `helm/infraforge-app/templates/ingress.yaml`

```yaml
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "infraforge-app.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "infraforge-app.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "infraforge-app.fullname" $ }}
                port:
                  number: {{ $.Values.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
```

---

## 🔧 SCRIPTS

### `scripts/setup.sh`

```bash
#!/bin/bash
set -e

echo "🚀 InfraForge Setup Script"
echo "=========================="

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not found"; exit 1; }
command -v tofu >/dev/null 2>&1 || { echo "❌ OpenTofu not found"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ Helm not found"; exit 1; }
echo "✅ All prerequisites installed"

# Create S3 bucket for Terraform state
BUCKET_NAME="infraforge-terraform-state"
AWS_REGION="eu-west-1"

echo "Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION \
  2>/dev/null || echo "Bucket already exists"

aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo "✅ S3 bucket configured"

# Create DynamoDB table for state locking
echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name infraforge-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION \
  2>/dev/null || echo "Table already exists"

echo "✅ DynamoDB table configured"

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo add eks https://aws.github.io/eks-charts
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update
echo "✅ Helm repositories added"

# Initialize Terraform
echo "Initializing Terraform..."
cd terraform
tofu init
echo "✅ Terraform initialized"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit config/apps.yaml"
echo "2. Run: cd terraform && tofu plan"
echo "3. Run: tofu apply"
```

### `scripts/push-images.sh`

```bash
#!/bin/bash
set -e

echo "🐳 Building and pushing Docker images to ECR"
echo "============================================="

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="eu-west-1"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Read config
APPS=$(yq eval '.applications | keys | .[]' ../config/apps.yaml)

for APP in $APPS; do
  echo ""
  echo "📦 Building $APP..."

  if [ -d "../apps/$APP" ]; then
    cd "../apps/$APP"

    # Build image
    docker build -t $APP:latest .

    # Tag for ECR
    docker tag $APP:latest $ECR_REGISTRY/$APP:latest

    # Push to ECR
    docker push $ECR_REGISTRY/$APP:latest

    echo "✅ $APP pushed to ECR"
    cd -
  else
    echo "⚠️  Directory apps/$APP not found, skipping..."
  fi
done

echo ""
echo "✅ All images pushed successfully!"
```

---

## 📚 DOCUMENTATION

### `README.md`

```markdown
# InfraForge GitOps Platform

Production-ready Kubernetes platform on AWS with **single-config-file management**.

## Features

- ✅ **Config-driven**: One file (`config/apps.yaml`) to rule them all
- ✅ **Full automation**: DNS, certificates, namespaces → auto-created
- ✅ **GitOps**: ArgoCD for continuous deployment
- ✅ **AWS Native**: ACM certs, ALB ingress, Route53 DNS
- ✅ **Scalable**: Auto-scaling nodes and pods
- ✅ **Secure**: Private subnets, encrypted RDS, RBAC

## Quick Start

```bash
# 1. Clone repo
git clone <repo-url>
cd infraforge-gitops

# 2. Edit configuration
vim config/apps.yaml

# 3. Run setup
./scripts/setup.sh

# 4. Deploy infrastructure
cd terraform
tofu plan
tofu apply

# 5. Build and push app images
../scripts/push-images.sh

# 6. Done! ArgoCD will deploy apps automatically
```

## Enable/Disable Applications

Edit `config/apps.yaml`:

```yaml
applications:
  muhasebe:
    enabled: true  # ← Change to false to disable
```

Then:

```bash
cd terraform
tofu apply  # Removes namespace, DNS, etc.
# ArgoCD auto-deletes the app
```

## Architecture

```
config/apps.yaml → Terraform → AWS (VPC, EKS, RDS, DNS, Certs)
                             → ArgoCD ApplicationSet
                             → Deploy apps
```

## Cost Estimation

- Base (no apps): ~$150/month (EKS + minimal nodes)
- Per app: ~$30-50/month (additional nodes + load balancer)

## Support

Issues: https://github.com/yourorg/infraforge-gitops/issues
```

---

## ✅ IMPLEMENTATION CHECKLIST

```
Phase 1: Infrastructure Foundation
├── [ ] Create directory structure
├── [ ] Write config/apps.yaml (with real apps)
├── [ ] Write terraform/versions.tf
├── [ ] Write terraform/variables.tf
├── [ ] Write terraform/locals.tf
├── [ ] Write terraform/vpc.tf
├── [ ] Write terraform/eks.tf
├── [ ] Write terraform/rds.tf
├── [ ] Write terraform/route53.tf
├── [ ] Write terraform/acm.tf
└── [ ] Write terraform/outputs.tf

Phase 2: EKS Addons & App Resources
├── [ ] Write terraform/ecr.tf (ECR repos for all apps)
├── [ ] Write terraform/addons.tf (EBS CSI, LBC, ExternalDNS)
├── [ ] Write terraform/app-resources.tf (namespaces, secrets)
└── [ ] Write terraform/argocd.tf

Phase 3: GitOps Configuration
├── [ ] Write argocd/argocd-values.yaml
├── [ ] Write argocd/applicationset.yaml
└── [ ] Write argocd/root-app.yaml

Phase 4: Helm Chart (Generic for all apps)
├── [ ] Write helm/infraforge-app/Chart.yaml
├── [ ] Write helm/infraforge-app/values.yaml
├── [ ] Write helm/infraforge-app/templates/_helpers.tpl
├── [ ] Write helm/infraforge-app/templates/deployment.yaml
├── [ ] Write helm/infraforge-app/templates/service.yaml
├── [ ] Write helm/infraforge-app/templates/ingress.yaml
├── [ ] Write helm/infraforge-app/templates/hpa.yaml
└── [ ] Write helm/infraforge-app/templates/serviceaccount.yaml

Phase 5: Scripts & Automation
├── [ ] Write scripts/setup.sh
├── [ ] Write scripts/push-images.sh
├── [ ] Write scripts/deploy.sh
└── [ ] Write scripts/cleanup.sh

Phase 6: Documentation
├── [ ] Write README.md
├── [ ] Write SETUP_GUIDE.md
├── [ ] Write docs/architecture.md
└── [ ] Write docs/troubleshooting.md

Phase 7: App Examples
├── [ ] Prepare apps/smk (if not ready)
├── [ ] Prepare apps/sonsuzenerji
├── [ ] Prepare apps/transferhub
└── [ ] Prepare apps/dronesight
```

---

## 🚀 START BUILDING?

Ready to implement? Say "start" and I'll begin creating all files step by step!
