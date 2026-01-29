# ArgoCD ApplicationSet Auto-Discovery

This document describes how the platform auto-discovers application repositories
and creates ArgoCD Applications without manual intervention.

## How it works

- Source of truth: `config/platform-params.yaml`
- Generator: ArgoCD ApplicationSet SCM Provider (GitHub org scan)
- Filter: `github.repoRegex` + `apps.manifestsPath`
- Namespace: per app, derived from repo name (prefix removed)
- Sync: automated (prune + self-heal)

## Key parameters

`config/platform-params.yaml`:

- `github.org` - GitHub organization
- `github.appRepoPrefix` - repo prefix (e.g., `idp-`)
- `github.repoRegex` - regex for repo discovery (e.g., `^idp-.*$`)
- `apps.manifestsPath` - path inside repo with manifests (default `deploy`)
- `apps.namespace.template` - docs-only template for namespace naming

## Troubleshooting

### Repo does not appear in ArgoCD

Checklist:

1. Repo name matches `github.repoRegex`
2. Repo contains the `apps.manifestsPath` directory
3. ArgoCD has access to the repo (private repo requires token or GitHub App)

Commands:

```bash
kubectl get applicationset workloads -n argocd
kubectl get applications -n argocd -l platform.darede.io/workload=true
```

### Application created but OutOfSync

Checklist:

1. Verify manifests are valid in `apps.manifestsPath`
2. Check namespace exists or `CreateNamespace=true` is set
3. Check ArgoCD events and controller logs

Commands:

```bash
kubectl get application <app> -n argocd
kubectl describe application <app> -n argocd
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=200
```

### Private repo access denied

Checklist:

1. `backstage-github` / `argocd_scm_token` Secret exists
2. Token has access to the org repos

Commands:

```bash
kubectl get secret argocd-scm-token -n argocd
kubectl describe secret argocd-scm-token -n argocd
```

## Validation

```bash
make validate-argocd-discovery
```
