#!/bin/bash
set -e

echo "=== Validating Platform Parameters ==="
echo ""

# Check .env (sensitive only)
echo "0. Environment file..."
if [ ! -f ".env" ]; then
  echo "❌ .env not found"
  echo "   Create .env with sensitive values only (GITHUB_TOKEN, COGNITO_ADMIN_TEMP_PASSWORD)"
  exit 1
fi
echo "✅ .env exists"

# Load .env
set -a
# shellcheck disable=SC1091
source .env
set +a

# Required env vars
required_vars=(
  "GITHUB_TOKEN"
  "COGNITO_ADMIN_TEMP_PASSWORD"
)

echo ""
echo "0.1 Required environment variables..."
missing=false
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ Missing env var: ${var}"
    missing=true
  else
    echo "✅ ${var} is set"
  fi
done
if [ "${missing}" = "true" ]; then
  echo "   Fix .env and rerun."
  exit 1
fi

# Password policy validation
echo ""
echo "0.2 Cognito admin password policy..."
pw="${COGNITO_ADMIN_TEMP_PASSWORD}"
pw_ok=true

if [ "${#pw}" -lt 12 ]; then
  echo "❌ Password length must be >= 12"
  pw_ok=false
fi
if ! [[ "${pw}" =~ [A-Z] ]]; then
  echo "❌ Password must contain an uppercase letter"
  pw_ok=false
fi
if ! [[ "${pw}" =~ [a-z] ]]; then
  echo "❌ Password must contain a lowercase letter"
  pw_ok=false
fi
if ! [[ "${pw}" =~ [0-9] ]]; then
  echo "❌ Password must contain a number"
  pw_ok=false
fi
if ! [[ "${pw}" =~ [^A-Za-z0-9] ]]; then
  echo "❌ Password must contain a symbol"
  pw_ok=false
fi

if [ "${pw_ok}" = "false" ]; then
  echo "   Fix COGNITO_ADMIN_TEMP_PASSWORD in .env and rerun."
  exit 1
fi
echo "✅ Cognito admin password meets policy"

# Email format validation moved to config validation

# Check config file
echo "1. Git config file..."
if [ ! -f "config/platform-params.yaml" ]; then
  echo "❌ config/platform-params.yaml not found"
  exit 1
fi
echo "✅ config/platform-params.yaml exists"

# Load config values
CONFIG_DOMAIN=$(yq eval '.infrastructure.domain' config/platform-params.yaml 2>/dev/null)
CONFIG_CLUSTER=$(yq eval '.infrastructure.clusterName' config/platform-params.yaml 2>/dev/null)
CONFIG_REGION=$(yq eval '.infrastructure.awsRegion' config/platform-params.yaml 2>/dev/null)
CONFIG_PROFILE=$(yq eval '.infrastructure.awsProfile' config/platform-params.yaml 2>/dev/null)
CONFIG_EMAIL=$(yq eval '.identity.cognitoAdminEmail' config/platform-params.yaml 2>/dev/null)
CONFIG_REPO=$(yq eval '.repository.url' config/platform-params.yaml 2>/dev/null)
CONFIG_GH_ACTIONS_ROLE=$(yq eval '.github.actionsRoleName' config/platform-params.yaml 2>/dev/null)
CONFIG_GH_REPO_REGEX=$(yq eval '.github.repoRegex' config/platform-params.yaml 2>/dev/null)
CONFIG_APPS_PATH=$(yq eval '.apps.manifestsPath' config/platform-params.yaml 2>/dev/null)
CONFIG_APPS_NS_STRATEGY=$(yq eval '.apps.namespace.strategy' config/platform-params.yaml 2>/dev/null)
CONFIG_APPS_NS_TEMPLATE=$(yq eval '.apps.namespace.template' config/platform-params.yaml 2>/dev/null)
CONFIG_ALB_SHARED_GROUP=$(yq eval '.alb.sharedGroupName' config/platform-params.yaml 2>/dev/null)
CONFIG_CI_AUTH_MODE=$(yq eval '.ci.authMode' config/platform-params.yaml 2>/dev/null)
CONFIG_CI_ECR_PREFIX=$(yq eval '.ci.ecrRepoPrefix' config/platform-params.yaml 2>/dev/null)
CONFIG_CI_TAG_STRATEGY=$(yq eval '.ci.imageTagStrategy' config/platform-params.yaml 2>/dev/null)
CONFIG_APP_DEFAULT_ARCH=$(yq eval '.apps.defaults.arch' config/platform-params.yaml 2>/dev/null)
CONFIG_BUILD_PLATFORM_ARM64=$(yq eval '.ci.build.platforms.arm64' config/platform-params.yaml 2>/dev/null)
CONFIG_BUILD_PLATFORM_AMD64=$(yq eval '.ci.build.platforms.amd64' config/platform-params.yaml 2>/dev/null)
CONFIG_BUILD_PLATFORM_MULTI=$(yq eval '.ci.build.platforms.multi' config/platform-params.yaml 2>/dev/null)
CONFIG_SCHED_ARCH_LABEL=$(yq eval '.scheduling.archLabelKey' config/platform-params.yaml 2>/dev/null)
CONFIG_SCHED_ARM_VALUE=$(yq eval '.scheduling.armValue' config/platform-params.yaml 2>/dev/null)
CONFIG_SCHED_AMD_VALUE=$(yq eval '.scheduling.amdValue' config/platform-params.yaml 2>/dev/null)

