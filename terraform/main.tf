# InfraForge GitOps Platform - Main Orchestrator
# This file orchestrates all infrastructure modules and ensures proper dependency order

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values for cross-module references
locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Module dependencies are managed through explicit depends_on where needed
# Order of operations:
# 1. VPC (vpc.tf)
# 2. EKS + RDS (eks.tf, rds.tf)
# 3. ECR Repositories (ecr.tf)
# 4. EKS Addons (addons.tf)
# 5. Route53 + ACM (route53.tf, acm.tf)
# 6. App Resources (app-resources.tf)
# 7. ArgoCD (argocd.tf)

# All module implementations are in their respective files:
# - vpc.tf: VPC, subnets, NAT, IGW, VPC endpoints
# - eks.tf: EKS cluster, node groups
# - rds.tf: RDS MySQL and PostgreSQL instances
# - ecr.tf: ECR repositories for all applications
# - addons.tf: EBS CSI, AWS LB Controller, ExternalDNS, Cluster Autoscaler, Metrics Server
# - route53.tf: Route53 zone data source
# - acm.tf: ACM wildcard certificate
# - app-resources.tf: Namespaces, secrets, configmaps for enabled apps
# - argocd.tf: ArgoCD installation and ApplicationSet
# - outputs.tf: All output values
