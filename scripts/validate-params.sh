#!/bin/bash
set -e

echo "=== Validating Platform Parameters ==="
echo ""

# Check config file
echo "1. Git config file..."
if [ ! -f "config/platform-params.yaml" ]; then
  echo "❌ config/platform-params.yaml not found"
  exit 1
fi
echo "✅ config/platform-params.yaml exists"

# Check ConfigMap
echo ""
echo "2. Kubernetes ConfigMap..."
if ! kubectl get configmap platform-params -n argocd &>/dev/null; then
  echo "❌ ConfigMap platform-params not found in argocd namespace"
  echo "   Run: cd terraform/platform-gitops && terraform apply"
  exit 1
fi
echo "✅ ConfigMap platform-params exists"

# Check ApplicationSet
echo ""
echo "3. ApplicationSet..."
if ! kubectl get applicationset platform-apps -n argocd &>/dev/null; then
  echo "❌ ApplicationSet platform-apps not found"
  echo "   Run: make bootstrap-platform"
  exit 1
fi
echo "✅ ApplicationSet platform-apps exists"

# Extract and display values
echo ""
echo "=== Current Configuration ==="
echo ""
echo "📝 Git Params (config/platform-params.yaml):"
if command -v yq &> /dev/null; then
  yq eval '.repository' config/platform-params.yaml
else
  echo "   (yq not installed, skipping pretty print)"
  grep -A 5 "^repository:" config/platform-params.yaml || true
fi

echo ""
echo "☸️  ConfigMap Params (platform-params):"
if command -v jq &> /dev/null; then
  kubectl get configmap platform-params -n argocd -o jsonpath='{.data}' | jq
else
  echo "   (jq not installed, showing raw data)"
  kubectl get configmap platform-params -n argocd -o jsonpath='{.data}'
  echo ""
fi

echo ""
echo "🚀 ApplicationSet Status:"
kubectl get applicationset platform-apps -n argocd -o wide

echo ""
echo "📦 Generated Applications:"
kubectl get applications -n argocd -o wide

echo ""
echo "✅ All validations passed!"
echo ""
echo "Next steps:"
echo "  - Apply Terraform: cd terraform/platform-gitops && terraform apply"
echo "  - Deploy Backstage: make install-backstage"
echo "  - Validate platform: make validate-platform"
