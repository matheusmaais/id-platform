# Análise de Compatibilidade com Instâncias Graviton (ARM)

## 📊 Resumo Executivo

**Status Atual:** ⚠️ **NÃO COMPATÍVEL** - Configuração atual restringe a arquitetura x86_64 (amd64)

**Potencial de Economia:** 💰 **~20% de redução de custo** usando instâncias Graviton (t4g/t3g)

**Esforço de Migração:** 🔧 **Médio** - Requer ajustes em scripts e configurações do Backstage

---

## 🔍 Análise Detalhada

### ✅ O que JÁ funciona com Graviton

1. **RDS PostgreSQL (Keycloak)**
   - ✅ **Já usa Graviton**: `db.t4g.micro` (ARM Graviton2)
   - ✅ Sem problemas de compatibilidade
   - ✅ Economia: ~$2-3/mês vs db.t3.micro

2. **Aplicações de Workload (Node.js, Python, Go)**
   - ✅ **Compatíveis** se imagens Docker forem multi-arch
   - ✅ Node.js: `node:18-alpine` - suporta ARM nativamente
   - ✅ Python: `python:3.11-slim` - suporta ARM nativamente
   - ✅ Go: Compilado com `CGO_ENABLED=0` - pode compilar para ARM

---

### ❌ Bloqueadores Identificados

#### 1. **Karpenter NodePool - Restrição de Arquitetura**

**Arquivo:** `platform/karpenter/nodepool.yaml`

**Problema:**
```yaml
# Linha 34-37
- key: kubernetes.io/arch
  operator: In
  values: ["amd64"]  # ❌ Restringe apenas x86_64
```

**Impacto:** Karpenter não provisionará nodes ARM mesmo que disponíveis

**Solução:** Adicionar `arm64` aos valores permitidos

---

#### 2. **Backstage - Dependências Hardcoded x86_64**

**Arquivos Afetados:**
- `packages/backstage/fix-git-libs.sh`
- `packages/backstage/fix-terraform.sh`
- `packages/backstage/values.yaml`

**Problemas Identificados:**

##### a) Terraform Download - Arquitetura Fixa
```bash
# fix-terraform.sh e fix-git-libs.sh
wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
# ❌ Sempre baixa versão amd64, mesmo em nodes ARM
```

**Solução:** Detectar arquitetura dinamicamente:
```bash
ARCH=$(uname -m)
case $ARCH in
  aarch64|arm64) TERRAFORM_ARCH="arm64" ;;
  x86_64|amd64) TERRAFORM_ARCH="amd64" ;;
esac
wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_${TERRAFORM_ARCH}.zip
```

##### b) Library Paths Hardcoded
```yaml
# packages/backstage/values.yaml (linha 58)
LD_LIBRARY_PATH: "/tools/lib/x86_64-linux-gnu"  # ❌ Path x86_64 fixo
```

**Solução:** Usar path dinâmico baseado em arquitetura:
```yaml
LD_LIBRARY_PATH: "/tools/lib/$(uname -m)-linux-gnu"
# ou detectar em runtime
```

##### c) Scripts de Fix com Paths x86_64
```bash
# fix-git-libs.sh
mkdir -p /tools/lib/x86_64-linux-gnu  # ❌ Path fixo
cp /lib/x86_64-linux-gnu/libc.so.6    # ❌ Path fixo
```

**Solução:** Detectar arquitetura e usar paths dinâmicos

---

#### 3. **Bootstrap Nodes - Instâncias x86_64**

**Arquivo:** `cluster/terraform/karpenter.tf`

**Configuração Atual:**
```hcl
instance_types = ["t3a.small", "t3.small"]  # ❌ Apenas x86_64
```

**Solução:** Adicionar instâncias Graviton:
```hcl
instance_types = ["t4g.small", "t3a.small", "t3.small"]
# t4g.small = Graviton2, ~20% mais barato
```

---

## 💰 Análise de Custos - Graviton vs x86_64

### Instâncias EC2 (SPOT - 70% desconto)

