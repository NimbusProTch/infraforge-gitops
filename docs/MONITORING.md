# Monitoring & Observability Guide

## Overview

InfraForge GitOps comes with a complete observability stack:
- **Prometheus** - Metrics collection
- **Grafana** - Visualization & dashboards
- **Alertmanager** - Alert routing & notifications
- **Jaeger** - Distributed tracing
- **OpenTelemetry** - Instrumentation framework

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Application  │────▶│ OTel         │────▶│ Prometheus   │
│ Metrics      │     │ Collector    │     │ (Storage)    │
└──────────────┘     └──────────────┘     └──────────────┘
                              │                    │
                              │                    │
                              ▼                    ▼
                     ┌──────────────┐     ┌──────────────┐
                     │ Jaeger       │     │ Grafana      │
                     │ (Traces)     │     │ (Dashboards) │
                     └──────────────┘     └──────────────┘
                              │                    │
                              │                    │
                              └────────┬───────────┘
                                       │
                                       ▼
                              ┌──────────────┐
                              │ Alertmanager │
                              │ (Alerts)     │
                              └──────────────┘
```

## Accessing Monitoring Tools

### Grafana
```bash
# Access Grafana UI
make grafana-ui

# Opens at: http://localhost:3000
# Username: admin
# Password: Retrieve from AWS Secrets Manager
```

### Prometheus
```bash
# Access Prometheus UI
make prometheus-ui

# Opens at: http://localhost:9090
```

### Jaeger (Tracing)
```bash
# Port-forward Jaeger UI
kubectl port-forward -n opentelemetry svc/jaeger-query 16686:16686

# Opens at: http://localhost:16686
```

## Application Instrumentation

### Automatic Instrumentation

All applications deployed via our template automatically get:

1. **Prometheus Annotations**
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

2. **OpenTelemetry Environment Variables**
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://opentelemetry-collector.opentelemetry:4317"
  - name: OTEL_SERVICE_NAME
    value: "your-app-name"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=production,service.version=v1.0.0"
```

### Manual Instrumentation

#### Go Application
```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
)

func main() {
    // Initialize OTEL tracer
    ctx := context.Background()
    exporter, _ := otlptracegrpc.New(ctx)

    // Your application code
}
```

#### Node.js Application
```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const provider = new NodeTracerProvider();
provider.addSpanProcessor(new BatchSpanProcessor(new OTLPTraceExporter()));
provider.register();
```

#### Python Application
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

trace.set_tracer_provider(TracerProvider())
span_processor = BatchSpanProcessor(OTLPSpanExporter())
trace.get_tracer_provider().add_span_processor(span_processor)
```

## Key Metrics to Monitor

### Application Metrics

```promql
# Request Rate (RPS)
rate(http_requests_total[5m])

# Request Duration (Latency)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error Rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Saturation (CPU)
avg(rate(container_cpu_usage_seconds_total[5m])) by (pod)

# Saturation (Memory)
container_memory_usage_bytes / container_spec_memory_limit_bytes
```

### Infrastructure Metrics

```promql
# Node CPU Usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node Memory Usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk Usage
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Pod Restarts
rate(kube_pod_container_status_restarts_total[15m])
```

### Kubernetes Metrics

```promql
# Pod Count
count(kube_pod_info) by (namespace)

# Deployment Availability
kube_deployment_status_replicas_available / kube_deployment_spec_replicas

# PVC Usage
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100
```

## Grafana Dashboards

### Pre-installed Dashboards

1. **Kubernetes Cluster Overview**
   - Node health
   - Pod status
   - Resource usage

2. **Application Dashboard**
   - Request rate
   - Latency (p50, p95, p99)
   - Error rate

3. **Database Dashboard** (CloudNativePG)
   - Connection pool
   - Query performance
   - Replication lag

4. **Kafka Dashboard** (Strimzi)
   - Topic metrics
   - Consumer lag
   - Broker health

### Creating Custom Dashboard

```bash
# 1. Create dashboard in Grafana UI
# 2. Export as JSON
# 3. Save to: monitoring/dashboards/my-dashboard.json
# 4. Commit to Git
# 5. Apply via ConfigMap
```

## Alerting

### Alert Rules

Create alert rules in `monitoring/alerts/`:

```yaml
# monitoring/alerts/app-alerts.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-alerts
  namespace: monitoring
