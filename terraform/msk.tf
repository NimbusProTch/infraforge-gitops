# ============================================================================
# Amazon MSK (Managed Streaming for Apache Kafka)
# ============================================================================

# Security Group for MSK
resource "aws_security_group" "msk" {
  count = local.msk_enabled ? 1 : 0

  name_prefix = "${var.cluster_name}-msk-"
  description = "Security group for MSK"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "Kafka plaintext access from EKS nodes"
  }

  ingress {
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "Kafka TLS access from EKS nodes"
  }

  ingress {
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "Zookeeper access from EKS nodes"
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
      Name = "${var.cluster_name}-msk-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# MSK Cluster
resource "aws_msk_cluster" "main" {
  count = local.msk_enabled ? 1 : 0

  cluster_name           = "${var.cluster_name}-kafka"
  kafka_version          = local.apps_config.infrastructure.msk.kafka_version
  number_of_broker_nodes = local.apps_config.infrastructure.msk.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = local.apps_config.infrastructure.msk.instance_type
    client_subnets  = module.vpc.private_subnets
    security_groups = [aws_security_group.msk[0].id]

    storage_info {
      ebs_storage_info {
        volume_size = local.apps_config.infrastructure.msk.ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
    encryption_at_rest_kms_key_arn = null # Use AWS managed key
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk[0].name
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-kafka"
    }
  )
}

# CloudWatch Log Group for MSK
resource "aws_cloudwatch_log_group" "msk" {
  count = local.msk_enabled ? 1 : 0

  name              = "/aws/msk/${var.cluster_name}-kafka"
  retention_in_days = 7

  tags = local.common_tags
}