| Instância | Arquitetura | vCPU | RAM | Custo/hora (SPOT) | Custo/mês (SPOT) | Economia |
|-----------|-------------|------|-----|-------------------|------------------|----------|
| **t4g.small** | **ARM Graviton2** | **2** | **2GB** | **~$0.0044** | **~$3.20** | **✅ 20%** |
| t3a.small | x86_64 AMD | 2 | 2GB | ~$0.0055 | ~$4.00 | - |
| **t4g.medium** | **ARM Graviton2** | **2** | **4GB** | **~$0.0088** | **~$6.40** | **✅ 20%** |
| t3a.medium | x86_64 AMD | 2 | 4GB | ~$0.011 | ~$8.00 | - |

### Bootstrap Nodes (ON_DEMAND)

| Instância | Arquitetura | Custo/hora | Custo/mês | Economia |
|-----------|-------------|------------|-----------|----------|
| **t4g.small** | **ARM Graviton2** | **~$0.0168** | **~$12.30** | **✅ 20%** |
| t3a.small | x86_64 AMD | ~$0.0184 | ~$13.40 | - |

### RDS (já otimizado)

| Instância | Arquitetura | Custo/mês | Status |
|-----------|-------------|-----------|--------|
| db.t4g.micro | ARM Graviton2 | ~$12 | ✅ **Já em uso** |

---

## 📋 Plano de Migração para Graviton

### Fase 1: Preparação (Baixo Risco)

1. **Atualizar Karpenter NodePool**
   - Adicionar `arm64` à lista de arquiteturas permitidas
   - Adicionar instâncias `t4g.small` e `t4g.medium` à lista

2. **Atualizar Bootstrap Nodes**
   - Adicionar `t4g.small` como primeira opção
   - Manter `t3a.small` como fallback

**Arquivos:**
- `platform/karpenter/nodepool.yaml`
- `platform/karpenter/nodepool.yaml.tpl`
- `cluster/terraform/karpenter.tf`

---

### Fase 2: Backstage - Suporte Multi-Arch (Médio Risco)

1. **Atualizar Scripts de Instalação**
   - Detectar arquitetura dinamicamente
   - Baixar Terraform correto para arquitetura
   - Usar paths dinâmicos para bibliotecas

2. **Atualizar Values.yaml**
   - Tornar `LD_LIBRARY_PATH` dinâmico
   - Usar initContainer que detecta arquitetura

**Arquivos:**
- `packages/backstage/fix-git-libs.sh`
- `packages/backstage/fix-terraform.sh`
- `packages/backstage/values.yaml`

---

### Fase 3: Validação (Crítico)

1. **Testar Backstage em Node ARM**
   - Scaffolder Terraform funciona?
   - Git operations funcionam?
   - Integrações GitHub funcionam?

2. **Testar Aplicações**
   - Node.js apps rodam corretamente?
   - Python apps rodam corretamente?
   - Go apps rodam corretamente?

---

## ✅ Recomendações

### Para MVP (Agora)

**Opção 1: Híbrido (Recomendado)**
- ✅ Manter x86_64 para Backstage (evita riscos)
- ✅ Usar Graviton para workloads de aplicações (economia)
- ✅ RDS já usa Graviton (sem mudança)

**Benefícios:**
- Economia imediata em workloads (~20%)
- Zero risco para Backstage
- Migração gradual possível

**Implementação:**
- Criar NodePool separado para Backstage (x86_64)
- NodePool default permite ARM (para apps)

---

### Para Produção (Futuro)

**Opção 2: Full Graviton**
- Migrar Backstage para ARM após validação
- Usar Graviton em todos os nodes
- Economia total: ~20% em infraestrutura

**Requisitos:**
- Validar todos os scripts Backstage
- Testar scaffolder em ARM
- Garantir imagens multi-arch

---

## 🔧 Implementação Rápida (Híbrido)

### 1. Adicionar Suporte ARM ao NodePool (Mantém x86_64)

