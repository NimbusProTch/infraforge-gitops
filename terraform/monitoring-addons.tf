# ============================================================================
# External Secrets Operator
# ============================================================================

# Namespace for External Secrets
resource "kubernetes_namespace" "external_secrets" {
  count = local.external_secrets_enabled ? 1 : 0

  metadata {
    name = "external-secrets"

    labels = {
      "app.kubernetes.io/name"       = "external-secrets"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# IRSA for External Secrets Operator
module "external_secrets_irsa" {
  count   = local.external_secrets_enabled ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    secrets_manager = aws_iam_policy.secrets_manager_access[0].arn
  }

  tags = local.common_tags
}

# IAM Policy for Secrets Manager Access
resource "aws_iam_policy" "secrets_manager_access" {
  count = local.secrets_manager_enabled ? 1 : 0

  name        = "${var.cluster_name}-secrets-manager-access"
  description = "Allow External Secrets Operator to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# External Secrets Operator Helm Release
resource "helm_release" "external_secrets" {
  count = local.external_secrets_enabled ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets[0].metadata[0].name
  version    = "0.9.11"

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa[0].iam_role_arn
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.external_secrets
  ]
}

# ============================================================================
# Prometheus + Grafana Stack (kube-prometheus-stack)
# ============================================================================

# Namespace for Monitoring
resource "kubernetes_namespace" "monitoring" {
  count = local.prometheus_enabled || local.grafana_enabled ? 1 : 0

  metadata {
    name = "monitoring"

    labels = {
      "app.kubernetes.io/name"       = "monitoring"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# kube-prometheus-stack Helm Release
resource "helm_release" "kube_prometheus_stack" {
  count = local.prometheus_enabled ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name
  version    = "55.5.0"

  values = [yamlencode({
    prometheus = {
      enabled = true
      prometheusSpec = {
        retention = local.apps_config.infrastructure.monitoring.prometheus.retention
        replicas  = local.apps_config.infrastructure.monitoring.prometheus.replicas
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = local.apps_config.infrastructure.monitoring.prometheus.storage_size
                }
              }
              storageClassName = "gp3"
            }
          }
        }
        resources = {
          requests = {
            cpu    = "500m"
            memory = "2Gi"
          }
          limits = {
            cpu    = "2000m"
            memory = "4Gi"
          }
        }
      }
    }

    grafana = {
      enabled       = local.grafana_enabled
      adminPassword = random_password.grafana_admin.result
      persistence = {
        enabled          = local.apps_config.infrastructure.monitoring.grafana.persistence_enabled
        size             = local.apps_config.infrastructure.monitoring.grafana.storage_size
        storageClassName = "gp3"
      }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        annotations = {
          "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"     = "ip"
          "alb.ingress.kubernetes.io/certificate-arn" = local.acm_enabled ? aws_acm_certificate.wildcard[0].arn : ""
          "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
          "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          "external-dns.alpha.kubernetes.io/hostname" = "grafana.${local.apps_config.domain}"
        }
        hosts = ["grafana.${local.apps_config.domain}"]
      }
      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }
    }

    alertmanager = {
      enabled = local.alertmanager_enabled
      alertmanagerSpec = {
        replicas = local.apps_config.infrastructure.monitoring.alertmanager.replicas
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "512Mi"
          }
        }
      }
    }

    # Disable some components to reduce resource usage
    kubeStateMetrics = {
      enabled = true
    }
    nodeExporter = {
      enabled = true
    }
    prometheusOperator = {
      enabled = true
    }
  })]

  depends_on = [
    module.eks,
    kubernetes_namespace.monitoring,
    helm_release.aws_load_balancer_controller
  ]

  timeout = 600
}
