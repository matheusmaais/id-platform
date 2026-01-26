# Observability Annotations - Standard

This document defines the standard annotations that all microservices should include in their `catalog-info.yaml` for proper observability integration with Grafana.

## Required Annotations

All microservices deployed in the IDP must include these annotations:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: my-service
  annotations:
    # Grafana Deep Links
    grafana.io/loki-query-url: >-
      https://grafana.timedevops.click/explore?left=["now-1h","now","Loki",{"expr":"{namespace=\"default\",app_kubernetes_io_name=\"my-service\"}"}]
    grafana.io/dashboard-url: >-
      https://grafana.timedevops.click/d/service-overview?var-namespace=default&var-app=my-service

    # Prometheus Metrics (optional, only if /metrics endpoint exists)
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/metrics"
```

## Annotation Details

### 1. `grafana.io/loki-query-url`

**Purpose:** Deep link to Grafana Explore with a pre-configured Loki query for this service's logs.

**Format:**
```
https://<GRAFANA_DOMAIN>/explore?left=["now-1h","now","Loki",{"expr":"<QUERY>"}]
```

**Query Pattern:**
```
{namespace="<NAMESPACE>",app_kubernetes_io_name="<APP_NAME>"}
```

**Required Labels in Logs:**
- `namespace`: Kubernetes namespace where the service is deployed
- `app_kubernetes_io_name`: Application name (matches `metadata.name` in Backstage)

**Example:**
```yaml
grafana.io/loki-query-url: >-
  https://grafana.timedevops.click/explore?left=["now-1h","now","Loki",{"expr":"{namespace=\"team-alpha\",app_kubernetes_io_name=\"hello-node\"}"}]
```

### 2. `grafana.io/dashboard-url`

**Purpose:** Deep link to a Grafana dashboard with pre-selected filters for this service.

**Format:**
```
https://<GRAFANA_DOMAIN>/d/<DASHBOARD_ID>?var-namespace=<NAMESPACE>&var-app=<APP_NAME>
```

**Dashboard ID:** `service-overview` (our golden dashboard)

**Variables:**
- `var-namespace`: Kubernetes namespace
- `var-app`: Application name

**Example:**
```yaml
grafana.io/dashboard-url: >-
  https://grafana.timedevops.click/d/service-overview?var-namespace=team-alpha&var-app=hello-node
```

### 3. Prometheus Annotations (Optional)

**Purpose:** Enable Prometheus to scrape metrics from the service.

**When to Use:** Only if your service exposes a `/metrics` endpoint (e.g., using `prom-client` for Node.js).

**Required Annotations:**
```yaml
prometheus.io/scrape: "true"  # Enable scraping
prometheus.io/port: "3000"     # Port where metrics are exposed
prometheus.io/path: "/metrics" # Path to metrics endpoint
```

**Example Service with Metrics:**
```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: api-gateway
  annotations:
    grafana.io/loki-query-url: >-
      https://grafana.timedevops.click/explore?left=["now-1h","now","Loki",{"expr":"{namespace=\"production\",app_kubernetes_io_name=\"api-gateway\"}"}]
    grafana.io/dashboard-url: >-
      https://grafana.timedevops.click/d/service-overview?var-namespace=production&var-app=api-gateway
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/metrics"
```

## Kubernetes Label Requirements

For observability to work correctly, your Kubernetes Deployment MUST include these labels:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: my-service
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: my-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: my-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: my-service
        app.kubernetes.io/component: backend
        app.kubernetes.io/part-of: my-system
```

**Required Labels:**
- `app.kubernetes.io/name`: Must match Backstage `metadata.name`
- `app.kubernetes.io/component`: Component type (e.g., backend, frontend, database)
- `app.kubernetes.io/part-of`: System name (matches Backstage `spec.system`)

## Log Format Requirements

For structured logging and proper parsing in Loki, services should emit logs in **JSON format**:

```json
{
  "level": "info",
  "msg": "Request processed",
  "timestamp": "2024-01-20T10:30:00Z",
  "method": "GET",
  "path": "/api/users",
  "status": 200,
  "duration_ms": 45
}
```

**Required Fields:**
- `level`: Log level (debug, info, warn, error, fatal)
- `msg`: Human-readable message
- `timestamp`: ISO 8601 timestamp

**Recommended Fields:**
- `method`, `path`, `status`: For HTTP requests
- `duration_ms`: Request duration
- `user_id`, `trace_id`: For distributed tracing

## Backstage Template Integration

When creating a new microservice via Backstage scaffolder, the template should automatically inject these annotations:

```yaml
# In your template.yaml
steps:
  - id: fetch
    name: Generate Microservice
    action: fetch:template
    input:
      url: ./skeleton
      values:
        name: ${{ parameters.name }}
        namespace: ${{ parameters.namespace }}
        baseDomain: ${{ values.baseDomain }}
        # ... other values
```

**In skeleton/catalog-info.yaml:**
```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: ${{ values.name }}
  annotations:
    grafana.io/loki-query-url: >-
      https://grafana.${{ values.baseDomain }}/explore?left=["now-1h","now","Loki",{"expr":"{namespace=\"${{ values.namespace }}\",app_kubernetes_io_name=\"${{ values.name }}\"}"}]
    grafana.io/dashboard-url: >-
      https://grafana.${{ values.baseDomain }}/d/service-overview?var-namespace=${{ values.namespace }}&var-app=${{ values.name }}
```

## Validation

Use Kyverno policies to enforce these annotations:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-observability-labels
spec:
  validationFailureAction: Audit
  rules:
    - name: check-app-labels
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
      validate:
        message: "Label app.kubernetes.io/name is required for observability"
        pattern:
          metadata:
            labels:
              app.kubernetes.io/name: "?*"
```

## Testing Deep Links

After deploying a service:

1. **Access Backstage** → Navigate to your component
2. **Click "View Logs"** → Should open Grafana Explore with filtered logs
3. **Click "View Dashboard"** → Should open service-overview dashboard
4. **Verify logs appear** in Grafana with correct labels
5. **Verify metrics** (if applicable) in Prometheus

## Troubleshooting

**Logs not appearing in Grafana:**
- Verify Promtail is running: `kubectl get pods -n observability -l app.kubernetes.io/name=promtail`
- Check Promtail logs: `kubectl logs -n observability -l app.kubernetes.io/name=promtail`
- Verify pod labels match the query

**Dashboard not loading:**
- Verify dashboard exists in Grafana: Settings → Dashboards → service-overview
- Check variables are correctly set in URL
- Verify Prometheus datasource is configured

**Metrics not scraped:**
- Verify annotations are on the **Pod**, not just Deployment
- Check Prometheus targets: Port-forward Prometheus → Status → Targets
- Verify `/metrics` endpoint returns valid Prometheus format

## References

- [Grafana Loki Query Language](https://grafana.com/docs/loki/latest/query/)
- [Prometheus Exposition Formats](https://prometheus.io/docs/instrumenting/exposition_formats/)
- [Kubernetes Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- [Backstage Software Catalog](https://backstage.io/docs/features/software-catalog/)
