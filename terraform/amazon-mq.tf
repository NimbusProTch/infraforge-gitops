# ============================================================================
# Amazon MQ (Managed RabbitMQ/ActiveMQ)
# ============================================================================

# Security Group for Amazon MQ
resource "aws_security_group" "amazon_mq" {
  count = local.amazon_mq_enabled ? 1 : 0

  name_prefix = "${var.cluster_name}-amazon-mq-"
  description = "Security group for Amazon MQ"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "AMQPS access from EKS nodes"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "HTTPS (Web Console) access from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-amazon-mq-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Amazon MQ Broker
resource "aws_mq_broker" "main" {
  count = local.amazon_mq_enabled ? 1 : 0

  broker_name        = "${var.cluster_name}-mq"
  engine_type        = local.apps_config.infrastructure.amazon_mq.engine_type
  engine_version     = local.apps_config.infrastructure.amazon_mq.engine_version
  host_instance_type = local.apps_config.infrastructure.amazon_mq.host_instance_type
  deployment_mode    = local.apps_config.infrastructure.amazon_mq.deployment_mode

  subnet_ids          = local.apps_config.infrastructure.amazon_mq.deployment_mode == "SINGLE_INSTANCE" ? [module.vpc.private_subnets[0]] : [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
  security_groups     = [aws_security_group.amazon_mq[0].id]
  publicly_accessible = false

  # Authentication
  user {
    username = var.mq_username
    password = random_password.mq_admin.result
  }

  # Logging
  logs {
    general = true
    audit   = false
  }

  # Maintenance
  maintenance_window_start_time {
    day_of_week = "SUNDAY"
    time_of_day = "05:00"
    time_zone   = "UTC"
  }

  # Encryption
  encryption_options {
    use_aws_owned_key = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-mq"
    }
  )
}
