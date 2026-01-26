# TLS/HTTPS Configuration

## Overview

All Ingresses in the platform are configured with TLS termination at the NLB using AWS ACM certificates.

## Architecture

```
Internet → Route53 (DNS) → NLB (TLS termination via ACM) → Ingress-NGINX → Services
```

## Configuration

### 1. ACM Certificate

The ACM certificate ARN is defined in `config.yaml`:

```yaml
acm_certificate_arn: "arn:aws:acm:us-east-1:948881762705:certificate/051f6515-0d0b-459c-a056-0663f7c88f5e"
```

### 2. NLB Configuration

The ingress-nginx Service is configured with the ACM certificate:

```yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "${ACM_CERTIFICATE_ARN}"
service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
```

### 3. Ingress Configuration

All Ingresses must include:

```yaml
spec:
  ingressClassName: nginx
  rules:
    - host: service.{{ domain }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-name
                port:
                  number: 80
  tls:
    - hosts:
        - service.{{ domain }}
```

**Important annotations:**

```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: service.{{ domain }}
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

## Current Status

### ✅ Configured with Templates

- **Grafana** (`argocd-apps/platform/kube-prometheus-stack.yaml.tpl`)
  - Template uses `{{ domain }}` placeholder
  - Rendered by `scripts/render-argocd-apps.sh`
  - Called by `scripts/install-observability.sh`

### ⚠️ Configured via kubectl patch (TEMPORARY)

The following Ingresses were patched manually and need to be refactored to use templates:

- **ArgoCD** (`argocd` namespace)
- **Backstage** (`backstage` namespace)
- **Keycloak** (`keycloak` namespace)

**Patches applied:**

```bash
kubectl patch ingress <name> -n <namespace> --type='json' -p='[
  {"op": "add", "path": "/spec/tls", "value": [{"hosts": ["<service>.timedevops.click"]}]},
  {"op": "add", "path": "/metadata/annotations/nginx.ingress.kubernetes.io~1ssl-redirect", "value": "true"}
]'
```

## TODO: Refactor to Templates

### ArgoCD Ingress

**Current:** Created by `scripts/install-argocd.sh` via `kubectl apply`

**Target:** Create `platform/argocd/ingress.yaml.tpl`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    external-dns.alpha.kubernetes.io/hostname: argocd.{{ domain }}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.{{ domain }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
  tls:
    - hosts:
        - argocd.{{ domain }}
```

### Backstage Ingress

**Current:** Created by Backstage Helm chart

**Target:** Override in `platform/backstage/helm-values.yaml.tpl`:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: backstage.{{ domain }}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
  hosts:
    - host: backstage.{{ domain }}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - backstage.{{ domain }}
```

### Keycloak Ingress

**Current:** Created by Keycloak Helm chart

**Target:** Override in `platform/keycloak/helm-values.yaml.tpl`:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: keycloak.{{ domain }}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
  hosts:
    - host: keycloak.{{ domain }}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - keycloak.{{ domain }}
```

## Validation

Test HTTPS connectivity:

```bash
for host in grafana argocd backstage keycloak; do
  echo -n "$host: "
  curl -I -s --connect-timeout 5 https://$host.timedevops.click 2>&1 | head -1
done
```

Expected output:

```
grafana: HTTP/2 302
argocd: HTTP/2 200
backstage: HTTP/2 200
keycloak: HTTP/2 200
```

## Security Considerations

1. **TLS Termination:** Happens at NLB using ACM certificate
2. **Backend Protocol:** HTTP between NLB and Ingress-NGINX (internal traffic)
3. **Force SSL:** All HTTP requests are redirected to HTTPS
4. **Certificate Management:** Automatic renewal via ACM
5. **DNS:** Managed by External-DNS (automatic A record creation)

## References

- [AWS ACM Documentation](https://docs.aws.amazon.com/acm/)
- [Ingress-NGINX Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [External-DNS AWS Guide](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)
