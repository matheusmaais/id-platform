# Backstage SSO Setup - Complete

**Date:** 2026-01-27  
**Status:** ✅ COMPLETE  
**Authentication:** Cognito OIDC

## Summary

Backstage is now fully configured with Cognito OIDC authentication. Guest login has been disabled and users will be redirected to Cognito for authentication.

## Configuration Applied

### 1. Sign-In Page Configuration
```yaml
# platform-apps/backstage/values.yaml
appConfig:
  app:
    signInPage: oidc  # Must be under app: section
```

### 2. Cognito Secret (Complete)
```bash
kubectl get secret backstage-cognito -n backstage
# Contains:
# - COGNITO_CLIENT_ID
# - COGNITO_CLIENT_SECRET  
# - COGNITO_ISSUER
```

### 3. Auth Provider Configuration
```yaml
auth:
  environment: development
  providers:
    oidc:
      development:
        metadataUrl: ${COGNITO_ISSUER}/.well-known/openid-configuration
        clientId: ${COGNITO_CLIENT_ID}
        clientSecret: ${COGNITO_CLIENT_SECRET}
        prompt: auto
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail
```

## Validation

```bash
# Application Status
kubectl get application backstage -n argocd
# NAME        SYNC STATUS   HEALTH STATUS
# backstage   Synced        Healthy

# Pod Status
kubectl get pods -n backstage
# NAME                         READY   STATUS    RESTARTS   AGE
# backstage-86b84757cb-ggvzw   1/1     Running   0          5m

# Config Verification
kubectl exec -n backstage deployment/backstage -- \
  cat /app/app-config-from-configmap.yaml | grep -A 2 "app:"
# app:
#   baseUrl: https://backstage.timedevops.click
#   signInPage: oidc

# Environment Variables
kubectl exec -n backstage deployment/backstage -- env | grep COGNITO
# COGNITO_CLIENT_ID=oseg1vj7ai3usqafrjtpor4e7
# COGNITO_CLIENT_SECRET=***
# COGNITO_ISSUER=https://cognito-idp.us-east-1.amazonaws.com/us-east-1_75myDdDAc
```

## Testing SSO Login

### 1. Access Backstage
Navigate to: https://backstage.timedevops.click

### 2. Expected Behavior
- **Before:** "Enter as a Guest User" option visible
- **After:** Automatic redirect to Cognito login page

### 3. Cognito Login
- URL: `https://idp-poc-darede.auth.us-east-1.amazoncognito.com`
- Email: `admin@timedevops.click`
- Password: (from Terraform output)

### 4. Get Admin Credentials
```bash
cd terraform/platform-gitops
terraform output -json cognito_admin_credentials | jq -r
```

### 5. Post-Login
- User should be redirected back to Backstage
- Identity verified via Cognito
- Email resolver matches user entity in catalog

## Troubleshooting

### Issue: Still Showing Guest Login

**Cause:** `signInPage` in wrong location (root instead of `app:`)

**Fix:**
```yaml
# WRONG
appConfig:
  app:
    title: ...
  signInPage: oidc  # ❌ Wrong location

# CORRECT
appConfig:
  app:
    title: ...
    signInPage: oidc  # ✅ Correct location
```

### Issue: 401 Errors on Catalog API

**Cause:** Missing COGNITO_ISSUER environment variable

**Fix:**
```bash
# Check secret
kubectl get secret backstage-cognito -n backstage -o jsonpath='{.data}' | jq -r 'keys[]'

# Should show:
# COGNITO_CLIENT_ID
# COGNITO_CLIENT_SECRET
# COGNITO_ISSUER

# If missing, patch:
kubectl patch secret backstage-cognito -n backstage \
  --type='json' \
  -p='[{"op": "add", "path": "/data/COGNITO_ISSUER", "value": "'$(echo -n "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_75myDdDAc" | base64)'"}]'
```

### Issue: ConfigMap Not Updating

**Cause:** ArgoCD not syncing changes from Git

**Fix:**
```bash
# Force ConfigMap recreation
kubectl delete configmap backstage-app-config -n backstage

# Wait for ArgoCD to recreate it
sleep 10

# Restart pod
kubectl delete pod -n backstage -l app.kubernetes.io/name=backstage
```

## Architecture

```
User Browser
    ↓
    ↓ (1) Access https://backstage.timedevops.click
    ↓
Backstage Frontend (signInPage: oidc)
    ↓
    ↓ (2) Redirect to Cognito
    ↓
Cognito Hosted UI
    ↓
    ↓ (3) User authenticates
    ↓
Backstage Backend (/api/auth/oidc/handler/frame)
    ↓
    ↓ (4) Validate token with Cognito
    ↓
    ↓ (5) Resolve user via emailMatchingUserEntityProfileEmail
    ↓
Backstage Catalog (user entity matched)
    ↓
    ↓ (6) Return to frontend with session
    ↓
User sees Backstage with verified identity
```

## Security Considerations

### 1. OIDC Flow
- Authorization Code flow with PKCE
- Tokens validated against Cognito
- Session managed by Backstage backend

### 2. User Resolution
- Email from Cognito ID token
- Matched against catalog user entities
- If no match, user has limited access

### 3. Secrets Management
- Client secret stored in Kubernetes secret
- Mounted as environment variables
- Not exposed to frontend

### 4. HTTPS Only
- All traffic over TLS
- ACM certificate on ALB
- No plain HTTP allowed

## Next Steps

### 1. Create User Entities in Catalog
```yaml
# catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: admin
spec:
  profile:
    displayName: Admin User
    email: admin@timedevops.click
  memberOf: [platform-team]
```

### 2. Configure RBAC (Optional)
```yaml
# app-config.yaml
permission:
  enabled: true
  policy:
    - allow: [catalog.entity.read]
      for: [user:default/admin]
```

### 3. Add More Users to Cognito
```bash
aws cognito-idp admin-create-user \
  --user-pool-id us-east-1_75myDdDAc \
  --username user@example.com \
  --user-attributes Name=email,Value=user@example.com \
  --message-action SUPPRESS
```

### 4. Configure User Groups
```bash
# Create group
aws cognito-idp create-group \
  --group-name developers \
  --user-pool-id us-east-1_75myDdDAc

# Add user to group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id us-east-1_75myDdDAc \
  --username user@example.com \
  --group-name developers
```

## Commits

- `356814b` - Initial signInPage configuration (wrong location)
- `5ceb601` - Added COGNITO_ISSUER to Terraform secret
- `94b0b32` - Fixed signInPage location (moved to app section)

## References

- [Backstage Auth Documentation](https://backstage.io/docs/auth/)
- [Backstage OIDC Provider](https://backstage.io/docs/auth/oidc/provider)
- [AWS Cognito OIDC](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-oidc-flow.html)
- [ArgoCD Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)

## Support

For issues or questions:
1. Check `docs/TROUBLESHOOTING-BACKSTAGE.md`
2. Check `docs/STATE.md` for current status
3. Review logs: `kubectl logs -n backstage -l app.kubernetes.io/name=backstage`
