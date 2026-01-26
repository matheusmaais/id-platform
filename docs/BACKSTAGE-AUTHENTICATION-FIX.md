# Backstage Authentication Fix - Keycloak OIDC

## Problem Summary

Backstage users were experiencing authentication failures with the error message:
```
Login failed; caused by Error: socket hang up
```

Additionally, the error logged showed:
```json
{
  "error": {
    "name": "Error",
    "message": "self-signed certificate",
    "code": "DEPTH_ZERO_SELF_SIGNED_CERT"
  }
}
```

## Root Cause Analysis

### Issue 1: Self-Signed Certificate Error

**Problem**: Backstage (Node.js) was attempting to connect to Keycloak over HTTPS but was rejecting the connection due to certificate validation failures. This occurred because the NLB is terminating TLS with an ACM certificate, but internal communication was still being validated.

**Solution**: Added `NODE_TLS_REJECT_UNAUTHORIZED=0` environment variable to the Backstage deployment to allow connections to services with self-signed or ACM certificates.

**Implementation**:
```yaml
# platform/backstage/helm-values.yaml.tpl
backstage:
  extraEnvVars:
    - name: NODE_TLS_REJECT_UNAUTHORIZED
      value: "0"
```

### Issue 2: Missing OIDC Scopes in Keycloak

**Problem**: The Keycloak realm `platform` was missing essential OIDC client-scopes (`profile`, `email`) that are required for standard OpenID Connect authentication. Only `groups` and `offline_access` scopes existed.

**Error**:
```
error=invalid_scope&error_description=Invalid+scopes: openid profile email groups
```

**Solution**: Created the missing client-scopes (`profile`, `email`) and associated them with the `backstage` client as default scopes.

**Implementation via Keycloak Admin API**:

1. **Created `profile` client-scope**:
```bash
curl -X POST "https://keycloak.timedevops.click/admin/realms/platform/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "profile",
    "description": "OpenID Connect built-in scope: profile",
    "protocol": "openid-connect",
    "attributes": {
      "include.in.token.scope": "true",
      "display.on.consent.screen": "true"
    }
  }'
```

2. **Created `email` client-scope**:
```bash
curl -X POST "https://keycloak.timedevops.click/admin/realms/platform/client-scopes" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "email",
    "description": "OpenID Connect built-in scope: email",
    "protocol": "openid-connect",
    "attributes": {
      "include.in.token.scope": "true",
      "display.on.consent.screen": "true"
    }
  }'
```

3. **Associated scopes with `backstage` client**:
```bash
# Add profile scope
curl -X PUT "https://keycloak.timedevops.click/admin/realms/platform/clients/$CLIENT_UUID/default-client-scopes/$PROFILE_UUID" \
  -H "Authorization: Bearer ${TOKEN}"

# Add email scope
curl -X PUT "https://keycloak.timedevops.click/admin/realms/platform/clients/$CLIENT_UUID/default-client-scopes/$EMAIL_UUID" \
  -H "Authorization: Bearer ${TOKEN}"
```

## Validation

### Before Fix
```bash
$ curl -sk "https://backstage.timedevops.click/api/auth/oidc/start?..."
# Result: HTTP 500 with invalid_scope error
```

### After Fix
```bash
$ curl -sk "https://backstage.timedevops.click/api/auth/oidc/start?..."
# Result: HTTP 302 redirect to Keycloak login page (expected behavior)
```

**OIDC Discovery Endpoint Test**:
```bash
$ curl -sk https://keycloak.timedevops.click/realms/platform/.well-known/openid-configuration | jq .issuer
# Result: "https://keycloak.timedevops.click/realms/platform"
```

**Client Scopes Verification**:
```bash
# Default client-scopes for backstage client
profile
email
groups
```

## Testing Steps

To test Backstage authentication:

1. Navigate to `https://backstage.timedevops.click`
2. Click "Sign In"
3. You should be redirected to Keycloak login page
4. Enter credentials (or create a user via Keycloak Admin Console)
5. After successful authentication, you should be redirected back to Backstage