echo ""
echo "1.1 Config required fields..."
missing_cfg=false

check_cfg() {
  key="$1"
  val="$2"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "❌ Missing config field: ${key}"
    missing_cfg=true
  else
    echo "✅ ${key} is set"
  fi
}

check_cfg "infrastructure.domain" "$CONFIG_DOMAIN"
check_cfg "infrastructure.clusterName" "$CONFIG_CLUSTER"
check_cfg "infrastructure.awsRegion" "$CONFIG_REGION"
check_cfg "infrastructure.awsProfile" "$CONFIG_PROFILE"
check_cfg "identity.cognitoAdminEmail" "$CONFIG_EMAIL"
check_cfg "repository.url" "$CONFIG_REPO"
check_cfg "github.actionsRoleName" "$CONFIG_GH_ACTIONS_ROLE"
check_cfg "github.repoRegex" "$CONFIG_GH_REPO_REGEX"
check_cfg "apps.manifestsPath" "$CONFIG_APPS_PATH"
check_cfg "apps.namespace.strategy" "$CONFIG_APPS_NS_STRATEGY"
check_cfg "apps.namespace.template" "$CONFIG_APPS_NS_TEMPLATE"
check_cfg "alb.sharedGroupName" "$CONFIG_ALB_SHARED_GROUP"
check_cfg "ci.authMode" "$CONFIG_CI_AUTH_MODE"
check_cfg "ci.ecrRepoPrefix" "$CONFIG_CI_ECR_PREFIX"
check_cfg "ci.imageTagStrategy" "$CONFIG_CI_TAG_STRATEGY"
check_cfg "apps.defaults.arch" "$CONFIG_APP_DEFAULT_ARCH"
check_cfg "ci.build.platforms.arm64" "$CONFIG_BUILD_PLATFORM_ARM64"
check_cfg "ci.build.platforms.amd64" "$CONFIG_BUILD_PLATFORM_AMD64"
check_cfg "ci.build.platforms.multi" "$CONFIG_BUILD_PLATFORM_MULTI"
check_cfg "scheduling.archLabelKey" "$CONFIG_SCHED_ARCH_LABEL"
check_cfg "scheduling.armValue" "$CONFIG_SCHED_ARM_VALUE"
check_cfg "scheduling.amdValue" "$CONFIG_SCHED_AMD_VALUE"
if [ "${missing_cfg}" = "true" ]; then
  echo "   Fix config/platform-params.yaml and rerun."
  exit 1
fi

# Validate arch value
echo ""
echo "1.3 App defaults architecture..."
if [ "$CONFIG_APP_DEFAULT_ARCH" != "arm64" ] && [ "$CONFIG_APP_DEFAULT_ARCH" != "amd64" ] && [ "$CONFIG_APP_DEFAULT_ARCH" != "multi" ]; then
  echo "❌ apps.defaults.arch must be one of: arm64, amd64, multi"
  echo "   Current value: $CONFIG_APP_DEFAULT_ARCH"
  exit 1
fi
echo "✅ apps.defaults.arch = $CONFIG_APP_DEFAULT_ARCH"

# Validate email from config
echo ""
echo "1.2 Cognito admin email (from config)..."
if ! [[ "${CONFIG_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
  echo "❌ Invalid email format: ${CONFIG_EMAIL}"
  exit 1
fi
echo "✅ Cognito admin email format valid"

echo ""
echo "1.3 CI auth mode..."
if [ "$CONFIG_CI_AUTH_MODE" != "static-keys" ] && [ "$CONFIG_CI_AUTH_MODE" != "oidc" ]; then
  echo "❌ Invalid ci.authMode: ${CONFIG_CI_AUTH_MODE} (expected: static-keys | oidc)"
  exit 1
fi
echo "✅ CI auth mode valid"

if [ -z "${SKIP_K8S_CHECKS}" ]; then
  # Check ConfigMap
  echo ""
  echo "2. Kubernetes ConfigMap..."
  if ! kubectl get configmap platform-params -n argocd &>/dev/null; then
    echo "❌ ConfigMap platform-params not found in argocd namespace"
    echo "   Run: make apply-gitops"
    exit 1
  fi
  echo "✅ ConfigMap platform-params exists"

  # Check ApplicationSet (optional on first bootstrap)
  echo ""
  echo "3. ApplicationSet..."
  if ! kubectl get applicationset platform-apps -n argocd &>/dev/null; then
    echo "⚠️  ApplicationSet platform-apps not found (expected on first bootstrap)"
    echo "   It will be created by: make bootstrap-platform"
    APPLICATIONSET_PRESENT=false
  else
    echo "✅ ApplicationSet platform-apps exists"
    APPLICATIONSET_PRESENT=true
  fi
else
  APPLICATIONSET_PRESENT=false
fi

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

if [ "${APPLICATIONSET_PRESENT}" = "true" ]; then
  echo ""
  echo "🚀 ApplicationSet Status:"
  kubectl get applicationset platform-apps -n argocd -o wide

  echo ""
  echo "📦 Generated Applications:"
  kubectl get applications -n argocd -o wide
fi

echo ""
echo "✅ All validations passed!"
