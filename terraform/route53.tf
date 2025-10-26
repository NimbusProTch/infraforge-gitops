# Route53 hosted zone (data source - assuming zone already exists)
data "aws_route53_zone" "main" {
  count = local.route53_enabled ? 1 : 0

  name         = "${local.apps_config.domain}."
  private_zone = false
}

# Note: DNS records for applications (including ArgoCD) will be created automatically
# by ExternalDNS based on ingress annotations. No manual Route53 records needed.
