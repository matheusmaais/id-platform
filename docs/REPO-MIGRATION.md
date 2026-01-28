# Repository Migration Log

## Migration Details

**Date:** 2026-01-28 19:30-19:48 UTC  
**From:** `matheusmaais/id-platform`  
**To:** `darede-labs/idp-platform`  
**Reason:** Move to organization account for proper SCM Provider support in ArgoCD ApplicationSet

## Pre-Migration State

**Commit SHA:** `ab9d55db28fc53d10bc7ac1ec4e354ce4dce414f`  
**Branch:** `main`  
**Status:** All services operational (ArgoCD + Backstage HTTP 200)

### Validation Results (Pre-Migration)
```bash
✅ ArgoCD Server: Running (2/2 pods)
✅ ArgoCD Dex: Running (1/1 pod)
✅ Backstage: Running (1/1 pod)
✅ ArgoCD UI: https://argocd.timedevops.click (HTTP 200)
✅ Backstage UI: https://backstage.timedevops.click (HTTP 200)
✅ Applications: backstage (Synced/Healthy), platform-apps (Synced/Healthy)
```

## Migration Steps Executed

### 1. Repository Creation
```bash
gh repo create darede-labs/idp-platform --private
# Created: https://github.com/darede-labs/idp-platform
```

### 2. Code Changes
Updated references in 6 files:
- `config/platform-params.yaml`: Updated `repository.org`, `repository.name`, `repository.url`, `github.org`
- `argocd-apps/platform/backstage-appset.yaml`: Updated Git File generator `repoURL`
- `docs/STATE.md`, `docs/PHASE-0-GITOPS.md`, `docs/BACKSTAGE-DEPLOYMENT-PLAN.md`, `docs/VALIDATION-WORKFLOW.md`: Updated repo URLs

**Commit:** `94904f948ec341b4ba7613f4584de75689d64ed1`  
**Message:** `chore: migrate to darede-labs/idp-platform`

### 3. Push to New Repository
```bash
git push new-origin main:main
# Pushed 94904f9 to darede-labs/idp-platform
```

### 4. Terraform Apply
Applied changes to update cluster resources:
```bash
cd terraform/platform-gitops
export TF_VAR_github_token="$GITHUB_TOKEN"
terraform apply -auto-approve
```

**Resources Updated (7 changes):**
- `kubectl_manifest.platform_apps`: Updated `spec.source.repoURL`
- `kubectl_manifest.apps_project`: Updated `spec.sourceRepos` pattern
- `kubectl_manifest.workloads_appset`: Updated `spec.generators[0].scmProvider.github.organization`
- `kubernetes_config_map.platform_params`: Updated `GITHUB_ORG`, `PLATFORM_REPO_URL`
- `kubernetes_config_map.platform_params_backstage`: Updated `GITHUB_ORG`, `PLATFORM_REPO_URL`
- `kubernetes_secret.argocd_repo`: Updated repo URL
- `kubernetes_secret.backstage_postgresql`: Metadata cleanup

### 5. ApplicationSet Update
The `platform-apps` ApplicationSet needed manual update because it reads from Git:
```bash
kubectl apply -f argocd-apps/platform/backstage-appset.yaml
# Updated Git File generator repoURL to new repo
```

### 6. Application Refresh
Forced Backstage Application recreation to pick up new repo:
```bash
kubectl delete application backstage -n argocd
# ApplicationSet automatically recreated it with new repoURL
```

## Post-Migration State

**Commit SHA:** `94904f948ec341b4ba7613f4584de75689d64ed1`  
**Repository:** `https://github.com/darede-labs/idp-platform`  
**Branch:** `main`

### Validation Results (Post-Migration)
```bash
✅ ArgoCD Server: Running (2/2 pods)
✅ ArgoCD Dex: Running (1/1 pod)
✅ Backstage: Running (1/1 pod) - Recreated successfully
✅ ArgoCD UI: https://argocd.timedevops.click (HTTP 200)
✅ Backstage UI: https://backstage.timedevops.click (HTTP 200)
✅ Applications: backstage (Synced/Healthy), platform-apps (Synced/Healthy)
✅ platform-apps Application: repoURL = https://github.com/darede-labs/idp-platform
✅ backstage Application: sources[1].repoURL = https://github.com/darede-labs/idp-platform
✅ platform-apps ApplicationSet: generators[0].git.repoURL = https://github.com/darede-labs/idp-platform
✅ workloads ApplicationSet: organization = darede-labs
```

### ConfigMap Verification
```bash
kubectl get configmap platform-params -n argocd -o jsonpath='{.data.GITHUB_ORG}'
# Output: darede-labs ✅

kubectl get configmap platform-params -n argocd -o jsonpath='{.data.PLATFORM_REPO_URL}'
# Output: https://github.com/darede-labs/idp-platform ✅
```

## Issues Encountered

### 1. Terraform State Lock
**Issue:** State lock from previous interrupted operation  
**Resolution:** `terraform force-unlock ab9169e1-7d56-9ada-d186-829309d20298`

### 2. ApplicationSet Not Refreshing
**Issue:** ApplicationSet `platform-apps` continued reading from old repo after Terraform apply  
**Root Cause:** ApplicationSet manifest is stored in Git, and Git File generator was pointing to old repo  
**Resolution:** Manually applied updated `backstage-appset.yaml` with new repoURL

### 3. Backstage Application Stale
**Issue:** Backstage Application retained old repoURL after ApplicationSet update  
**Resolution:** Deleted Application to force ApplicationSet to recreate it with new parameters

## Rollback Procedure (If Needed)

If migration needs to be reverted:

```bash
# 1. Revert Terraform changes
cd terraform/platform-gitops
export TF_VAR_github_token="$GITHUB_TOKEN"
terraform apply -var="platform_repo_url=https://github.com/matheusmaais/id-platform"

# 2. Revert ApplicationSet
kubectl apply -f <old-backstage-appset.yaml-with-old-repo>

# 3. Force Application refresh
kubectl delete application backstage -n argocd

# 4. Verify
kubectl get application backstage -n argocd -o jsonpath='{.spec.sources[1].repoURL}'
```

## Lessons Learned

1. **ApplicationSets with Git Generators** require manual update when the generator's `repoURL` changes, even if managed by Terraform
2. **Application recreation** is sometimes necessary to pick up new ApplicationSet parameters
3. **Terraform state locks** should be checked before operations to avoid conflicts
4. **GitHub Organization** is required for ArgoCD SCM Provider (not personal accounts)

## Next Steps

1. ✅ Migration complete and validated
2. ⏭️ Create GitHub Organization `darede-labs` or use existing org for workload auto-discovery
3. ⏭️ Test end-to-end app scaffolding flow with new repository
