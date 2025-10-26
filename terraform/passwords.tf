# ============================================================================
# Random Passwords for Services
# ============================================================================
# These passwords are generated once and stored in Terraform state
# They can be retrieved from outputs or AWS Secrets Manager

# Database Master Password
resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
  # Exclude characters that might cause issues in connection strings
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
  min_special = 2
}

# Amazon MQ Admin Password
resource "random_password" "mq_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# Grafana Admin Password
resource "random_password" "grafana_admin" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 1
}

# ============================================================================
# Store Passwords in AWS Secrets Manager (Optional but Recommended)
# ============================================================================

# Database Password Secret
resource "aws_secretsmanager_secret" "db_password" {
  count = local.secrets_manager_enabled ? 1 : 0

  name        = "prod/infraforge/db-master-password"
  description = "RDS database master password"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  count = local.secrets_manager_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.db_password[0].id
  secret_string = random_password.db_master.result
}

# Amazon MQ Password Secret
resource "aws_secretsmanager_secret" "mq_password" {
  count = local.amazon_mq_enabled && local.secrets_manager_enabled ? 1 : 0

  name        = "prod/infraforge/mq-admin-password"
  description = "Amazon MQ admin password"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "mq_password" {
  count = local.amazon_mq_enabled && local.secrets_manager_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.mq_password[0].id
  secret_string = random_password.mq_admin.result
}

# Grafana Admin Password Secret
resource "aws_secretsmanager_secret" "grafana_password" {
  count = local.grafana_enabled && local.secrets_manager_enabled ? 1 : 0

  name        = "prod/infraforge/grafana-admin-password"
  description = "Grafana admin password"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "grafana_password" {
  count = local.grafana_enabled && local.secrets_manager_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.grafana_password[0].id
  secret_string = random_password.grafana_admin.result
}
