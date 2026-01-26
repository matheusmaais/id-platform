---
title: "Bootstrap UI failures (ArgoCD, Keycloak, Backstage)"
date: 2026-01-22
owner: QA/DevOps
severity: High
scope: Clean install (make install from zero)
---

## Symptoms (user-visible)
- ArgoCD UI does not open (browser shows connection error/blank).
- Keycloak UI opens, but Admin Console shows a blank page.
- Backstage loads, but catalog page shows “cannot load entities”.

## Expected behavior
- ArgoCD UI accessible at `https://argocd.<domain>` and loads login page.
- Keycloak Admin Console loads fully with JS/CSS assets and renders UI.
- Backstage catalog loads non-empty entities list.

## Repro steps (clean install)
1. Destroy environment (cluster + DNS + ingress + ArgoCD).
2. Run `make install` from repo root.
3. Open ArgoCD UI URL in browser.
4. Open Keycloak Admin Console URL in browser.
5. Open Backstage UI and navigate to Catalog.

## Evidence to collect (automatable)
- Ingress status and endpoints:
  - `kubectl get ingress -A -o wide`
  - `kubectl describe ingress -n argocd argocd`
- Ingress controller health/logs:
  - `kubectl get pods -n ingress-nginx -o wide`
  - `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200`
- ArgoCD server/service:
  - `kubectl get svc -n argocd`
  - `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=200`
- Keycloak proxy headers / CSP:
  - `kubectl logs -n keycloak -l app.kubernetes.io/name=keycloak --tail=200`
  - `kubectl get ingress -n keycloak -o yaml`
- Backstage catalog:
  - `kubectl logs -n backstage -l app.kubernetes.io/name=backstage --tail=200`
  - `kubectl get configmap -n backstage -o yaml`