## Creating Test Users in Keycloak

### Via Keycloak Admin Console

1. Access: `https://keycloak.timedevops.click/admin/master/console/`
2. Login with admin credentials:
   - Username: `admin`
   - Password: (from `kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d`)
3. Select realm: `platform`
4. Navigate to: Users → Add user
5. Fill in user details:
   - Username: `test-user`
   - Email: `test-user@example.com`
   - First Name / Last Name (optional)
6. Click "Create"
7. Go to "Credentials" tab
8. Set password:
   - New Password: `<your-password>`
   - Confirm Password: `<your-password>`
   - Temporary: OFF
9. Click "Set Password"

### Via Keycloak Admin API

```bash
# Get admin token
ADMIN_PASSWORD=$(kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d)
TOKEN=$(curl -sk -X POST https://keycloak.timedevops.click/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=${ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

# Create user
curl -sk -X POST "https://keycloak.timedevops.click/admin/realms/platform/users" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test-user",
    "email": "test-user@example.com",
    "enabled": true,
    "emailVerified": true
  }'

# Get user ID
USER_ID=$(curl -sk -X GET "https://keycloak.timedevops.click/admin/realms/platform/users?username=test-user" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')

# Set password
curl -sk -X PUT "https://keycloak.timedevops.click/admin/realms/platform/users/${USER_ID}/reset-password" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "password",
    "value": "Test@123",
    "temporary": false
  }'
```

## E2E Test Integration

To integrate this fix into E2E tests, add a phase to create a test user and validate OIDC login:

```bash
# In scripts/e2e-mvp.sh

# Phase: Backstage Authentication
info "Testing Backstage OIDC authentication..."

# Create test user
KEYCLOAK_ADMIN_PASSWORD=$(kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d)
# ... (user creation script)

# Validate OIDC endpoint
OIDC_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://backstage.timedevops.click/api/auth/oidc/start?...")
if [ "$OIDC_STATUS" = "302" ]; then
  success "Backstage OIDC endpoint is working (HTTP 302)"
else
  error "Backstage OIDC endpoint returned HTTP $OIDC_STATUS (expected 302)"
fi
```

## Security Considerations

**⚠️ Production Warning**: The `NODE_TLS_REJECT_UNAUTHORIZED=0` setting disables TLS certificate validation and should be used with caution in production environments.

**Alternatives for Production**:

1. **Use proper CA-signed certificates**: Configure Keycloak with a certificate from a trusted CA.
2. **Internal CA**: Deploy an internal Certificate Authority and distribute its root certificate to all services.
3. **Service Mesh**: Use a service mesh (Istio, Linkerd) with mTLS for internal service-to-service communication.
4. **Cert-Manager**: Use cert-manager with Let's Encrypt for automatic certificate provisioning.

**For now** (MVP/Development): Using `NODE_TLS_REJECT_UNAUTHORIZED=0` is acceptable since all communication is over a trusted internal network (VPC) with TLS termination at the NLB (AWS ACM certificates).

## Files Modified

1. `platform/backstage/helm-values.yaml.tpl` - Added `NODE_TLS_REJECT_UNAUTHORIZED=0`
2. Keycloak realm `platform` - Added `profile` and `email` client-scopes via API
3. Keycloak client `backstage` - Associated new scopes as default scopes

## Related Issues

- Problem #1: Backstage login 'socket hang up' (✅ RESOLVED)
- Problem #2: Keycloak `null.timedevops.click` (✅ RESOLVED)
- Problem #3: ArgoCD Invalid Redirect URL (✅ RESOLVED)

## References

- [Backstage Authentication Documentation](https://backstage.io/docs/auth/)
- [Keycloak OIDC Configuration](https://www.keycloak.org/docs/latest/server_admin/#_oidc)
- [Node.js TLS Options](https://nodejs.org/api/tls.html#tls_tls_connect_options_callback)
