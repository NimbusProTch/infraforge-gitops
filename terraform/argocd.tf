# ============================================================================
# ArgoCD Namespace
# ============================================================================

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}

# ============================================================================
# ArgoCD Helm Release
# ============================================================================

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.6"

  values = [templatefile("${path.root}/../argocd/argocd-values.yaml", {
    domain     = local.apps_config.domain
    cert_arn   = local.acm_enabled ? aws_acm_certificate.wildcard[0].arn : ""
    account_id = local.apps_config.aws.account_id
    region     = var.aws_region
  })]

  depends_on = [
    module.eks,
    helm_release.aws_load_balancer_controller
  ]

  # Increase timeout for ArgoCD installation
  timeout = 600

  # Wait for resources to be ready
  wait = true
}

# ============================================================================
# Wait for ArgoCD to be Ready
# ============================================================================

resource "time_sleep" "wait_for_argocd" {
  create_duration = "90s"

  depends_on = [helm_release.argocd]
}

# ============================================================================
# ArgoCD ApplicationSet
# ============================================================================
# Note: This uses List generator populated with enabled apps from config

resource "kubectl_manifest" "argocd_applicationset" {
  yaml_body = templatefile("${path.root}/../argocd/applicationset.yaml", {
    repo_url     = var.git_repo_url
    domain       = local.apps_config.domain
    cert_arn     = local.acm_enabled ? aws_acm_certificate.wildcard[0].arn : ""
    account_id   = local.apps_config.aws.account_id
    region       = var.aws_region
    applications = local.enabled_apps
  })

  depends_on = [time_sleep.wait_for_argocd]
}

# ============================================================================
# ArgoCD Root Application
# ============================================================================

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = templatefile("${path.root}/../argocd/root-app.yaml", {
    repo_url = var.git_repo_url
  })

  depends_on = [time_sleep.wait_for_argocd]
}

# ============================================================================
# ArgoCD Initial Admin Password Secret
# ============================================================================

# Get the initial admin password
data "kubernetes_secret" "argocd_initial_admin_secret" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}

# ============================================================================
# ArgoCD GitHub Repository Secret (Optional - for private repos)
# ============================================================================

# Uncomment if using private GitHub repositories
# resource "kubernetes_secret" "argocd_repo" {
#   metadata {
#     name      = "github-repo"
#     namespace = kubernetes_namespace.argocd.metadata[0].name
#     labels = {
#       "argocd.argoproj.io/secret-type" = "repository"
#     }
#   }

#   data = {
#     type          = "git"
#     url           = var.git_repo_url
#     password      = var.github_token
#     username      = "git"
#   }

#   depends_on = [helm_release.argocd]
# }
