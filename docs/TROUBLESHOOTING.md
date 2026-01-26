# Troubleshooting Guide

## Common Installation Issues

### Pre-Installation Issues

#### Error: Missing required environment variable
**Symptom:** `validate-config.sh` fails with "Missing required environment variable"

**Solution:**
```bash
export GITHUB_TOKEN="ghp_xxxxx"
export KEYCLOAK_ADMIN_PASSWORD="changeme"
export ARGOCD_CLIENT_SECRET="$(openssl rand -hex 32)"
export BACKSTAGE_CLIENT_SECRET="$(openssl rand -hex 32)"
```

#### Error: AWS credentials not configured
**Symptom:** `aws sts get-caller-identity` fails

**Solution:**
```bash
aws configure
# Or set AWS_PROFILE
export AWS_PROFILE=your-profile
```

#### Error: kubectl not configured
**Symptom:** `kubectl cluster-info` fails

**Solution:**
```bash
# After Terraform creates cluster
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### Installation Issues

#### Error: Terraform state locked
**Symptom:** `terraform apply` fails with "Error acquiring the state lock"

**Solution:**
```bash
cd cluster/terraform
terraform force-unlock <lock-id>
```

#### Error: ArgoCD Application sync failed
**Symptom:** Application shows "SyncFailed" status

**Common Causes:**
1. **GitOps repo not accessible**
   - Check `GITHUB_TOKEN` is set
   - Verify repo URL in `config.yaml` is correct
   - Check ArgoCD repo credentials secret exists

2. **Templates not rendered**
   - Templates in GitOps repo must be pre-rendered
   - Or use Helm charts directly instead of directory paths

3. **Missing Terraform outputs**
   - Run `terraform output` to verify all outputs exist
   - Re-run `terraform apply` if outputs are missing

**Solution:**
```bash
# Check Application status
kubectl -n argocd get applications

# Check Application details
kubectl -n argocd describe application <app-name>

# Check sync logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller
```

#### Error: Keycloak realm import failed
**Symptom:** `keycloak-realm-import` Job fails

**Common Causes:**
1. **Keycloak not ready**
   - Job starts before Keycloak is fully ready
   - Check Keycloak pod logs

2. **kcadm.sh not found**
   - Image tag mismatch between Helm chart and Job
   - Verify `keycloak.image_tag` matches Job image tag

3. **ConfigMap not found**
   - `keycloak-realm-config` ConfigMap missing
   - Verify bootstrap script created it

**Solution:**
```bash
# Check Job status
kubectl -n keycloak get jobs
kubectl -n keycloak describe job keycloak-realm-import

# Check Job logs
kubectl -n keycloak logs job/keycloak-realm-import

# Check Keycloak pod
kubectl -n keycloak get pods
kubectl -n keycloak logs <keycloak-pod-name>
```

#### Error: OIDC login fails
**Symptom:** Cannot login to ArgoCD/Backstage via Keycloak

**Common Causes:**
1. **Client secret mismatch**
   - Verify `ARGOCD_CLIENT_SECRET` matches Keycloak client secret
   - Check `oidc-client-secrets` secret in argocd namespace

2. **Issuer URL incorrect**
   - Keycloak issuer may be `/realms/platform` or `/auth/realms/platform`
   - Check Keycloak version and issuer URL format

3. **Redirect URI mismatch**
   - Verify redirect URIs in Keycloak client match application URLs

**Solution:**
```bash
# Check Keycloak client configuration
kubectl -n keycloak exec -it <keycloak-pod> -- \
  /opt/bitnami/keycloak/bin/kcadm.sh get clients/argocd \
  --server http://localhost:8080 \
  --realm platform \
  --user admin \
  --password <password>

# Test issuer URL
curl -k https://keycloak.<domain>/realms/platform/.well-known/openid-configuration
curl -k https://keycloak.<domain>/auth/realms/platform/.well-known/openid-configuration
```

### Post-Installation Issues

#### Error: Endpoints return 502/503
**Symptom:** Application URLs return bad gateway errors

**Common Causes:**
1. **Ingress not ready**
   - Check ingress-nginx pods are running
   - Verify LoadBalancer service has external IP

2. **DNS not configured**
   - Check Route53 records exist
   - Verify external-dns is running and creating records

**Solution:**
```bash
# Check ingress
kubectl -n ingress-nginx get svc
kubectl -n ingress-nginx get pods

# Check DNS records
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>

# Check external-dns logs
kubectl -n external-dns logs -l app.kubernetes.io/name=external-dns
```

#### Error: Application pods not starting
**Symptom:** Pods stuck in Pending or CrashLoopBackOff

**Common Causes:**
1. **Resource constraints**
   - Not enough CPU/memory in cluster
   - Check node resources

2. **Image pull errors**
   - Private registry credentials missing
   - Image tag doesn't exist

3. **ConfigMap/Secret missing**
   - Required ConfigMaps or Secrets not created

**Solution:**
```bash
# Check pod status
kubectl get pods --all-namespaces

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
```

## Recovery Procedures

### Complete Cluster Rebuild

If installation is completely broken:

```bash
# 1. Destroy everything
./scripts/destroy-cluster.sh

# 2. Verify cleanup
kubectl get all --all-namespaces
terraform -chdir=cluster/terraform state list

# 3. Reinstall from scratch
make install
```

### Partial Recovery

If only some components failed:

```bash
# 1. Delete failed Applications
kubectl -n argocd delete application <failed-app>

# 2. Re-apply root app
gomplate -f argocd-apps/root-app.yaml.tpl -c config.yaml | kubectl apply -f -

# 3. Wait for sync
kubectl -n argocd wait --for=condition=healthy application <app-name> --timeout=5m
```

## Getting Help

1. Check logs: `test-install.log` contains full installation log
2. Check Application status: `kubectl -n argocd get applications`
3. Check pod logs: `kubectl logs <pod-name> -n <namespace>`
4. Check ArgoCD UI: `https://argocd.<domain>`

## Prevention

- Always run `make doctor` before installation
- Always run `scripts/pre-flight-check.sh` before installation
- Keep `config.yaml` and environment variables in sync
- Use pinned versions for charts and images
- Test in dev/staging before production
