# ${{ values.name }}

${{ values.description }}

## Overview

This application was generated using the Internal Developer Platform.

- **Owner**: ${{ values.owner }}
- **Type**: Node.js Express Application
- **Deployment**: GitOps via ArgoCD

## Quick Start

### Local Development

```bash
npm install
npm run dev
```

The application will be available at `http://localhost:3000`.

### Endpoints

- `GET /` - Application info
- `GET /health` - Health check
- `GET /ready` - Readiness check
- `GET /metrics` - Prometheus metrics

## Deployment

### Pipeline

The CI/CD pipeline runs automatically on every push to `main`:

1. Build Docker image
2. Push to ECR: `${{ values.ecrRegistry }}/${{ values.ciEcrRepoPrefix }}${{ values.name }}`
3. Update Kubernetes manifest with new image tag (in `${{ values.manifestsPath }}`)
4. ArgoCD syncs automatically

**CI auth**: OIDC (no long-lived credentials)

### Monitoring

- **ArgoCD**: https://argocd.${{ values.domain }}/applications/${{ values.repoPrefix }}${{ values.name }}
- **Backstage**: Component catalog
{% if values.exposePublic %}
- **Application**: https://${{ values.name }}.${{ values.domain }}
{% endif %}

### Configuration

- **Replicas**: ${{ values.replicas }}
{% if values.exposePublic %}
- **Public Access**: Yes (https://${{ values.name }}.${{ values.domain }})
{% else %}
- **Public Access**: No (ClusterIP only)
{% endif %}

## Architecture

- **Platform**: AWS EKS (${{ values.clusterName }})
- **Region**: ${{ values.awsRegion }}
- **Namespace**: ${{ values.appNamespace }}
- **Image Registry**: ECR
{% if values.exposePublic %}
- **Ingress**: ALB (shared: ${{ values.albGroupName }})
{% endif %}

## Links

- [Repository](https://github.com/${{ values.githubOrg }}/${{ values.repoPrefix }}${{ values.name }})
- [CI Pipeline](https://github.com/${{ values.githubOrg }}/${{ values.repoPrefix }}${{ values.name }}/actions)
- [ArgoCD](https://argocd.${{ values.domain }}/applications/${{ values.repoPrefix }}${{ values.name }})