data:
  app-alerts.yaml: |
    groups:
    - name: application
      interval: 30s
      rules:
      # High Error Rate
      - alert: HighErrorRate
        expr: |
          (rate(http_requests_total{status=~"5.."}[5m])
          / rate(http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "{{ $labels.service }} has error rate > 5%"

      # High Latency
      - alert: HighLatency
        expr: |
          histogram_quantile(0.95,
            rate(http_request_duration_seconds_bucket[5m])
          ) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency detected"
          description: "{{ $labels.service }} p95 latency > 1s"

      # Pod Not Ready
      - alert: PodNotReady
        expr: kube_pod_status_phase{phase!="Running"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod not ready"
          description: "{{ $labels.pod }} in {{ $labels.namespace }} is not running"

      # High Memory Usage
      - alert: HighMemoryUsage
        expr: |
          (container_memory_usage_bytes
          / container_spec_memory_limit_bytes) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "{{ $labels.pod }} using > 90% memory"

      # High CPU Usage
      - alert: HighCPUUsage
        expr: |
          (rate(container_cpu_usage_seconds_total[5m])
          / container_spec_cpu_quota * 100000) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage"
          description: "{{ $labels.pod }} using > 80% CPU"
```

### Notification Channels

Configure Alertmanager to send alerts:

```yaml
# monitoring/alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m

    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'pagerduty'
      - match:
          severity: warning
        receiver: 'slack'

    receivers:
    - name: 'default'
      webhook_configs:
      - url: 'http://example.com/webhook'

    - name: 'slack'
      slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

    - name: 'pagerduty'
      pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'
```

## Best Practices

### 1. Four Golden Signals

Monitor these for every service:

- **Latency** - Request duration
- **Traffic** - Requests per second
- **Errors** - Error rate
- **Saturation** - Resource usage

### 2. SLIs & SLOs

Define Service Level Indicators and Objectives:

```yaml
# SLI: Request Success Rate
# SLO: 99.9% of requests succeed
(1 - (rate(http_requests_total{status=~"5.."}[30d])
     / rate(http_requests_total[30d]))) * 100 > 99.9

# SLI: Request Latency
# SLO: 95% of requests < 100ms
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket[5m])
) < 0.1
```

### 3. Alert Severity Levels

- **Critical**: Production down, immediate action
- **Warning**: Degraded performance, investigate soon
- **Info**: Notable events, no action needed

### 4. Alert Naming Convention

```
<Severity><Component><Issue>
Examples:
- CriticalDatabaseDown
- WarningHighErrorRate
- InfoDeploymentStarted
```

### 5. Runbooks

Link alerts to runbooks:

```yaml
annotations:
  summary: "High error rate detected"
  description: "{{ $labels.service }} has error rate > 5%"
  runbook_url: "https://wiki.example.com/runbooks/high-error-rate"
```

## Distributed Tracing

### View Traces in Jaeger

1. Access Jaeger UI: `http://localhost:16686`
2. Select service from dropdown
3. Filter by:
   - Time range
   - Min/Max duration
   - Tags
   - Errors only

### Understanding Traces

```
Trace: User Request Flow
│
├─ [frontend] GET /api/users (150ms)
│  │
│  ├─ [api-gateway] Route request (10ms)
│  │  │
│  │  ├─ [user-service] GET /users (100ms)
│  │  │  │
│  │  │  ├─ [database] SELECT * FROM users (80ms)
│  │  │  └─ [cache] GET user:* (5ms)
│  │  │
│  │  └─ [auth-service] Validate token (20ms)
│  │
│  └─ [frontend] Render response (20ms)
```

## Troubleshooting

### Metrics Not Appearing

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check if app exposes /metrics
kubectl port-forward -n production pod/my-app-xxx 8080:8080
curl http://localhost:8080/metrics
```

### Alerts Not Firing

```bash
# Check Alertmanager
kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0

# Check alert rules
kubectl get prometheusrules -n monitoring

# Verify Alertmanager config
kubectl get secret -n monitoring alertmanager-kube-prometheus-stack-alertmanager -o yaml
```

### Traces Not Showing

```bash
# Check OpenTelemetry Collector
kubectl logs -n opentelemetry -l app=opentelemetry-collector

# Verify app sends traces
kubectl logs -n production my-app-xxx | grep -i "otel\|trace"

# Check Jaeger
kubectl logs -n opentelemetry -l app=jaeger
```

## Cost Optimization

### Metrics Retention

```yaml
# Reduce Prometheus retention (default: 15d)
prometheus:
  prometheusSpec:
    retention: 7d  # Keep last 7 days
    retentionSize: "50GB"
```

### Sample Rate

```yaml
# Reduce trace sample rate for high-traffic services
env:
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # Sample 10% of traces
```

## Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Four Golden Signals (Google SRE)](https://sre.google/sre-book/monitoring-distributed-systems/)
