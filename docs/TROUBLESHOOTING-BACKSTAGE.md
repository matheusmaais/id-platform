# Backstage Troubleshooting Guide

## Common Issues and Solutions

### Issue 1: Backstage Application OutOfSync (PostgreSQL Secret Drift)

**Symptoms:**
```bash
kubectl get application backstage -n argocd
# NAME        SYNC STATUS   HEALTH STATUS
# backstage   OutOfSync     Healthy
```

**Root Cause:**
- PostgreSQL Helm chart generates a random `postgres-password` on each sync
- ArgoCD detects this as drift and marks the application as OutOfSync
- This is expected behavior for Helm-managed secrets

**Solution:**
Add `ignoreDifferences` to the ApplicationSet to ignore the password field:

```yaml
# argocd-apps/platform/backstage-appset.yaml
spec:
  template:
    spec:
      ignoreDifferences:
        - kind: Secret
          name: backstage-postgresql
          jsonPointers:
            - /data/postgres-password
```

**Validation:**
```bash
# After applying the fix
kubectl get application backstage -n argocd
# NAME        SYNC STATUS   HEALTH STATUS
# backstage   Synced        Healthy
```

**References:**
- ArgoCD Issue: https://github.com/argoproj/argo-cd/issues/1079
- Best Practice: Always ignore Helm-generated secrets in ArgoCD

---

### Issue 2: Backstage Pod Failing Readiness Probes

**Symptoms:**
```bash
kubectl get pods -n backstage
# NAME                        READY   STATUS    RESTARTS   AGE
# backstage-xxx               0/1     Running   0          5m

kubectl logs -n backstage backstage-xxx --tail=50
# {"level":"error","message":"Plugin 'auth' threw an error during startup...
# TypeError: Invalid URL","input":"${BACKSTAGE_DOMAIN:+https://...}"}
```

**Root Cause:**
- Backstage doesn't support bash-style conditional syntax `${VAR:+value}`
- The app-config uses this syntax for `baseUrl` configuration

**Solution:**
Change the URL syntax in `platform-apps/backstage/values.yaml`:

```yaml
# Before (WRONG)
appConfig:
  app:
    baseUrl: ${BACKSTAGE_DOMAIN:+https://${BACKSTAGE_DOMAIN}}
  backend:
    baseUrl: ${BACKSTAGE_DOMAIN:+https://${BACKSTAGE_DOMAIN}}

# After (CORRECT)
appConfig:
  app:
    baseUrl: https://${BACKSTAGE_DOMAIN}
  backend:
    baseUrl: https://${BACKSTAGE_DOMAIN}
```

**Validation:**
```bash
# Pod should become ready
kubectl get pods -n backstage
# NAME                        READY   STATUS    RESTARTS   AGE
# backstage-xxx               1/1     Running   0          2m

# Check logs for successful startup
kubectl logs -n backstage backstage-xxx | grep "Listening on"
# {"level":"info","message":"Listening on 0.0.0.0:7007"...}
```

---

### Issue 3: Backstage Not Accessible via HTTPS

**Symptoms:**
```bash
curl -I https://backstage.timedevops.click
# HTTP/1.1 502 Bad Gateway
# or
# HTTP/1.1 504 Gateway Timeout
```

**Troubleshooting Steps:**

1. **Check Ingress:**
```bash
kubectl get ingress -n backstage
# Verify ADDRESS is populated with ALB DNS
```

2. **Check ALB Target Health:**
```bash
# Get target group ARN from Ingress annotations
kubectl describe ingress backstage -n backstage | grep target-group

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <arn> \
  --region us-east-1
```

3. **Check Pod Status:**
```bash
kubectl get pods -n backstage
kubectl logs -n backstage <pod-name>
```

4. **Check DNS:**
```bash
dig backstage.timedevops.click +short
# Should return ALB IPs
```

5. **Check Security Groups:**
```bash
# Verify ALB security group allows HTTPS (443)
# Verify ALB can reach pods on port 7007
```

**Common Fixes:**
- Add ALB → Node security group rules
- Verify ACM certificate is valid
- Check External-DNS logs for DNS creation errors

---

### Issue 4: PostgreSQL Persistence Issues

**Symptoms:**
```bash
kubectl get pvc -n backstage
# No resources found (or PVC pending)

kubectl logs -n backstage backstage-postgresql-0
# Warning: PersistentVolumeClaim is not bound
```

**Root Cause:**
- EBS CSI Driver not configured with IRSA
- Persistence disabled in values.yaml for Phase 0

**Current Configuration (Phase 0):**
```yaml
# platform-apps/backstage/values.yaml
postgresql:
  primary:
    persistence:
      enabled: false  # Ephemeral storage for dev
```

