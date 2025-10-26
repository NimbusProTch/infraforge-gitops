# ============================================================================
# Kubernetes Namespaces for Enabled Apps
# ============================================================================

resource "kubernetes_namespace" "apps" {
  for_each = local.enabled_apps

  metadata {
    name = each.value.namespace

    labels = {
      "app.kubernetes.io/name"       = each.key
      "app.kubernetes.io/managed-by" = "terraform"
      "infraforge.io/app"            = each.key
      "infraforge.io/enabled"        = "true"
    }

    annotations = {
      "infraforge.io/subdomain"   = each.value.subdomain
      "infraforge.io/database"    = each.value.database.type
      "infraforge.io/environment" = local.apps_config.environment
    }
  }

  depends_on = [module.eks]
}

# ============================================================================
# Database Secrets for Apps with MySQL
# ============================================================================

resource "kubernetes_secret" "mysql_db_credentials" {
  for_each = local.need_mysql ? local.mysql_apps : {}

  metadata {
    name      = "db-credentials"
    namespace = kubernetes_namespace.apps[each.key].metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = each.key
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    DATABASE_URL = "mysql://${var.db_username}:${random_password.db_master.result}@${aws_db_instance.mysql[0].address}:${aws_db_instance.mysql[0].port}/${try(each.value.database.name, "${each.key}_db")}"
    DB_HOST      = aws_db_instance.mysql[0].address
    DB_PORT      = tostring(aws_db_instance.mysql[0].port)
    DB_NAME      = try(each.value.database.name, "${each.key}_db")
    DB_USERNAME  = var.db_username
    DB_PASSWORD  = random_password.db_master.result
    DB_TYPE      = "mysql"
  }

  type = "Opaque"
}

# ============================================================================
# Database Secrets for Apps with PostgreSQL
# ============================================================================

resource "kubernetes_secret" "postgresql_db_credentials" {
  for_each = local.need_postgresql ? local.postgresql_apps : {}

  metadata {
    name      = "db-credentials"
    namespace = kubernetes_namespace.apps[each.key].metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = each.key
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    DATABASE_URL = "postgresql://${var.db_username}:${random_password.db_master.result}@${aws_db_instance.postgresql[0].address}:${aws_db_instance.postgresql[0].port}/${try(each.value.database.name, "${each.key}_db")}"
    DB_HOST      = aws_db_instance.postgresql[0].address
    DB_PORT      = tostring(aws_db_instance.postgresql[0].port)
    DB_NAME      = try(each.value.database.name, "${each.key}_db")
    DB_USERNAME  = var.db_username
    DB_PASSWORD  = random_password.db_master.result
    DB_TYPE      = "postgresql"
  }

  type = "Opaque"
}

# ============================================================================
# ConfigMap with App-Specific Configuration
# ============================================================================

resource "kubernetes_config_map" "app_config" {
  for_each = local.enabled_apps

  metadata {
    name      = "${each.key}-config"
    namespace = kubernetes_namespace.apps[each.key].metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = each.key
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    APP_NAME     = each.key
    ENVIRONMENT  = local.apps_config.environment
    DOMAIN       = "${each.value.subdomain}.${local.apps_config.domain}"
    AWS_REGION   = var.aws_region
    ECR_REGISTRY = "${local.apps_config.aws.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    IMAGE_REPO   = "${local.apps_config.aws.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${each.value.image.repository_name}"
  }
}

# ============================================================================
# ECR Pull Secret (for private ECR repositories)
# ============================================================================

# Note: EKS nodes already have ECR access via IAM role
# This is for additional security if needed
