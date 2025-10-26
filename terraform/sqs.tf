# ============================================================================
# Amazon SQS (Simple Queue Service)
# ============================================================================

# SQS Queues for each enabled application
resource "aws_sqs_queue" "app_queues" {
  for_each = local.sqs_enabled ? local.enabled_apps : {}

  name                       = "${var.cluster_name}-${each.key}-queue"
  delay_seconds              = 0
  max_message_size           = 262144 # 256 KB
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 30

  # Dead Letter Queue
  redrive_policy = local.apps_config.infrastructure.sqs.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.app_dlq[each.key].arn
    maxReceiveCount     = 3
  }) : null

  # Encryption
  sqs_managed_sse_enabled = true

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.cluster_name}-${each.key}-queue"
      Application = each.key
    }
  )
}

# Dead Letter Queues (DLQ)
resource "aws_sqs_queue" "app_dlq" {
  for_each = local.sqs_enabled && local.apps_config.infrastructure.sqs.create_dlq ? local.enabled_apps : {}

  name                      = "${var.cluster_name}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.cluster_name}-${each.key}-dlq"
      Application = each.key
      Type        = "DeadLetterQueue"
    }
  )
}

# IAM Policy for EKS pods to access SQS
resource "aws_iam_policy" "sqs_access" {
  count = local.sqs_enabled ? 1 : 0

  name        = "${var.cluster_name}-sqs-access"
  description = "Allow EKS pods to access SQS queues"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          for queue in aws_sqs_queue.app_queues : queue.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ListQueues"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}
