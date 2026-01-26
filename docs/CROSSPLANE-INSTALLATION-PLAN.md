# Crossplane Installation Plan - Simplified Approach

## 🎯 Objetivo
Instalar Crossplane com AWS Provider usando IRSA (sem credenciais estáticas)

## 📋 Análise do Problema Atual

### Problemas Identificados:
1. ❌ Helm values muito complexo (packageCache customizado causando deadlock)
2. ❌ Init containers esperando CRDs que não podem ser criados
3. ❌ Tentativa de instalar providers via Helm values (não é o padrão)
4. ❌ Timeout muito curto (60s) no init container

### Lições Aprendidas:
- Crossplane deve ser instalado de forma MINIMALISTA
- Providers devem ser instalados APÓS o core estar pronto
- Usar configurações padrão do Helm chart oficial

## 🛠️ Plano de Execução Simplificado

### Fase 1: Preparação (✅ JÁ FEITO)
- [x] IRSA role criado via Terraform
- [x] Outputs do Terraform disponíveis
- [x] Namespace será criado pelo Helm automaticamente

### Fase 2: Instalação Crossplane Core
**Estratégia**: Usar valores MÍNIMOS do Helm

```yaml
# Apenas o essencial:
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "<ARN_DO_IRSA>"

# Deixar tudo mais no padrão
```

**Comandos**:
```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version 1.18.3 \
  --values platform/crossplane/helm-values.yaml \
  --wait \
  --timeout 5m
```

**Validação**:
```bash
kubectl wait --for=condition=available --timeout=300s \
  deployment/crossplane -n crossplane-system
```

### Fase 3: Instalar AWS Provider (Family)
**Estratégia**: Usar o provider-family-aws que já inclui tudo

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: upbound-provider-aws
spec:
  package: xpkg.upbound.io/upbound/provider-family-aws:v1.16.0
```

**Aguardar** provider ficar healthy (pode levar 2-3 minutos):
```bash
kubectl wait --for=condition=Healthy provider/upbound-provider-aws \
  --timeout=300s
```

### Fase 4: Configurar ProviderConfig com IRSA
```yaml
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: IRSA
```

### Fase 5: Validar com S3 Bucket
```yaml
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: crossplane-test-bucket
spec:
  forProvider:
    region: us-east-1
  providerConfigRef:
    name: default
```

**Validação**:
```bash
kubectl get bucket
kubectl describe bucket crossplane-test-bucket
aws s3 ls | grep crossplane-test
```

## 📝 Arquivos a Criar/Modificar

1. **platform/crossplane/helm-values.yaml.tpl** - SIMPLIFICAR drasticamente
2. **platform/crossplane/provider-aws.yaml** - Provider Family AWS
3. **platform/crossplane/providerconfig.yaml.tpl** - ProviderConfig com IRSA
4. **platform/crossplane/examples/s3-bucket-test.yaml** - Teste simples
5. **scripts/install-crossplane.sh** - Script sequencial e claro

## ⚠️ Pontos Críticos

1. **NÃO customizar packageCache** - usar padrão
2. **NÃO instalar providers via Helm** - usar kubectl apply depois
3. **AGUARDAR cada fase** antes de prosseguir
4. **Provider Family** é melhor que providers individuais
5. **Timeouts adequados** - 5min para install, 5min para provider

## ✅ Critérios de Sucesso

- [ ] Crossplane core instalado e healthy
- [ ] Provider AWS instalado e healthy
- [ ] ProviderConfig aplicado
- [ ] S3 bucket criado via Crossplane
- [ ] Bucket visível no AWS Console
- [ ] Tudo funcionando com IRSA (sem credenciais estáticas)
