# Wildcard certificate for *.ticarethanem.net
resource "aws_acm_certificate" "wildcard" {
  count = local.acm_enabled ? 1 : 0

  domain_name       = "*.${local.apps_config.domain}"
  validation_method = "DNS"

  subject_alternative_names = [
    local.apps_config.domain # Root domain
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "wildcard-${local.apps_config.domain}"
    }
  )
}

# DNS validation records
resource "aws_route53_record" "cert_validation" {
  for_each = local.acm_enabled ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "wildcard" {
  count = local.acm_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "10m"
  }
}