**For Production (Phase 1+):**
1. Create EBS CSI Driver IRSA
2. Enable persistence in values.yaml
3. Specify storage class and size

---

### Issue 5: Backstage Catalog Not Loading

**Symptoms:**
- Backstage UI loads but catalog is empty
- No components/systems/APIs visible

**Troubleshooting:**

1. **Check Catalog Configuration:**
```bash
kubectl get configmap backstage-app-config -n backstage -o yaml
# Verify catalog.locations are configured
```

2. **Check Backend Logs:**
```bash
kubectl logs -n backstage <backstage-pod> | grep catalog
# Look for catalog processing errors
```

3. **Check Database Connection:**
```bash
kubectl logs -n backstage <backstage-pod> | grep database
# Verify PostgreSQL connection is successful
```

4. **Test Catalog Endpoint:**
```bash
kubectl port-forward -n backstage svc/backstage 7007:7007
curl http://localhost:7007/api/catalog/entities
```

---

### Issue 6: Cognito OIDC Authentication Not Working

**Symptoms:**
- Login button doesn't appear
- Redirect to Cognito fails
- Authentication succeeds but user not authorized

**Troubleshooting:**

1. **Verify Cognito Configuration:**
```bash
kubectl get secret backstage-cognito -n backstage -o yaml
# Check COGNITO_CLIENT_ID, COGNITO_CLIENT_SECRET, COGNITO_ISSUER
```

2. **Check App Config:**
```bash
kubectl get configmap backstage-app-config -n backstage -o yaml | grep -A 10 "auth:"
```

3. **Verify Cognito Callback URL:**
- Should be: `https://backstage.timedevops.click/api/auth/oidc/handler/frame`
- Check in Cognito User Pool → App Client → Callback URLs

4. **Check Backend Logs:**
```bash
kubectl logs -n backstage <backstage-pod> | grep -i "auth\|oidc\|cognito"
```

---

## Diagnostic Commands

### Quick Health Check
```bash
# Application status
kubectl get application backstage -n argocd

# Pod status
kubectl get pods -n backstage

# Ingress status
kubectl get ingress -n backstage

# HTTP check
curl -I https://backstage.timedevops.click

# DNS check
dig backstage.timedevops.click +short
```

### Detailed Diagnostics
```bash
# Full application details
kubectl describe application backstage -n argocd

# Pod logs
kubectl logs -n backstage <backstage-pod> --tail=100

# PostgreSQL logs
kubectl logs -n backstage backstage-postgresql-0 --tail=50

# Events
kubectl get events -n backstage --sort-by='.lastTimestamp'

# ConfigMap
kubectl get configmap backstage-app-config -n backstage -o yaml

# Secrets (redacted)
kubectl get secrets -n backstage
```

### ArgoCD Specific
```bash
# Sync status
kubectl get application backstage -n argocd -o jsonpath='{.status.sync.status}'

# Health status
kubectl get application backstage -n argocd -o jsonpath='{.status.health.status}'

# Last sync time
kubectl get application backstage -n argocd -o jsonpath='{.status.operationState.finishedAt}'

# Sync errors
kubectl get application backstage -n argocd -o jsonpath='{.status.conditions}'
```

---

## Prevention Best Practices

### 1. Always Use ignoreDifferences for Helm Secrets
```yaml
ignoreDifferences:
  - kind: Secret
    name: backstage-postgresql
    jsonPointers:
      - /data/postgres-password
```

### 2. Use Simple Environment Variable Syntax
```yaml
# Good
baseUrl: https://${BACKSTAGE_DOMAIN}

# Bad
baseUrl: ${BACKSTAGE_DOMAIN:+https://${BACKSTAGE_DOMAIN}}
```

### 3. Monitor ArgoCD Application Health
```bash
# Set up alerts for OutOfSync or Degraded status
kubectl get application -n argocd -w
```

### 4. Use Proper Readiness/Liveness Probes
```yaml
readinessProbe:
  httpGet:
    path: /.backstage/health/v1/readiness
    port: 7007
  initialDelaySeconds: 30
  periodSeconds: 10
```

### 5. Enable Detailed Logging for Debugging
```yaml
backstage:
  extraEnvVars:
    - name: LOG_LEVEL
      value: debug
```

---

## Related Documentation

- [STATE.md](./STATE.md) - Current platform state
- [PHASE-0-GITOPS.md](./PHASE-0-GITOPS.md) - GitOps implementation guide
- [ARCHITECTURE-DECISIONS.md](./ARCHITECTURE-DECISIONS.md) - Architecture decisions
- [Backstage Official Docs](https://backstage.io/docs/overview/what-is-backstage)
- [ArgoCD Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