```yaml
# platform/karpenter/nodepool.yaml
requirements:
  # Arquitetura: permitir ambas
  - key: kubernetes.io/arch
    operator: In
    values: ["amd64", "arm64"]  # ✅ Adicionar arm64

  # Instâncias: adicionar Graviton
  - key: node.kubernetes.io/instance-type
    operator: In
    values:
      # Graviton (ARM) - mais baratas
      - "t4g.small"     # 2 vCPU, 2GB RAM - CHEAPEST
      - "t4g.medium"    # 2 vCPU, 4GB RAM
      # x86_64 (fallback)
      - "t3a.small"
      - "t3.small"
      - "t3a.medium"
      - "t3.medium"
```

### 2. NodeSelector para Backstage (Forçar x86_64)

```yaml
# packages/backstage/values.yaml
backstage:
  nodeSelector:
    kubernetes.io/arch: amd64  # ✅ Forçar x86_64 para Backstage
```

### 3. Aplicações Usam ARM Automaticamente

- Karpenter escolherá `t4g.small` (mais barata) quando compatível
- Aplicações Node.js/Python/Go funcionam em ARM sem mudanças

---

## 📊 Estimativa de Economia (Híbrido)

### Cenário Atual
- Bootstrap: 2× t3a.small (ON_DEMAND) = ~$27/mês
- Workloads: Variável (t3a.small a t3.medium SPOT) = ~$4-9/mês
- RDS: db.t4g.micro = ~$14/mês
- **Total: ~$45-50/mês**

### Cenário Híbrido (Graviton para Apps)
- Bootstrap: 2× t3a.small (ON_DEMAND) = ~$27/mês
- Workloads: Variável (t4g.small a t4g.medium SPOT) = ~$3.20-6.40/mês
- RDS: db.t4g.micro = ~$14/mês
- **Total: ~$44-47/mês**

**Economia: ~$1-3/mês (3-7%)** - Modesta, mas sem riscos

### Cenário Full Graviton (Futuro)
- Bootstrap: 2× t4g.small (ON_DEMAND) = ~$24.60/mês
- Workloads: Variável (t4g.small a t4g.medium SPOT) = ~$3.20-6.40/mês
- RDS: db.t4g.micro = ~$14/mês
- **Total: ~$42-45/mês**

**Economia: ~$3-8/mês (7-18%)** - Significativa, requer validação Backstage

---

## ⚠️ Riscos e Mitigações

### Riscos Identificados

1. **Backstage Scaffolder pode falhar em ARM**
   - **Risco:** Alto (dependências x86_64 hardcoded)
   - **Mitigação:** Manter Backstage em x86_64 (nodeSelector)

2. **Imagens Docker não multi-arch**
   - **Risco:** Médio (depende de imagens base)
   - **Mitigação:** Verificar imagens antes de migrar

3. **Bibliotecas nativas incompatíveis**
   - **Risco:** Baixo (Node.js/Python/Go são compatíveis)
   - **Mitigação:** Testar aplicações em ARM antes

---

## ✅ Conclusão

**Recomendação para MVP:**
1. ✅ **Implementar suporte híbrido** (Graviton para apps, x86_64 para Backstage)
2. ✅ **Economia imediata:** ~3-7% sem riscos
3. ✅ **Migração futura:** Full Graviton após validação Backstage

**Não há problema em usar Graviton para:**
- ✅ Aplicações Node.js/Python/Go
- ✅ RDS (já em uso)
- ✅ Workloads gerais

**Evitar Graviton para:**
- ⚠️ Backstage (até corrigir scripts)
- ⚠️ Qualquer workload com dependências nativas x86_64

---

## 📚 Referências

- [AWS Graviton Processors](https://aws.amazon.com/ec2/graviton/)
- [Karpenter Architecture Support](https://karpenter.sh/docs/concepts/node-pools/#architecture)
- [Terraform ARM64 Downloads](https://releases.hashicorp.com/terraform/)
- [Docker Multi-Arch Images](https://docs.docker.com/build/building/multi-platform/)
