# Infrastructure Components

Bu döküman InfraForge GitOps Platform'daki tüm infrastructure bileşenlerini açıklar.

## 📋 İçindekiler

- [AWS Managed Services (External)](#aws-managed-services-external)
- [Secrets Management](#secrets-management)
- [Monitoring Stack](#monitoring-stack)
- [Logging & Tracing Stack](#logging--tracing-stack)
- [Backup & Disaster Recovery](#backup--disaster-recovery)
- [Internal Operators (EKS içinde)](#internal-operators-eks-içinde)

---

## AWS Managed Services (External)

### 🗄️ RDS (Relational Database Service)

**Amaç:** Managed MySQL ve PostgreSQL veritabanları

**Enable/Disable:**
```yaml
infrastructure:
  rds:
    mysql:
      enabled: true  # MySQL'i aç/kapat
    postgresql:
      enabled: true  # PostgreSQL'i aç/kapat
```

**Özellikler:**
- ✅ Multi-AZ support (HA)
- ✅ Automated backups
- ✅ Encryption at rest
- ✅ Monitoring integration
- ✅ Auto-scaling storage

**Maliyet:** ~$15-30/month (db.t3.micro)

---

### 🔴 ElastiCache (Redis/Memcached)

**Amaç:** Managed cache layer

**Enable/Disable:**
```yaml
infrastructure:
  elasticache:
    enabled: false  # Varsayılan: disabled
    engine: "redis"
    node_type: "cache.t3.micro"
```

**Kullanım Senaryoları:**
- Session store
- API response caching
- Rate limiting
- Real-time analytics

**Maliyet:** ~$12-25/month (cache.t3.micro)

---

### 🐰 Amazon MQ (RabbitMQ/ActiveMQ)

**Amaç:** Managed message broker

**Enable/Disable:**
```yaml
infrastructure:
  amazon_mq:
    enabled: false  # Varsayılan: disabled
    engine_type: "RabbitMQ"
    host_instance_type: "mq.t3.micro"
```

**Kullanım Senaryoları:**
- Async messaging
- Event-driven architecture
- Task queues
- Microservice communication

**Maliyet:** ~$65/month (mq.t3.micro single instance)

---

### 📨 MSK (Managed Streaming for Kafka)

**Amaç:** Managed Apache Kafka

**Enable/Disable:**
```yaml
infrastructure:
  msk:
    enabled: false  # Varsayılan: disabled
    kafka_version: "3.5.1"
    instance_type: "kafka.t3.small"
```

**Kullanım Senaryoları:**
- Event streaming
- Log aggregation
- Real-time analytics
- Change data capture (CDC)

**Maliyet:** ~$150/month (3x kafka.t3.small)

---

### 📬 SQS (Simple Queue Service)

**Amaç:** Managed message queues

**Enable/Disable:**
```yaml
infrastructure:
  sqs:
    enabled: false  # Varsayılan: disabled
    create_dlq: true  # Dead Letter Queue
```

**Kullanım Senaryoları:**
- Decoupling microservices
- Background job processing
- Load leveling
- Fan-out patterns

**Maliyet:** Pay-per-use (~$0.40 per million requests)

---

## Secrets Management

### 🔐 External Secrets Operator

**Amaç:** AWS Secrets Manager'dan secret'ları Kubernetes'e sync eder

**Enable/Disable:**
```yaml
infrastructure:
  external_secrets:
    enabled: true  # Varsayılan: enabled
    secrets_manager:
      enabled: true
```

**Kullanım:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  secretStoreRef:
    name: aws-secretsmanager
  target:
    name: app-credentials
  data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: prod/db/password
```

**Avantajlar:**
- ✅ Merkezi secret yönetimi
- ✅ Rotation support
- ✅ Audit logging
- ✅ No secrets in Git

---

## Monitoring Stack

### 📊 Prometheus + Grafana

**Amaç:** Metrics collection ve visualization

**Enable/Disable:**
```yaml
infrastructure:
  monitoring:
    prometheus:
      enabled: true  # Metrics collection
      retention: "15d"
      storage_size: "50Gi"
    grafana:
      enabled: true  # Dashboard
      admin_password: "admin"
    alertmanager:
      enabled: true  # Alerting
```

**Özellikler:**
- ✅ Automatic service discovery
- ✅ Pre-configured dashboards
- ✅ AlertManager integration
- ✅ ServiceMonitor CRDs
- ✅ Persistent storage

**Erişim:**
- Grafana: `https://grafana.ticarethanem.net`
- Prometheus: ClusterIP (internal only)

**Dashboards:**
- Kubernetes cluster metrics
- Node metrics
- Pod metrics
- Application metrics (custom)

---

## Logging & Tracing Stack

### 📝 Loki (Log Aggregation)

**Amaç:** Centralized logging

**Enable/Disable:**
```yaml
infrastructure:
  logging:
    loki:
      enabled: true
      retention_days: 30
      storage_size: "100Gi"
```

**Özellikler:**
- ✅ Label-based log indexing
- ✅ Grafana integration
- ✅ LogQL query language
- ✅ Persistent storage
- ✅ Promtail log shipper (DaemonSet)

**Kullanım:**
Grafana'da Loki data source üzerinden log sorgulama:
```logql
{namespace="smk"} |= "error"
```

---

### 🔭 OpenTelemetry Collector

**Amaç:** Traces, logs ve metrics collection

**Enable/Disable:**
```yaml
infrastructure:
  logging:
    opentelemetry:
      enabled: true
      traces_enabled: true
      logs_enabled: true
      metrics_enabled: true
```

**Özellikler:**
- ✅ OTLP protocol support
- ✅ Jaeger integration (tracing)
- ✅ Loki export (logs)
- ✅ Prometheus export (metrics)
- ✅ Vendor-neutral

**Instrumentation:**
App'lerinizde OpenTelemetry SDK kullanın:
```javascript
// Node.js example
const { trace } = require('@opentelemetry/api');
const tracer = trace.getTracer('my-app');

const span = tracer.startSpan('processRequest');
// ... process request
span.end();
```

---

## Backup & Disaster Recovery

### 💾 Velero

**Amaç:** Kubernetes cluster backup

**Enable/Disable:**
```yaml
infrastructure:
  backup:
    velero:
      enabled: true
      s3_bucket: "infraforge-velero-backups"
      backup_schedule: "0 2 * * *"  # Daily 02:00
      retention_days: 30
```

**Özellikler:**
- ✅ Automated daily backups
- ✅ S3 storage
- ✅ Namespace-level backups
- ✅ PV snapshots (EBS)
- ✅ Disaster recovery

**Kullanım:**
```bash
# Manual backup
velero backup create manual-backup --include-namespaces smk

# Restore
velero restore create --from-backup manual-backup

# List backups
velero backup get
```

---

## Internal Operators (EKS içinde)

### 🐘 CloudNativePG Operator

**Amaç:** PostgreSQL cluster management (EKS içinde)

**Enable/Disable:**
```yaml
infrastructure:
  internal_operators:
    cloudnative_pg:
      enabled: false  # Varsayılan: disabled
      default_instances: 3
      storage_size: "10Gi"
```

**Kullanım:**
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: smk-postgres
spec:
  instances: 3
  storage:
    size: 10Gi
  postgresql:
    parameters:
      max_connections: "100"
```

**Avantajlar:**
- ✅ High availability (3 replicas)
- ✅ Automatic failover
- ✅ Backup integration
- ✅ Maliyet: RDS'den ~%60 daha ucuz

---

### 🔴 Redis Operator

**Amaç:** Redis cluster management (EKS içinde)

**Enable/Disable:**
```yaml
infrastructure:
  internal_operators:
    redis_operator:
      enabled: false
      default_replicas: 3
```

**Kullanım:**
```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: Redis
metadata:
  name: smk-redis
spec:
  kubernetesConfig:
    image: redis:7.0
  redisExporter:
    enabled: true
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
```

**Avantajlar:**
- ✅ Master-slave replication
- ✅ Sentinel mode
- ✅ Maliyet: ElastiCache'den ~%70 daha ucuz

---

### 🐰 RabbitMQ Cluster Operator

**Amaç:** RabbitMQ cluster management (EKS içinde)

**Enable/Disable:**
```yaml
infrastructure:
  internal_operators:
    rabbitmq_operator:
      enabled: false
      default_replicas: 3
```

**Kullanım:**
```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: smk-rabbitmq
spec:
  replicas: 3
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
```

**Avantajlar:**
- ✅ Quorum queues
- ✅ Mirrored queues
- ✅ Maliyet: Amazon MQ'dan ~%80 daha ucuz

---

### 🍃 MongoDB Community Operator

**Amaç:** MongoDB replica set management (EKS içinde)

**Enable/Disable:**
```yaml
infrastructure:
  internal_operators:
    mongodb_operator:
      enabled: false
      default_replicas: 3
```

**Kullanım:**
```yaml
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: smk-mongodb
spec:
  members: 3
  type: ReplicaSet
  version: "6.0.5"
  security:
    authentication:
      modes: ["SCRAM"]
  users:
    - name: app-user
      db: admin
      passwordSecretRef:
        name: app-user-password
```

---

### 📨 Strimzi Kafka Operator

**Amaç:** Kafka cluster management (EKS içinde)

**Enable/Disable:**
```yaml
infrastructure:
  internal_operators:
    strimzi_kafka:
      enabled: false
      default_replicas: 3
      zookeeper_replicas: 3
```

**Kullanım:**
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: smk-kafka
spec:
  kafka:
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    storage:
      type: jbod
      volumes:
      - id: 0
        type: persistent-claim
        size: 50Gi
  zookeeper:
    replicas: 3
    storage:
      type: persistent-claim
      size: 10Gi
```

**Avantajlar:**
- ✅ Full Kafka ecosystem
- ✅ Kafka Connect support
- ✅ Schema Registry
- ✅ Maliyet: MSK'dan ~%75 daha ucuz

---

## 💰 Maliyet Karşılaştırması

| Component | AWS Managed | Internal Operator | Savings |
|-----------|-------------|-------------------|---------|
| PostgreSQL | RDS: $15/mo | CloudNativePG: $6/mo | 60% |
| Redis | ElastiCache: $12/mo | Redis Operator: $3.6/mo | 70% |
| RabbitMQ | Amazon MQ: $65/mo | RabbitMQ Operator: $13/mo | 80% |
| Kafka | MSK: $150/mo | Strimzi: $37.5/mo | 75% |

**Not:** Internal operator'lar EKS node maliyetine eklenir ancak yine de çok daha ucuzdur.

---

## 🎯 Öneri: Hangi Seçeneği Kullanmalıyım?

### AWS Managed Services Kullan (External):
- ✅ Production-critical database'ler (RDS)
- ✅ Minimum ops overhead istiyorsanız
- ✅ AWS support'u gerekiyorsa
- ✅ Compliance gereksinimleri varsa

### Internal Operators Kullan (EKS içinde):
- ✅ Maliyet optimizasyonu kritikse
- ✅ Kubernetes native tools tercih ediyorsanız
- ✅ Development/staging environment'lar
- ✅ Tam kontrol istiyorsanız

### Hybrid Approach (Önerilen):
```yaml
# Production
rds.postgresql.enabled: true      # Critical data
elasticache.enabled: true         # High performance cache

# Development/Staging
internal_operators:
  cloudnative_pg.enabled: true    # Dev databases
  redis_operator.enabled: true    # Dev cache
```

---

## 🔍 Monitoring ve Alerting

Tüm bileşenler Prometheus + Grafana ile entegre:

- **ServiceMonitor:** Her operator otomatik metric export eder
- **Dashboards:** Pre-configured Grafana dashboards
- **Alerts:** Critical alerts için AlertManager

---

## 📚 İlgili Dökümanlar

- [Setup Guide](../SETUP_GUIDE.md)
- [Architecture](./architecture.md)
- [Troubleshooting](./troubleshooting.md)
- [GitHub Actions CI/CD](../.github/workflows/README.md)
