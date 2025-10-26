# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-db-subnet-group"
    }
  )
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.cluster_name}-rds-"
  description = "Security group for RDS instances"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "MySQL access from EKS nodes"
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
    description     = "PostgreSQL access from EKS nodes"
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
      Name = "${var.cluster_name}-rds-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# MySQL RDS Instance (only if needed)
resource "aws_db_instance" "mysql" {
  count = local.need_mysql ? 1 : 0

  identifier     = "${var.cluster_name}-mysql"
  engine         = "mysql"
  engine_version = local.apps_config.infrastructure.rds.mysql.engine_version
  instance_class = local.apps_config.infrastructure.rds.mysql.instance_class

  allocated_storage     = local.apps_config.infrastructure.rds.mysql.allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = local.apps_config.infrastructure.rds.mysql.allocated_storage * 2

  db_name  = "infraforge"
  username = var.db_username
  password = random_password.db_master.result

  multi_az               = local.apps_config.infrastructure.rds.mysql.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = local.apps_config.infrastructure.rds.mysql.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.cluster_name}-mysql-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  tags = merge(
    local.common_tags,
    {
      Name     = "${var.cluster_name}-mysql"
      Database = "mysql"
    }
  )
}

# PostgreSQL RDS Instance (only if needed)
resource "aws_db_instance" "postgresql" {
  count = local.need_postgresql ? 1 : 0

  identifier     = "${var.cluster_name}-postgresql"
  engine         = "postgres"
  engine_version = local.apps_config.infrastructure.rds.postgresql.engine_version
  instance_class = local.apps_config.infrastructure.rds.postgresql.instance_class

  allocated_storage     = local.apps_config.infrastructure.rds.postgresql.allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = local.apps_config.infrastructure.rds.postgresql.allocated_storage * 2

  db_name  = "infraforge"
  username = var.db_username
  password = random_password.db_master.result

  multi_az               = local.apps_config.infrastructure.rds.postgresql.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = local.apps_config.infrastructure.rds.postgresql.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.cluster_name}-postgresql-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(
    local.common_tags,
    {
      Name     = "${var.cluster_name}-postgresql"
      Database = "postgresql"
    }
  )
}

# Note: Database password must be provided in terraform.tfvars
# For security, we don't generate passwords automatically
