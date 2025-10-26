# ============================================================================
# Velero (Backup & Disaster Recovery)
# ============================================================================

# S3 Bucket for Velero Backups
resource "aws_s3_bucket" "velero_backups" {
  count = local.velero_enabled ? 1 : 0

  bucket = local.apps_config.infrastructure.backup.velero.s3_bucket

  tags = merge(
    local.common_tags,
    {
      Name    = local.apps_config.infrastructure.backup.velero.s3_bucket
      Purpose = "velero-backups"
    }
  )
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "velero_backups" {
  count = local.velero_enabled ? 1 : 0

  bucket = aws_s3_bucket.velero_backups[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "velero_backups" {
  count = local.velero_enabled ? 1 : 0

  bucket = aws_s3_bucket.velero_backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "velero_backups" {
  count = local.velero_enabled ? 1 : 0

  bucket = aws_s3_bucket.velero_backups[0].id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = local.apps_config.infrastructure.backup.velero.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "velero_backups" {
  count = local.velero_enabled ? 1 : 0

  bucket = aws_s3_bucket.velero_backups[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Policy for Velero
resource "aws_iam_policy" "velero" {
  count = local.velero_enabled ? 1 : 0

  name        = "${var.cluster_name}-velero"
  description = "IAM policy for Velero backup"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = "${aws_s3_bucket.velero_backups[0].arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.velero_backups[0].arn
      }
    ]
  })

  tags = local.common_tags
}

# IRSA for Velero
module "velero_irsa" {
  count   = local.velero_enabled ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-velero"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["velero:velero"]
    }
  }

  role_policy_arns = {
    velero = aws_iam_policy.velero[0].arn
  }

  tags = local.common_tags
}

# Namespace for Velero
resource "kubernetes_namespace" "velero" {
  count = local.velero_enabled ? 1 : 0

  metadata {
    name = "velero"

    labels = {
      "app.kubernetes.io/name"       = "velero"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# Velero Helm Release
resource "helm_release" "velero" {
  count = local.velero_enabled ? 1 : 0

  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  namespace  = kubernetes_namespace.velero[0].metadata[0].name
  version    = "5.2.0"

  values = [yamlencode({
    initContainers = [{
      name  = "velero-plugin-for-aws"
      image = "velero/velero-plugin-for-aws:v1.9.0"
      volumeMounts = [{
        mountPath = "/target"
        name      = "plugins"
      }]
    }]

    configuration = {
      provider = "aws"
      backupStorageLocation = {
        bucket = aws_s3_bucket.velero_backups[0].id
        config = {
          region = var.aws_region
        }
      }
      volumeSnapshotLocation = {
        config = {
          region = var.aws_region
        }
      }
    }

    serviceAccount = {
      server = {
        create = true
        name   = "velero"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.velero_irsa[0].iam_role_arn
        }
      }
    }

    # Backup schedules
    schedules = {
      daily = {
        disabled = false
        schedule = local.apps_config.infrastructure.backup.velero.backup_schedule
        template = {
          ttl                = "${local.apps_config.infrastructure.backup.velero.retention_days * 24}h"
          includedNamespaces = ["*"]
          excludedNamespaces = ["kube-system", "kube-public", "kube-node-lease"]
        }
      }
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

    metrics = {
      enabled = local.prometheus_enabled
      serviceMonitor = {
        enabled = local.prometheus_enabled
      }
    }
  })]

  depends_on = [
    module.eks,
    kubernetes_namespace.velero,
    aws_s3_bucket.velero_backups,
    module.velero_irsa
  ]

  timeout = 600
}
