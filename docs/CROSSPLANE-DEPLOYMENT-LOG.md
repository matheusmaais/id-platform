# Crossplane Deployment Log - Static Site Template

## Timeline

### 2026-01-30 01:30-03:30 UTC

#### Phase 1: Terraform Infrastructure (✅ COMPLETE)
**Duration:** 2min 12s  
**Status:** SUCCESS

**Resources Created:**
- Namespace `crossplane-system` 
- IAM Role `platform-eks-crossplane` (ARN: `arn:aws:iam::948881762705:role/platform-eks-crossplane`)
- IAM Policy with S3 + CloudFront permissions
- ServiceAccount `provider-aws` with IRSA annotation
- ConfigMaps updated with CROSSPLANE_ROLE_ARN and ENVIRONMENT

**Files Modified:**
- `terraform/platform-gitops/crossplane.tf` (new file)
- `terraform/platform-gitops/configmap.tf`
- `terraform/platform-gitops/locals.tf`

**Terraform Output:**
```
Apply complete! Resources: 5 added, 4 changed, 0 destroyed.
crossplane_role_arn = "arn:aws:iam::948881762705:role/platform-eks-crossplane"
```

---

#### Phase 2: Crossplane Installation via GitOps (✅ COMPLETE with Issues)

**Issue #1: Sync Wave Ordering** (01:40-02:00 UTC)
- **Problem:** All resources syncing simultaneously, CRD not found errors
- **Solution:** Added sync-waves (10, 20, 30) + SkipDryRunOnMissingResource
- **Commit:** `c83af96` - "fix: add sync-waves to Crossplane resources for proper ordering"

**Issue #2: Provider Version 404** (02:00-03:20 UTC)
- **Problem:** 
  - `provider-aws-s3:v1.23.0` doesn't exist (404)
  - Versions v1.21.0+ require Upbound Team subscription (paid)
- **Investigation:**
  ```
  kubectl describe provider provider-aws-s3
  Message: HEAD https://xpkg.upbound.io/v2/.../v1.23.0: 404 Not Found
          MANIFEST_UNKNOWN: manifest unknown
  ```
- **Solution:** Downgraded to v1.16.0 (last free version)
- **Commit:** `c629bfc` - "fix: use free provider versions (v1.16.0)"

**Issue #3: ArgoCD Health Check** (02:00-03:20 UTC)
- **Problem:** `ComparisonError: cannot perform concat operation between string and nil`
- **Analysis:** Known ArgoCD bug with Crossplane Provider health checks
- **Status:** FALSE POSITIVE - resources are synced, Crossplane is running
- **Evidence:**
  ```
  kubectl get deployments -n crossplane-system
  crossplane                1/1     1            1           87m
  crossplane-rbac-manager   1/1     1            1           87m
  ```

**Current State (03:20 UTC):**
```
Crossplane Core: ✅ RUNNING
├── Deployment/crossplane: 1/1 Running (87min uptime)
└── Deployment/crossplane-rbac-manager: 1/1 Running (87min uptime)

Providers: ⏳ AWAITING SYNC
├── provider-aws-s3: INSTALLED=False (awaiting v1.16.0 sync from Git)
└── provider-aws-cloudfront: INSTALLED=False (awaiting v1.16.0 sync from Git)
```

---

#### Phase 3: Additional Improvements

**Site HTML Enhancements:**
- Added tech badges (AWS, Terraform, Kubernetes, ArgoCD, Crossplane, Backstage)
- Modern gradient design with green theme
- Responsive layout with hover effects
- **Commits:** 
  - `78574af` - Beautiful HTML template
  - `c696719` - Technology badges

---

## Key Decisions (GitOps Principles Applied)

1. **All changes via Git commits** - No imperative `kubectl apply`
2. **Sync-waves for ordering** - Declarative resource dependencies
3. **Free provider versions** - Avoid vendor lock-in with paid subscriptions
4. **IRSA for auth** - No static credentials, following AWS best practices
5. **Documented in STATE.md** - Full traceability

---

## Next Steps

1. Wait for ArgoCD auto-sync to apply v1.16.0 provider versions (ETA: 3-5min)
2. Verify Providers reach `INSTALLED=True` and `HEALTHY=True`
3. Deploy ProviderConfig and validate IRSA authentication
4. Deploy XRD and Composition
5. Test end-to-end flow via Backstage template

---

## Troubleshooting Commands

```bash
# Check Crossplane status
kubectl get deployments,pods -n crossplane-system
kubectl get providers.pkg.crossplane.io

# Check ArgoCD Application
kubectl get application crossplane -n argocd -o yaml | grep -A 30 "status:"

# Check Provider details
kubectl describe provider provider-aws-s3

# Force ArgoCD sync (if needed)
kubectl -n argocd patch application crossplane --type json \
  -p='[{"op": "add", "path": "/operation", "value": {"initiatedBy": {"username": "admin"}, "sync": {"revision": "HEAD"}}}]'
```

---

## References

- [Crossplane Docs](https://docs.crossplane.io/)
- [AWS Blueprints for Crossplane](https://awslabs.github.io/crossplane-on-eks/)
- [Upbound Provider Marketplace](https://marketplace.upbound.io/providers/upbound/provider-aws-s3)
- [Crossplane Best Practices](https://blog.crossplane.io/enhancing-security-practices-with-crossplane-providers/)
