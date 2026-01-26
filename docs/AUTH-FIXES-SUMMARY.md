# Authentication Fixes Summary

## Overview

This document summarizes the authentication fixes implemented to resolve login issues for both ArgoCD and Backstage.

## Issues Identified

### 1. ArgoCD OIDC Login Failure
**Error:** `invalid_scope: Invalid scopes: openid profile email groups`

**Root Cause:** The ArgoCD client in Keycloak was missing the required client scopes (`profile`, `email`, `groups`).

**Fix:**
- Created `scripts/fix-argocd-oidc.sh` to programmatically:
  - Create missing client scopes in Keycloak (profile, email, groups)
  - Associate these scopes with the `argocd` client
  - Restart ArgoCD server to apply changes
- The script is idempotent and can be run multiple times safely

### 2. Backstage Login Failure
**Error:** `Login failed; caused by Error: Failed to sign-in, unable to resolve user identity.`

**Root Cause:** User email mismatch between Keycloak and Backstage catalog:
- Keycloak users had emails: `admin@timedevops.click`, `test-user@timedevops.click`
- Backstage catalog had emails: `admin@darede.com.br`, `matheus.andrade@darede.com.br`

**Fix:**
- Updated `packages/backstage/users-catalog.yaml` to match Keycloak user emails
- Applied changes via ConfigMap update
- Restarted Backstage deployment to pick up new user catalog

## Scripts Created

### 1. `scripts/fix-argocd-oidc.sh`
Standalone script to fix ArgoCD OIDC configuration in Keycloak.

**Features:**
- Loads configuration from `config.yaml` (domain, subdomains)
- Obtains Keycloak admin token
- Creates missing client scopes (profile, email, groups)
- Associates scopes with ArgoCD client
- Restarts ArgoCD server
- Idempotent execution

**Usage:**
```bash
bash scripts/fix-argocd-oidc.sh
```

### 2. `scripts/validate-auth.sh`
Comprehensive validation script for authentication configuration.

**Validates:**
1. Keycloak accessibility
2. Keycloak admin token acquisition
3. Users in Keycloak platform realm
4. ArgoCD client configuration and scopes
5. Backstage client configuration
6. Backstage users catalog
7. ArgoCD OIDC configuration
8. Backstage API accessibility

**Usage:**
```bash
bash scripts/validate-auth.sh
```

**Output:**
- ✓ Success indicators for each validation step
- Detailed information about users, clients, and scopes
- Next steps for manual testing

## Configuration Changes

### 1. Keycloak Realm: `platform`
- **ArgoCD Client:**
  - Client ID: `argocd`
  - Client Scopes: `openid`, `profile`, `email`, `groups`
  - Direct Access Grants: Enabled
  - Public Client: No (confidential)

- **Backstage Client:**
  - Client ID: `backstage`
  - Client Scopes: `openid`, `profile`, `email`, `groups`

### 2. Backstage Users Catalog
Updated users to match Keycloak emails:
```yaml
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: admin
spec:
  profile:
    displayName: Admin User
    email: admin@timedevops.click
  memberOf:
    - admins
---
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: test-user
spec:
  profile:
    displayName: Test User
    email: test-user@timedevops.click
  memberOf:
    - admins
```

### 3. Test User Credentials
- Username: `test-user`
- Password: `Test@2024!` (stored in `test-user-password` secret in `keycloak` namespace)

## Testing

### ArgoCD Login
1. Navigate to: https://argocd.timedevops.click
2. Click "LOG IN VIA KEYCLOAK"
3. Use credentials: `test-user` / `Test@2024!`
4. Expected: Successful login with user profile

### Backstage Login
1. Navigate to: https://backstage.timedevops.click
2. Click "Sign In"
3. Use credentials: `test-user` / `Test@2024!`
4. Expected: Successful login with user profile and catalog access

## Validation Results

All validation checks passed:
- ✓ Keycloak is accessible
- ✓ Admin token obtained
- ✓ Users found in Keycloak (admin, test-user)
- ✓ ArgoCD client configured with required scopes
- ✓ Backstage client configured
- ✓ Backstage users catalog updated
- ✓ ArgoCD OIDC configuration present
- ✓ Backstage API accessible

## Next Steps

1. **Manual Testing:** User should manually test both ArgoCD and Backstage logins via UI
2. **E2E Integration:** Add authentication validation to `scripts/e2e-mvp.sh`
3. **Documentation:** Update platform documentation with authentication setup
4. **Monitoring:** Add alerts for authentication failures

## Files Modified

- `scripts/fix-argocd-oidc.sh` (new)
- `scripts/validate-auth.sh` (new)
- `packages/backstage/users-catalog.yaml` (updated)

## Secrets Created

- `test-user-password` in `keycloak` namespace

## GitOps Considerations

- User catalog changes are persisted in Git (`packages/backstage/users-catalog.yaml`)
- Keycloak client scope configuration is done via API (not GitOps)
- For production, consider using Keycloak Operator or Terraform for client configuration

## Troubleshooting

### ArgoCD Login Still Fails
1. Run `bash scripts/fix-argocd-oidc.sh` again
2. Check ArgoCD logs: `kubectl logs -n argocd deployment/argocd-server`
3. Verify client secret: `kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.oidc\.keycloak\.clientSecret}' | base64 --decode`

### Backstage Login Still Fails
1. Verify user email in catalog: `kubectl exec -n backstage deployment/backstage -- cat /catalog/users-catalog.yaml`
2. Check Backstage logs: `kubectl logs -n backstage deployment/backstage`
3. Verify Keycloak user email: Use `scripts/validate-auth.sh`

### Keycloak Not Accessible
1. Check Keycloak pod: `kubectl get pods -n keycloak`
2. Check Ingress: `kubectl get ingress -n keycloak`
3. Verify DNS: `nslookup keycloak.timedevops.click`

## References

- [ArgoCD OIDC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#existing-oidc-provider)
- [Backstage Authentication](https://backstage.io/docs/auth/)
- [Keycloak Admin REST API](https://www.keycloak.org/docs-api/latest/rest-api/index.html)
