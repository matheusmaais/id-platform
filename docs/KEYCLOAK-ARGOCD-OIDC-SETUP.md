# Keycloak OIDC Setup for ArgoCD

## Problem
ArgoCD login fails with `invalid_scope: Invalid scopes: openid profile email groups`

## Root Cause
ArgoCD client in Keycloak is missing required OIDC scopes. These scopes are necessary for ArgoCD to authenticate users via Keycloak and retrieve user information.

## Solution

### Prerequisites
- Keycloak installed and accessible
- ArgoCD installed with OIDC configured in `argocd-cm` ConfigMap
- `jq`, `curl`, `yq` installed locally or in CI/CD environment
- Test user already created in Keycloak (from `scripts/create-keycloak-test-user.sh`)

### Steps

#### 1. Create Client Scopes

```bash
bash scripts/create-keycloak-argocd-scopes.sh
```

This script creates the following client scopes in Keycloak:
- `openid` - Required for OpenID Connect authentication
- `profile` - Provides user profile information (name, username)
- `email` - Provides user email address
- `groups` - Provides user group memberships for RBAC

#### 2. Associate Scopes with ArgoCD Client

```bash
bash scripts/associate-argocd-client-scopes.sh
```

This script associates all required scopes with the `argocd` client as default client scopes, ensuring they are automatically included in token requests.

#### 3. Restart ArgoCD Server

```bash
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=120s
```

#### 4. Validate OIDC Login

```bash
bash scripts/validate-argocd-oidc.sh
```

This script performs an OAuth2 password grant flow to verify that:
- Token can be obtained successfully
- All required scopes are present in the token
- Token contains necessary claims for ArgoCD authentication

#### 5. Manual Test

1. Open `https://argocd.timedevops.click` (or your ArgoCD URL)
2. Click "LOG IN VIA KEYCLOAK"
3. Authenticate with test user credentials:
   - Username: `test-user`
   - Password: `Test@123456`
4. Should successfully redirect to ArgoCD UI

## Verification

### Check ArgoCD Server Logs

```bash
kubectl logs -n argocd deployment/argocd-server | grep -i oidc
```

Look for successful OIDC authentication messages and no `invalid_scope` errors.

### Verify Client Scopes in Keycloak Admin Console

1. Navigate to: Keycloak Admin Console → Clients → argocd → Client Scopes tab
2. Should see in "Default Client Scopes" section:
   - openid
   - profile
   - email
   - groups

### Check ArgoCD ConfigMap

```bash
kubectl get cm argocd-cm -n argocd -o yaml
```

Verify OIDC configuration includes:
```yaml
data:
  url: https://argocd.timedevops.click
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.timedevops.click/realms/platform
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
```

## Troubleshooting

### Still Getting `invalid_scope` Error

1. **Check ArgoCD ConfigMap has correct issuer URL:**
   ```bash
   kubectl get cm argocd-cm -n argocd -o yaml | grep issuer
   ```
   Should match: `https://keycloak.timedevops.click/realms/platform`

2. **Verify Keycloak realm name:**
   ```bash
   # Should be 'platform'
   curl -sk https://keycloak.timedevops.click/realms/platform/.well-known/openid-configuration | jq '.issuer'
   ```

3. **Check client secret matches:**
   ```bash
   # Get from Keycloak
   # Get from ArgoCD secret
   kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.oidc\.keycloak\.clientSecret}' | base64 --decode
   ```

### Token Missing Claims

1. **Check client scope mappers in Keycloak:**
   - Navigate to: Keycloak Admin Console → Client Scopes → profile/email/groups
   - Ensure mappers are configured and enabled

2. **Verify scopes are set to "Include in token scope":**
   - Each client scope should have `include.in.token.scope` attribute set to `true`

### ArgoCD Shows "User Not Authorized"

1. **Check ArgoCD RBAC policy:**
   ```bash
   kubectl get cm argocd-rbac-cm -n argocd -o yaml
   ```

2. **Add policy for test user or group:**
   ```yaml
   data:
     policy.csv: |
       g, test-user, role:admin
       # Or for groups:
       g, platform-admins, role:admin
   ```

## Related Documentation

- [Backstage OIDC Authentication Fix](BACKSTAGE-AUTHENTICATION-FIX.md) - Similar issue resolved for Backstage
- [Keycloak Admin API Documentation](https://www.keycloak.org/docs/latest/server_admin/)
- [ArgoCD OIDC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#existing-oidc-provider)

## Automation Notes

For production environments, consider:

1. **Keycloak Realm Export/Import**: Export the configured realm and import during installation
2. **Infrastructure as Code**: Use Terraform with the Keycloak provider
3. **Init Container**: Add an init container to Keycloak StatefulSet that runs these scripts
4. **External Secrets Operator**: Manage Keycloak configuration as Kubernetes secrets

For MVP/PoC, the manual scripts approach is acceptable and provides clear audit trail.
