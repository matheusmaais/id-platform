# Authentication Test Guide - ArgoCD + Keycloak OIDC

## 🎯 Objetivo
Validar a integração OIDC entre ArgoCD e Keycloak

## 📋 Pré-requisitos

- ✅ ArgoCD instalado e acessível
- ✅ Keycloak instalado e acessível
- ✅ External DNS funcionando
- ✅ Ingress NGINX com TLS configurado

## 🔐 Credenciais

### ArgoCD Admin (Built-in)
```bash
Username: admin
Password: $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)
```

### Keycloak Admin
```bash
Username: admin
Password: changeme
```

## 🧪 Testes de Autenticação

### Teste 1: Login ArgoCD com Admin Local

1. Acesse: https://argocd.timedevops.click
2. Click em "LOGIN VIA KEYCLOAK" (se disponível) ou use admin/password
3. Verificar se consegue logar como admin local

**Resultado Esperado**: Login bem-sucedido com usuário admin

### Teste 2: Login ArgoCD via Keycloak OIDC

1. Acesse: https://argocd.timedevops.click
2. Click em "LOG IN VIA KEYCLOAK" ou "LOG IN VIA SSO"
3. Será redirecionado para https://keycloak.timedevops.click
4. Faça login com credenciais do Keycloak
5. Após autenticação, será redirecionado de volta ao ArgoCD

**Resultado Esperado**: Login bem-sucedido via OIDC

### Teste 3: Verificar Keycloak Realm

1. Acesse: https://keycloak.timedevops.click
2. Login como admin
3. Selecione realm "platform"
4. Verificar se client "argocd" existe
5. Verificar redirect URIs: `https://argocd.timedevops.click/*`

**Resultado Esperado**: Client configurado corretamente

## ✅ Checklist de Validação

- [ ] ArgoCD acessível via HTTPS
- [ ] Keycloak acessível via HTTPS
- [ ] Login ArgoCD com admin local funciona
- [ ] Botão "Login via Keycloak" aparece na tela de login
- [ ] Redirecionamento para Keycloak funciona
- [ ] Login via Keycloak funciona
- [ ] Usuário logado via OIDC aparece no ArgoCD
- [ ] Groups do Keycloak são mapeados para roles do ArgoCD

## 🔧 Configuração OIDC no ArgoCD

```yaml
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
  requestedIDTokenClaims:
    groups:
      essential: true
```

## 🔧 Keycloak Client Configuration

```json
{
  "clientId": "argocd",
  "enabled": true,
  "protocol": "openid-connect",
  "redirectUris": [
    "https://argocd.timedevops.click/*",
    "https://argocd.timedevops.click/auth/callback"
  ],
  "webOrigins": [
    "https://argocd.timedevops.click"
  ],
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": true,
  "publicClient": false
}
```

## 📝 Troubleshooting

### Problema: Botão de login OIDC não aparece
**Solução**:
```bash
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 20 "oidc.config"
```
Verificar se configuração OIDC está presente

### Problema: Erro ao redirecionar para Keycloak
**Solução**:
```bash
# Verificar DNS
dig +short keycloak.timedevops.click

# Verificar certificado
curl -vI https://keycloak.timedevops.click
```

### Problema: Erro "invalid redirect_uri"
**Solução**: Verificar no Keycloak se o redirect_uri está configurado corretamente

### Problema: Usuário não tem permissões no ArgoCD
**Solução**: Configurar RBAC policy no ArgoCD ConfigMap

## 🚀 Próximos Passos

1. Criar usuários de teste no Keycloak
2. Configurar groups no Keycloak
3. Mapear groups para roles no ArgoCD
4. Testar permissões granulares
