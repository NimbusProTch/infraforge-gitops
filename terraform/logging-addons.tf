# ============================================================================
# Loki Stack (Log Aggregation)
# ============================================================================

# Namespace for Logging
resource "kubernetes_namespace" "logging" {
  count = local.loki_enabled || local.opentelemetry_enabled ? 1 : 0

  metadata {
    name = "logging"

    labels = {
      "app.kubernetes.io/name"       = "logging"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# Loki Helm Release
resource "helm_release" "loki" {
  count = local.loki_enabled ? 1 : 0

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.logging[0].metadata[0].name
  version    = "5.41.4"

  values = [yamlencode({
    loki = {
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        type = "filesystem"
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v12"
          index = {
            prefix = "index_"
            period = "24h"
          }
        }]
      }
      limits_config = {
        retention_period = "${local.apps_config.infrastructure.logging.loki.retention_days}d"
      }
    }

    singleBinary = {
      replicas = 1
      persistence = {
        enabled      = true
        size         = local.apps_config.infrastructure.logging.loki.storage_size
        storageClass = "gp3"
      }
      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }
    }

    monitoring = {
      selfMonitoring = {
        enabled = true
        grafanaAgent = {
          installOperator = false
        }
      }
      serviceMonitor = {
        enabled = local.prometheus_enabled
      }
    }

    test = {
      enabled = false
    }
  })]

  depends_on = [
    module.eks,
    kubernetes_namespace.logging
  ]

  timeout = 600
}

# Promtail (Log shipper for Loki)
resource "helm_release" "promtail" {
  count = local.loki_enabled ? 1 : 0

  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  namespace  = kubernetes_namespace.logging[0].metadata[0].name
  version    = "6.15.3"

  values = [yamlencode({
    config = {
      clients = [{
        url = "http://loki:3100/loki/api/v1/push"
      }]
    }

    resources = {
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "200m"
        memory = "256Mi"
      }
    }

    # DaemonSet to collect logs from all nodes
    tolerations = [{
      effect   = "NoSchedule"
      operator = "Exists"
    }]
  })]

  depends_on = [
    module.eks,
    kubernetes_namespace.logging,
    helm_release.loki
  ]
}

# ============================================================================
# OpenTelemetry Collector (Traces, Logs, Metrics)
# ============================================================================

# Namespace for OpenTelemetry
resource "kubernetes_namespace" "opentelemetry" {
  count = local.opentelemetry_enabled ? 1 : 0

  metadata {
    name = "opentelemetry"

    labels = {
      "app.kubernetes.io/name"       = "opentelemetry"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# OpenTelemetry Operator
resource "helm_release" "opentelemetry_operator" {
  count = local.opentelemetry_enabled ? 1 : 0

  name       = "opentelemetry-operator"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  namespace  = kubernetes_namespace.opentelemetry[0].metadata[0].name
  version    = "0.47.1"

  set {
    name  = "manager.collectorImage.repository"
    value = "otel/opentelemetry-collector-contrib"
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.opentelemetry,
    helm_release.cert_manager  # cert-manager must be installed first for CRDs
  ]
}

# OpenTelemetry Collector (via kubectl manifest after operator is ready)
resource "kubectl_manifest" "otel_collector" {
  count = local.opentelemetry_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "opentelemetry.io/v1alpha1"
    kind       = "OpenTelemetryCollector"
    metadata = {
      name      = "otel-collector"
      namespace = kubernetes_namespace.opentelemetry[0].metadata[0].name
    }
    spec = {
      mode = "deployment"
      config = yamlencode({
        receivers = {
          otlp = {
            protocols = {
              grpc = {}
              http = {}
            }
          }
          # Prometheus receiver for metrics
          prometheus = local.apps_config.infrastructure.logging.opentelemetry.metrics_enabled ? {
            config = {
              scrape_configs = [{
                job_name        = "otel-collector"
                scrape_interval = "30s"
                static_configs = [{
                  targets = ["localhost:8888"]
                }]
              }]
            }
          } : null
        }

        processors = {
          batch = {}
          memory_limiter = {
            check_interval  = "1s"
            limit_mib       = 512
            spike_limit_mib = 128
          }
        }

        exporters = {
          # Prometheus exporter for metrics
          prometheus = local.apps_config.infrastructure.logging.opentelemetry.metrics_enabled && local.prometheus_enabled ? {
            endpoint = "0.0.0.0:8889"
          } : null

          # Loki exporter for logs
          loki = local.apps_config.infrastructure.logging.opentelemetry.logs_enabled && local.loki_enabled ? {
            endpoint = "http://loki.logging.svc.cluster.local:3100/loki/api/v1/push"
          } : null

          # Jaeger exporter for traces (can be replaced with Tempo)
          otlp = local.apps_config.infrastructure.logging.opentelemetry.traces_enabled ? {
            endpoint = "jaeger-collector.opentelemetry.svc.cluster.local:4317"
            tls = {
              insecure = true
            }
          } : null

          # Logging exporter for debugging
          logging = {
            loglevel = "info"
          }
        }

        service = {
          pipelines = merge(
            local.apps_config.infrastructure.logging.opentelemetry.traces_enabled ? {
              traces = {
                receivers  = ["otlp"]
                processors = ["memory_limiter", "batch"]
                exporters  = ["otlp", "logging"]
              }
            } : {},
            local.apps_config.infrastructure.logging.opentelemetry.metrics_enabled ? {
              metrics = {
                receivers  = ["otlp", "prometheus"]
                processors = ["memory_limiter", "batch"]
                exporters = concat(
                  local.prometheus_enabled ? ["prometheus"] : [],
                  ["logging"]
                )
              }
            } : {},
            local.apps_config.infrastructure.logging.opentelemetry.logs_enabled ? {
              logs = {
                receivers  = ["otlp"]
                processors = ["memory_limiter", "batch"]
                exporters = concat(
                  local.loki_enabled ? ["loki"] : [],
                  ["logging"]
                )
              }
            } : {}
          )
        }
      })

      resources = {
        limits = {
          cpu    = "500m"
          memory = "1Gi"
        }
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
      }
    }
  })

  depends_on = [
    helm_release.opentelemetry_operator,
    helm_release.loki
  ]
}

# Jaeger for Trace Visualization (optional, lightweight)
resource "helm_release" "jaeger" {
  count = local.opentelemetry_enabled && local.apps_config.infrastructure.logging.opentelemetry.traces_enabled ? 1 : 0

  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  namespace  = kubernetes_namespace.opentelemetry[0].metadata[0].name
  version    = "0.71.12"

  values = [yamlencode({
    provisionDataStore = {
      cassandra = false
    }
    allInOne = {
      enabled = true
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
    }
    storage = {
      type = "memory"
    }
    agent = {
      enabled = false
    }
    collector = {
      enabled = false
    }
    query = {
      enabled = false
    }
  })]

  depends_on = [
    module.eks,
    kubernetes_namespace.opentelemetry
  ]
}
