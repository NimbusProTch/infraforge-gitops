# ============================================================================
# ElastiCache (Redis/Memcached)
# ============================================================================

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  count = local.elasticache_enabled ? 1 : 0

  name       = "${var.cluster_name}-elasticache-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-elasticache-subnet-group"
    }
  )
}

# Security Group for ElastiCache
resource "aws_security_group" "elasticache" {
  count = local.elasticache_enabled ? 1 : 0

  name_prefix = "${var.cluster_name}-elasticache-"
  description = "Security group for ElastiCache"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "Redis access from EKS nodes"
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
      Name = "${var.cluster_name}-elasticache-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ElastiCache Replication Group (Redis)
resource "aws_elasticache_replication_group" "redis" {
  count = local.elasticache_enabled && local.apps_config.infrastructure.elasticache.engine == "redis" ? 1 : 0

  replication_group_id = "${var.cluster_name}-redis"
  description          = "Redis cluster for ${var.cluster_name}"

  engine               = "redis"
  engine_version       = local.apps_config.infrastructure.elasticache.engine_version
  node_type            = local.apps_config.infrastructure.elasticache.node_type
  num_cache_clusters   = local.apps_config.infrastructure.elasticache.num_cache_nodes
  parameter_group_name = local.apps_config.infrastructure.elasticache.parameter_group_family

  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main[0].name
  security_group_ids         = [aws_security_group.elasticache[0].id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  automatic_failover_enabled = local.apps_config.infrastructure.elasticache.num_cache_nodes > 1

  # Maintenance and backup
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_window          = "03:00-04:00"
  snapshot_retention_limit = 7

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-redis"
    }
  )
}
