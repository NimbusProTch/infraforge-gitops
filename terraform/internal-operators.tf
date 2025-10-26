# ============================================================================
# CloudNativePG Operator (PostgreSQL)
# ============================================================================

# Namespace for CloudNativePG
resource "kubernetes_namespace" "cloudnative_pg" {
  count = local.cloudnative_pg_enabled ? 1 : 0

  metadata {
    name = "cnpg-system"

    labels = {
      "app.kubernetes.io/name"       = "cloudnativepg"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# CloudNativePG Operator Helm Release
resource "helm_release" "cloudnative_pg" {
  count = local.cloudnative_pg_enabled ? 1 : 0

  name       = "cloudnative-pg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  namespace  = kubernetes_namespace.cloudnative_pg[0].metadata[0].name
  version    = "0.20.0"

  set {
    name  = "monitoring.podMonitorEnabled"
    value = local.prometheus_enabled
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.cloudnative_pg
  ]
}

# ============================================================================
# Redis Operator
# ============================================================================

# Namespace for Redis Operator
resource "kubernetes_namespace" "redis_operator" {
  count = local.redis_operator_enabled ? 1 : 0

  metadata {
    name = "redis-operator"

    labels = {
      "app.kubernetes.io/name"       = "redis-operator"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# Redis Operator Helm Release
resource "helm_release" "redis_operator" {
  count = local.redis_operator_enabled ? 1 : 0

  name       = "redis-operator"
  repository = "https://ot-container-kit.github.io/helm-charts"
  chart      = "redis-operator"
  namespace  = kubernetes_namespace.redis_operator[0].metadata[0].name
  version    = "0.15.1"

  set {
    name  = "redisOperator.watchNamespace"
    value = "" # Watch all namespaces
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.redis_operator
  ]
}

# ============================================================================
# RabbitMQ Cluster Operator
# ============================================================================

# Namespace for RabbitMQ Operator
resource "kubernetes_namespace" "rabbitmq_operator" {
  count = local.rabbitmq_operator_enabled ? 1 : 0

  metadata {
    name = "rabbitmq-system"

    labels = {
      "app.kubernetes.io/name"       = "rabbitmq-operator"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# RabbitMQ Cluster Operator Helm Release
resource "helm_release" "rabbitmq_operator" {
  count = local.rabbitmq_operator_enabled ? 1 : 0

  name       = "rabbitmq-cluster-operator"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq-cluster-operator"
  namespace  = kubernetes_namespace.rabbitmq_operator[0].metadata[0].name
  version    = "3.12.1"

  set {
    name  = "clusterOperator.watchAllNamespaces"
    value = "true"
  }

  set {
    name  = "clusterOperator.metrics.enabled"
    value = local.prometheus_enabled
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.rabbitmq_operator
  ]
}

# ============================================================================
# MongoDB Community Operator
# ============================================================================

# Namespace for MongoDB Operator
resource "kubernetes_namespace" "mongodb_operator" {
  count = local.mongodb_operator_enabled ? 1 : 0

  metadata {
    name = "mongodb"

    labels = {
      "app.kubernetes.io/name"       = "mongodb-operator"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# MongoDB Community Operator Helm Release
resource "helm_release" "mongodb_operator" {
  count = local.mongodb_operator_enabled ? 1 : 0

  name       = "mongodb-kubernetes-operator"
  repository = "https://mongodb.github.io/helm-charts"
  chart      = "community-operator"
  namespace  = kubernetes_namespace.mongodb_operator[0].metadata[0].name
  version    = "0.9.0"

  set {
    name  = "operator.watchNamespace"
    value = "*" # Watch all namespaces
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.mongodb_operator
  ]
}

# ============================================================================
# Strimzi Kafka Operator
# ============================================================================

# Namespace for Strimzi Kafka Operator
resource "kubernetes_namespace" "strimzi_kafka" {
  count = local.strimzi_kafka_enabled ? 1 : 0

  metadata {
    name = "kafka"

    labels = {
      "app.kubernetes.io/name"       = "strimzi-kafka"
      "app.kubernetes.io/managed-by" = "opentofu"
    }
  }

  depends_on = [module.eks]
}

# Strimzi Kafka Operator Helm Release
resource "helm_release" "strimzi_kafka" {
  count = local.strimzi_kafka_enabled ? 1 : 0

  name       = "strimzi-kafka-operator"
  repository = "https://strimzi.io/charts"
  chart      = "strimzi-kafka-operator"
  namespace  = kubernetes_namespace.strimzi_kafka[0].metadata[0].name
  version    = "0.39.0"

  set {
    name  = "watchAnyNamespace"
    value = "true"
  }

  set {
    name  = "generateNetworkPolicy"
    value = "false"
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.strimzi_kafka
  ]
}
