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

### Issue 3: ArgoCD não pegou a nova app (criada no Backstage)

**Symptoms:**
- Você criou uma app Node.js (ou Static Site) no Backstage; GitHub e CI foram criados.
- No ArgoCD não aparece nenhuma Application para esse repo (app não foi descoberta).

**Checks rápidos:**

1. **Nome do repo** — O ApplicationSet só descobre repos que batem com `^idp-.*` e que tenham o diretório `deploy/`. O repo precisa ser `idp-<nome>` (ex.: `idp-myapp`). Se o nome não começar com `idp-`, o ArgoCD não lista.

2. **Diretório `deploy/`** — O filtro usa `pathsExist: ["deploy"]`. Confirme que no **branch default** (ex.: `main`) existe o diretório `deploy/` com os manifests. Se o primeiro commit não tiver `deploy/`, o ApplicationSet ignora o repo.

3. **Forçar reconciliação do ApplicationSet** — O controller pode levar até ~1 min para rodar de novo. Para não esperar:

   ```bash
   # Forçar refresh do ApplicationSet "workloads"
   kubectl annotate applicationset workloads -n argocd argocd.argoproj.io/refresh=hard --overwrite
   ```

   Ou com ArgoCD CLI: `argocd appset get workloads --refresh` (se tiver `argocd` configurado).

4. **Logs do ApplicationSet controller** — Ver se há erro ao listar repos ou ao aplicar o filtro:

   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100
   ```

   Procure por erros de GitHub (401, 403, 404) ou mensagens como `generated N applications`.

5. **Token no cluster vem do Terraform** — O token do SCM Provider está no secret `github-scm-token` (namespace argocd), criado pelo Terraform a partir de **var.github_token**. O `make apply-gitops` usa `GITHUB_TOKEN` do `.env` → `TF_VAR_github_token`. **Se você rotacionou o token:** atualize o `.env` com o novo `GITHUB_TOKEN` e rode `make apply-gitops` (ou `terraform apply` em `terraform/platform-gitops`) para atualizar o secret no cluster. Sem isso, o ArgoCD continua usando o token antigo e pode passar a listar 0 repos (401/403).

6. **Bug conhecido: filtro pathsExist** — Em alguns cenários o filtro `pathsExist: ["deploy"]` faz o SCM Provider retornar **0 repos** (ex.: 404 na checagem de path). Se o token está correto e o repo tem `deploy/` mas o ApplicationSet continua gerando 0 applications, desabilite o filtro para testar: em `terraform/platform-gitops` rode `terraform apply -var="apps_scm_paths_exist_filter=false"` (ou crie `terraform.tfvars` com `apps_scm_paths_exist_filter = false`). Depois force refresh: `kubectl annotate applicationset workloads -n argocd argocd.argoproj.io/refresh=hard --overwrite`. Se as apps voltarem a aparecer, a causa é o pathsExist; pode deixar o filtro desligado (todos os repos `idp-*` da org serão descobertos) ou acompanhar correções no ArgoCD.

**Resumo:** Confirme repo `idp-*`, `deploy/` no branch default, **token no cluster atualizado via terraform apply**, force o refresh do ApplicationSet. Se ainda 0 apps, teste com `apps_scm_paths_exist_filter=false`.

---

### Issue 4: Backstage Not Accessible via HTTPS

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

### Issue 5: PostgreSQL Persistence Issues

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

### Issue 6: Backstage Catalog Not Loading

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

### Issue 7: Cognito OIDC Authentication Not Working

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

### Issue 8: StaticWebsite / CDN — Sync OK but S3 not created

**Symptoms:**
- ArgoCD Application do static site está Synced.
- O claim `StaticWebsite` existe no namespace da app.
- S3 (e CloudFront) não foram provisionados pelo Crossplane.

**Diagnóstico (rode no cluster e use a saída para achar a causa):**

1. **Claim e Composite:**
```bash
# Listar claims StaticWebsite (troque o namespace pelo da sua app, ex.: daredeidpmonday1)
kubectl get staticwebsite -A
kubectl get xstaticwebsite -A

# Detalhes do claim (nome do recurso que você viu no erro, ex.: daredeidpmonday1)
kubectl describe staticwebsite <nome-do-claim> -n <namespace-da-app>
# Ver condições (Ready, Synced) e events no final
```

2. **XRD e Composition:**
```bash
kubectl get xrd xstaticwebsites.platform.darede.io
kubectl get composition
kubectl get compositionrevision
# Se não houver Composition/CompositionRevision, a app Crossplane pode estar OutOfSync ou o path não foi aplicado
```

3. **ProviderConfig e Providers:**
```bash
kubectl get providerconfig -A
kubectl get provider -n crossplane-system
kubectl get providerrevision -n crossplane-system
# ProviderConfig "default" (aws.upbound.io) deve existir; providers provider-aws-s3 e provider-aws-cloudfront INSTALLED/HEALTHY
```

4. **Recursos S3/CloudFront (Crossplane):**
```bash
kubectl get bucket -A
kubectl get distribution -A
# Se vazios, a Composition não está criando ou o provider não está aplicando
```

5. **Events e logs Crossplane:**
```bash
kubectl get events -n <namespace-da-app> --sort-by='.lastTimestamp' | tail -30
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=50
```

**Causas comuns:**

| Causa | O que ver | Ação |
|-------|-----------|------|
| **IRSA 403** (causa raiz comum) | Bucket/Distribution com `ReconcileError`, mensagem `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity` | A role IAM deve confiar na SA usada pelo provider. O DeploymentRuntimeConfig usa `serviceAccountName: provider-aws`; a trust policy em `terraform/platform-gitops/crossplane.tf` deve incluir `provider-aws` (não só `crossplane-provider-aws-*`). Rode `terraform apply` no módulo platform-gitops. |
| **Region obrigatório no S3** | Events no XStaticWebsite: `BucketPublicAccessBlock`/`BucketOwnershipControls` "invalid: spec.forProvider.region: Required value" | A Composition deve aplicar `spec.region` nos recursos S3 (BucketPublicAccessBlock, BucketOwnershipControls). Corrigido em `platform-apps/crossplane/static-website/composition.yaml` com patch `FromCompositeFieldPath: spec.region → spec.forProvider.region`. Sync da app Crossplane no ArgoCD. |
| App Crossplane não Synced | XRD ou Composition ausentes | No ArgoCD: Sync da application `crossplane` (namespace argocd). |
| ProviderConfig ausente | `kubectl get providerconfig` vazio | A app Crossplane aplica `platform-apps/crossplane/providers/provider-config.yaml` em `crossplane-system`; confira que o path está no Application e deu Sync. |
| Provider não HEALTHY | `kubectl get provider` mostra não HEALTHY | Ver IRSA: `kubectl get sa provider-aws -n crossplane-system -o yaml` (annotation `eks.amazonaws.com/role-arn`). Ver logs do provider. |
| siteName inválido no claim | Condição no claim com erro de validação | O XRD exige `spec.siteName` com pattern `^[a-z][a-z0-9-]*$` e maxLength 32. Corrija o manifest no repo da app e faça Sync de novo. |
| Composition não usada | XStaticWebsite existe mas sem recursos composto | Verifique se existe uma Composition com `compositeTypeRef: XStaticWebsite` e label `crossplane.io/xrd: xstaticwebsites.platform.darede.io`. |

**Validação após correção:**
```bash
kubectl get staticwebsite -A
kubectl get bucket -A
kubectl get distribution -A
# Bucket e Distribution devem aparecer e ficar Ready
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
