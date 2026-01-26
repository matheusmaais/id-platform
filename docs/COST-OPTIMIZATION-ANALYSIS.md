# Análise de Otimização de Custos - MVP

## 📊 Resumo Executivo

Análise realizada em: 2026-01-21
Objetivo: Verificar e otimizar configurações de instâncias EC2 e RDS para MVP com menor custo possível

---

## 🔍 EC2 - Análise Atual

### Bootstrap Nodes (Karpenter Controller)
**Arquivo:** `cluster/terraform/karpenter.tf`

**Configuração Atual:**
- Instâncias: `t3a.small`, `t3.small` (ON_DEMAND)
- Quantidade: 2 nodes (desired_size: 2)
- Custo estimado: ~$0.0184/hora × 2 × 730h = **~$27/mês**

**Status:** ✅ **Adequado para MVP**
- ON_DEMAND necessário para estabilidade do Karpenter controller
- t3a.small/t3.small são as menores instâncias viáveis para EKS nodes

**Otimização possível:**
- Considerar reduzir para 1 node mínimo (min_size: 1) se tolerar downtime durante updates
- Custo reduzido: ~$13.50/mês (50% de economia)

---

### Karpenter NodePool (Workload Nodes)
**Arquivo:** `platform/karpenter/nodepool.yaml`

**Configuração Atual:**
- Instâncias permitidas: 12 tipos diferentes
  - T3 family: t3a.medium, t3.medium, t3a.large, t3.large, t3a.xlarge, t3.xlarge
  - M5 family: m5.large, m5.xlarge, m5a.large, m5a.xlarge
  - M6i family: m6i.large, m6i.xlarge
- Limites: 20 vCPU, 80Gi RAM
- Capacity type: SPOT (preferido)

**Problema Identificado:** ⚠️
- Lista inclui instâncias grandes e caras (xlarge) desnecessárias para MVP
- M5/M6i são mais caras que T3 family
- Para MVP, devemos focar apenas nas menores instâncias

**Custos Estimados (SPOT - 70% desconto):**
| Instância | vCPU | RAM | Custo/hora (SPOT) | Custo/mês (SPOT) |
|-----------|------|-----|-------------------|------------------|
| t3a.small | 2 | 2GB | ~$0.0055 | ~$4 |
| t3.small | 2 | 2GB | ~$0.0066 | ~$4.80 |
| t3a.medium | 2 | 4GB | ~$0.011 | ~$8 |
| t3.medium | 2 | 4GB | ~$0.013 | ~$9.50 |
| t3a.large | 2 | 8GB | ~$0.022 | ~$16 |
| m5.large | 2 | 8GB | ~$0.033 | ~$24 |
| m5.xlarge | 4 | 16GB | ~$0.066 | ~$48 |
| m6i.xlarge | 4 | 16GB | ~$0.088 | ~$64 |

**Recomendação:** ✅ **OTIMIZAR**
- Remover instâncias grandes (large, xlarge)
- Remover famílias M5/M6i (mais caras)
- Manter apenas: t3a.small, t3.small, t3a.medium, t3.medium
- **Economia estimada:** Evita provisionamento acidental de instâncias caras

---

## 🗄️ RDS - Análise Atual

**Arquivo:** `cluster/terraform/rds-keycloak.tf`

**Configuração Atual:**
- Instância: `db.t4g.micro` (ARM Graviton2)
- Storage: 20GB gp3
- Backup: 1 dia
- Multi-AZ: false
- Custo estimado: **~$12-15/mês**

**Status:** ✅ **JÁ OTIMIZADO**
- db.t4g.micro é a instância RDS mais barata disponível
- ARM Graviton2 oferece melhor custo/performance
- Configuração já está otimizada para MVP

**Alternativas consideradas:**
- db.t3.micro: ~$14/mês (x86, mais caro)
- db.t4g.small: ~$24/mês (desnecessário para MVP)

---

## 📋 Recomendações de Otimização

### 1. EC2 Karpenter NodePool - Reduzir lista de instâncias

**Ação:** Remover instâncias grandes e caras do NodePool

**Arquivo:** `platform/karpenter/nodepool.yaml`

**Mudança:**
```yaml
# ANTES: 12 tipos de instâncias
values:
  - "t3a.medium"
  - "t3.medium"
  - "t3a.large"      # REMOVER
  - "t3.large"       # REMOVER
  - "t3a.xlarge"     # REMOVER
  - "t3.xlarge"      # REMOVER
  - "m5.large"       # REMOVER
  - "m5.xlarge"      # REMOVER
  - "m5a.large"      # REMOVER
  - "m5a.xlarge"     # REMOVER
  - "m6i.large"      # REMOVER
  - "m6i.xlarge"     # REMOVER

# DEPOIS: Apenas 4 tipos menores
values:
  - "t3a.small"     # ADICIONAR (menor custo)
  - "t3.small"       # ADICIONAR (fallback)
  - "t3a.medium"     # MANTER
  - "t3.medium"      # MANTER
```

**Benefícios:**
- ✅ Previne provisionamento acidental de instâncias caras
- ✅ Karpenter escolherá automaticamente a menor instância compatível
- ✅ Mantém flexibilidade com 4 opções (melhora disponibilidade SPOT)
- ✅ Compatível com limites: 20 vCPU, 80Gi RAM

---

### 2. EC2 Bootstrap Nodes - Reduzir mínimo (opcional)

**Ação:** Reduzir min_size de 2 para 1

**Arquivo:** `cluster/terraform/karpenter.tf`

**Mudança:**
```hcl
scaling_config {
  desired_size = 2
  min_size     = 1  # Reduzir de 2 para 1
  max_size     = 3
}
```

**Benefícios:**
- ✅ Economia: ~$13.50/mês (50% de redução)
- ⚠️ Trade-off: Menor disponibilidade durante updates

**Recomendação:** Manter min_size=2 para MVP (custo baixo e melhor disponibilidade)

---

## 💰 Estimativa de Custos - MVP Otimizado

### Cenário Atual (antes da otimização)
| Recurso | Quantidade | Custo/mês |
|---------|------------|-----------|
| Bootstrap nodes (ON_DEMAND) | 2 × t3a.small | ~$27 |
| Karpenter nodes (SPOT) | Variável (até 20 vCPU) | ~$8-64* |
| RDS db.t4g.micro | 1 | ~$14 |
| **TOTAL** | | **~$49-105/mês** |

*Depende de qual instância o Karpenter provisionar

### Cenário Otimizado (após otimização)
| Recurso | Quantidade | Custo/mês |
|---------|------------|-----------|
| Bootstrap nodes (ON_DEMAND) | 2 × t3a.small | ~$27 |
| Karpenter nodes (SPOT) | Variável (t3a.small a t3.medium) | ~$4-9* |
| RDS db.t4g.micro | 1 | ~$14 |
| **TOTAL** | | **~$45-50/mês** |

*Karpenter escolherá automaticamente a menor instância compatível

**Economia estimada:** ~$4-55/mês (dependendo do workload)

---

## ✅ Checklist de Implementação

- [x] Análise de configurações atuais
- [x] Identificação de oportunidades de otimização
- [ ] Aplicar otimização no NodePool (remover instâncias grandes)
- [ ] Validar configuração com `kubectl get nodepool`
- [ ] Monitorar custos após implementação

---

## 📚 Referências

- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [AWS RDS Pricing](https://aws.amazon.com/rds/pricing/)
- [Karpenter Best Practices](https://karpenter.sh/docs/concepts/node-pools/)
- [EKS Node Sizing Guide](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html)
