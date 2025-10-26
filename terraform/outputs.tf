# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# EKS Outputs
output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

# RDS Outputs
output "rds_mysql_endpoint" {
  description = "MySQL RDS endpoint"
  value       = local.need_mysql ? aws_db_instance.mysql[0].endpoint : "N/A - MySQL not needed"
}

output "rds_mysql_address" {
  description = "MySQL RDS address"
  value       = local.need_mysql ? aws_db_instance.mysql[0].address : "N/A - MySQL not needed"
}

output "rds_postgresql_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = local.need_postgresql ? aws_db_instance.postgresql[0].endpoint : "N/A - PostgreSQL not needed"
}

output "rds_postgresql_address" {
  description = "PostgreSQL RDS address"
  value       = local.need_postgresql ? aws_db_instance.postgresql[0].address : "N/A - PostgreSQL not needed"
}

# ACM Certificate
output "acm_certificate_arn" {
  description = "ACM wildcard certificate ARN"
  value       = local.acm_enabled ? aws_acm_certificate.wildcard[0].arn : "N/A - ACM disabled"
}

output "acm_certificate_status" {
  description = "ACM certificate validation status"
  value       = local.acm_enabled ? aws_acm_certificate.wildcard[0].status : "N/A - ACM disabled"
}

# ECR Repositories
output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    for k, v in aws_ecr_repository.apps : k => v.repository_url
  }
}

# Route53
output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.route53_enabled ? data.aws_route53_zone.main[0].zone_id : "N/A - Route53 disabled"
}

output "route53_zone_name" {
  description = "Route53 hosted zone name"
  value       = local.route53_enabled ? data.aws_route53_zone.main[0].name : "N/A - Route53 disabled"
}

# Kubeconfig command
output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# Enabled apps
output "enabled_apps" {
  description = "List of enabled applications"
  value       = keys(local.enabled_apps)
}

# Config summary
output "config_summary" {
  description = "Configuration summary"
  value = {
    domain               = local.apps_config.domain
    environment          = local.apps_config.environment
    total_apps           = length(local.all_apps)
    enabled_apps         = length(local.enabled_apps)
    mysql_required       = local.need_mysql
    postgresql_required  = local.need_postgresql
    ingress_enabled_apps = length(local.ingress_enabled_apps)
  }
}

# External Services
output "elasticache_endpoint" {
  description = "ElastiCache endpoint"
  value       = local.elasticache_enabled && length(aws_elasticache_replication_group.redis) > 0 ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : "N/A - ElastiCache disabled"
}

output "amazon_mq_endpoint" {
  description = "Amazon MQ broker endpoint"
  value       = local.amazon_mq_enabled && length(aws_mq_broker.main) > 0 ? aws_mq_broker.main[0].instances[0].endpoints[0] : "N/A - Amazon MQ disabled"
}

output "msk_bootstrap_brokers" {
  description = "MSK Kafka bootstrap brokers"
  value       = local.msk_enabled && length(aws_msk_cluster.main) > 0 ? aws_msk_cluster.main[0].bootstrap_brokers_tls : "N/A - MSK disabled"
}

output "sqs_queue_urls" {
  description = "SQS queue URLs"
  value       = local.sqs_enabled ? { for k, v in aws_sqs_queue.app_queues : k => v.url } : {}
}

# Monitoring & Logging
output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = local.grafana_enabled ? "https://grafana.${local.apps_config.domain}" : "N/A - Grafana disabled"
}

output "prometheus_enabled" {
  description = "Prometheus monitoring status"
  value       = local.prometheus_enabled
}

output "loki_enabled" {
  description = "Loki logging status"
  value       = local.loki_enabled
}

output "opentelemetry_enabled" {
  description = "OpenTelemetry status"
  value       = local.opentelemetry_enabled
}

# Backup
output "velero_s3_bucket" {
  description = "Velero backup S3 bucket"
  value       = local.velero_enabled ? aws_s3_bucket.velero_backups[0].id : "N/A - Velero disabled"
}

# Internal Operators Status
output "internal_operators_status" {
  description = "Status of internal operators"
  value = {
    cloudnative_pg    = local.cloudnative_pg_enabled
    redis_operator    = local.redis_operator_enabled
    rabbitmq_operator = local.rabbitmq_operator_enabled
    mongodb_operator  = local.mongodb_operator_enabled
    strimzi_kafka     = local.strimzi_kafka_enabled
  }
}

# Passwords (Sensitive - stored in AWS Secrets Manager)
output "db_master_password" {
  description = "Database master password (also in Secrets Manager: prod/infraforge/db-master-password)"
  value       = random_password.db_master.result
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Grafana admin password (also in Secrets Manager: prod/infraforge/grafana-admin-password)"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "password_retrieval_commands" {
  description = "Commands to retrieve passwords from Secrets Manager"
  value = {
    db_password      = "aws secretsmanager get-secret-value --secret-id prod/infraforge/db-master-password --query SecretString --output text"
    grafana_password = "aws secretsmanager get-secret-value --secret-id prod/infraforge/grafana-admin-password --query SecretString --output text"
    mq_password      = local.amazon_mq_enabled ? "aws secretsmanager get-secret-value --secret-id prod/infraforge/mq-admin-password --query SecretString --output text" : "N/A - Amazon MQ disabled"
  }
}
