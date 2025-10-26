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

  # Apps grouped by database type
  mysql_apps = {
    for k, v in local.enabled_apps : k => v
    if v.database.type == "mysql"
  }

  postgresql_apps = {
    for k, v in local.enabled_apps : k => v
    if v.database.type == "postgresql"
  }

  # ============================================================================
  # AWS Managed Databases
  # ============================================================================
  need_mysql = (
    try(local.apps_config.infrastructure.rds.mysql.enabled, false) &&
    length(local.mysql_apps) > 0
  )

  need_postgresql = (
    try(local.apps_config.infrastructure.rds.postgresql.enabled, false) &&
    length(local.postgresql_apps) > 0
  )

  # ============================================================================
  # AWS Managed Services (External)
  # ============================================================================
  elasticache_enabled = try(local.apps_config.infrastructure.elasticache.enabled, false)
  amazon_mq_enabled   = try(local.apps_config.infrastructure.amazon_mq.enabled, false)
  msk_enabled         = try(local.apps_config.infrastructure.msk.enabled, false)
  sqs_enabled         = try(local.apps_config.infrastructure.sqs.enabled, false)

  # ============================================================================
  # Container Registry
  # ============================================================================
  ecr_enabled = try(local.apps_config.infrastructure.ecr.enabled, true)

  # ECR apps - only create for apps with ecr.enabled = true
  ecr_apps = local.ecr_enabled ? [
    for k, v in local.apps_config.applications : k
    if try(v.ecr.enabled, true) # Default to true if ecr.enabled not specified
  ] : []

  # ============================================================================
  # DNS & Certificates
  # ============================================================================
  route53_enabled = try(local.apps_config.infrastructure.route53.enabled, true)
  acm_enabled     = try(local.apps_config.infrastructure.acm.enabled, true)

  # ============================================================================
  # Secrets Management
  # ============================================================================
  external_secrets_enabled = try(local.apps_config.infrastructure.external_secrets.enabled, false)
  secrets_manager_enabled  = try(local.apps_config.infrastructure.external_secrets.secrets_manager.enabled, false)

  # ============================================================================
  # Monitoring Stack
  # ============================================================================
  prometheus_enabled   = try(local.apps_config.infrastructure.monitoring.prometheus.enabled, false)
  grafana_enabled      = try(local.apps_config.infrastructure.monitoring.grafana.enabled, false)
  alertmanager_enabled = try(local.apps_config.infrastructure.monitoring.alertmanager.enabled, false)

  # ============================================================================
  # Logging & Tracing Stack
  # ============================================================================
  loki_enabled          = try(local.apps_config.infrastructure.logging.loki.enabled, false)
  opentelemetry_enabled = try(local.apps_config.infrastructure.logging.opentelemetry.enabled, false)

  # ============================================================================
  # Backup
  # ============================================================================
  velero_enabled = try(local.apps_config.infrastructure.backup.velero.enabled, false)

  # ============================================================================
  # Internal Operators
  # ============================================================================
  cloudnative_pg_enabled    = try(local.apps_config.infrastructure.internal_operators.cloudnative_pg.enabled, false)
  redis_operator_enabled    = try(local.apps_config.infrastructure.internal_operators.redis_operator.enabled, false)
  rabbitmq_operator_enabled = try(local.apps_config.infrastructure.internal_operators.rabbitmq_operator.enabled, false)
  mongodb_operator_enabled  = try(local.apps_config.infrastructure.internal_operators.mongodb_operator.enabled, false)
  strimzi_kafka_enabled     = try(local.apps_config.infrastructure.internal_operators.strimzi_kafka.enabled, false)

  # Common tags
  common_tags = merge(
    var.default_tags,
    {
      Environment = local.apps_config.environment
      ManagedBy   = "opentofu"
      Project     = "infraforge"
      Domain      = local.apps_config.domain
    }
  )

  # EKS cluster identifier
  cluster_name = var.cluster_name
}
