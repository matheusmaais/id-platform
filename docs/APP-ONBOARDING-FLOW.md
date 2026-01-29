# App Onboarding Flow (Backstage → GitHub → ArgoCD)

This document describes the end-to-end flow for onboarding a new application
using Backstage and GitOps.

## Flow summary

1. User creates an app in Backstage (`idp-*` repo)
2. Backstage scaffolder generates:
   - `deploy/` manifests (namespace, deployment, service, ingress)
   - CI workflow for build + push to ECR
3. ArgoCD auto-discovers the repo and creates an Application
4. ArgoCD syncs the app and creates the namespace

## CI authentication (temporary)

OIDC is temporarily disabled due to SCP. CI uses static AWS keys from GitHub
Secrets/Environments:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (optional)

When SCP is resolved, switch to OIDC in the workflow.

## Validation

```bash
make validate-platform-params
make validate-argocd-discovery
make validate-new-app-flow APP=idp-myapp1
```

## Debug commands

```bash
kubectl get applications -n argocd
kubectl describe application <app> -n argocd
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=200
kubectl get ingress -n <namespace>
```
