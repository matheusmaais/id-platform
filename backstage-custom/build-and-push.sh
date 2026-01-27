#!/bin/bash
# ============================================================================
# Backstage Custom Image - Build and Push to ECR
# Deterministic, reproducible, and secure
# ============================================================================

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly IMAGE_NAME="backstage-platform"
readonly IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
readonly LATEST_TAG="latest"

# Functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    
    for cmd in docker aws jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

get_aws_account() {
    log_info "Getting AWS account information..."
    
    if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
        log_error "Failed to get AWS account ID. Are you logged in?"
        exit 1
    fi
    
    readonly ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    readonly FULL_IMAGE="${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    readonly FULL_IMAGE_LATEST="${ECR_REGISTRY}/${IMAGE_NAME}:${LATEST_TAG}"
    
    log_success "AWS Account: ${AWS_ACCOUNT_ID}"
    log_success "ECR Registry: ${ECR_REGISTRY}"
}

create_ecr_repository() {
    log_info "Checking ECR repository..."
    
    if aws ecr describe-repositories \
        --repository-names "${IMAGE_NAME}" \
        --region "${AWS_REGION}" &> /dev/null; then
        log_success "Repository exists: ${IMAGE_NAME}"
    else
        log_warning "Repository not found, creating..."
        
        aws ecr create-repository \
            --repository-name "${IMAGE_NAME}" \
            --region "${AWS_REGION}" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 \
            --tags Key=Project,Value=id-platform Key=Component,Value=backstage Key=ManagedBy,Value=script \
            > /dev/null
        
        log_success "Repository created: ${IMAGE_NAME}"
    fi
}

login_to_ecr() {
    log_info "Logging in to ECR..."
    
    if aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${ECR_REGISTRY}" &> /dev/null; then
        log_success "Logged in to ECR"
    else
        log_error "Failed to login to ECR"
        exit 1
    fi
}

build_image() {
    log_info "Building Docker image..."
    log_info "Image: ${FULL_IMAGE}"
    log_info "Platform: linux/arm64 (AWS Graviton / t4g)"
    
    if docker build \
        --platform linux/arm64 \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --tag "${FULL_IMAGE}" \
        --tag "${FULL_IMAGE_LATEST}" \
        --file Dockerfile \
        . ; then
        log_success "Image built successfully"
    else
        log_error "Docker build failed"
        exit 1
    fi
}

test_image() {
    log_info "Testing image..."
    
    # Start container
    local container_id
    container_id=$(docker run -d \
        -e POSTGRES_HOST=localhost \
        -e POSTGRES_PORT=5432 \
        -e POSTGRES_USER=backstage \
        -e POSTGRES_PASSWORD=test \
        -e POSTGRES_DB=backstage \
        "${FULL_IMAGE}")
    
    log_info "Container started: ${container_id:0:12}"
    
    # Wait for startup
    log_info "Waiting for backend to start (30s)..."
    sleep 30
    
    # Check if container is still running
    if ! docker ps --filter "id=${container_id}" --format "{{.ID}}" | grep -q "${container_id}"; then
        log_error "Container crashed during startup"
        docker logs "${container_id}"
        docker rm -f "${container_id}" &> /dev/null
        exit 1
    fi
    
    # Check logs for OIDC provider
    if docker logs "${container_id}" 2>&1 | grep -q "oidc"; then
        log_success "OIDC provider detected in logs"
    else
        log_warning "OIDC provider not explicitly mentioned in logs (may be OK)"
    fi
    
    # Cleanup
    docker rm -f "${container_id}" &> /dev/null
    log_success "Image test passed"
}

push_image() {
    log_info "Pushing image to ECR..."
    
    # Push versioned tag
    if docker push "${FULL_IMAGE}"; then
        log_success "Pushed: ${FULL_IMAGE}"
    else
        log_error "Failed to push image"
        exit 1
    fi
    
    # Push latest tag
    if docker push "${FULL_IMAGE_LATEST}"; then
        log_success "Pushed: ${FULL_IMAGE_LATEST}"
    else
        log_error "Failed to push latest tag"
        exit 1
    fi
}

get_image_info() {
    log_info "Getting image information..."
    
    local digest
    digest=$(aws ecr describe-images \
        --repository-name "${IMAGE_NAME}" \
        --image-ids imageTag="${IMAGE_TAG}" \
        --region "${AWS_REGION}" \
        --query 'imageDetails[0].imageDigest' \
        --output text)
    
    local size
    size=$(aws ecr describe-images \
        --repository-name "${IMAGE_NAME}" \
        --image-ids imageTag="${IMAGE_TAG}" \
        --region "${AWS_REGION}" \
        --query 'imageDetails[0].imageSizeInBytes' \
        --output text)
    
    local size_mb=$((size / 1024 / 1024))
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    BUILD COMPLETE                              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Image:   ${FULL_IMAGE}"
    echo "Latest:  ${FULL_IMAGE_LATEST}"
    echo "Digest:  ${digest}"
    echo "Size:    ${size_mb} MB"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Update platform-apps/backstage/values.yaml:"
    echo "   backstage:"
    echo "     image:"
    echo "       registry: ${ECR_REGISTRY}"
    echo "       repository: ${IMAGE_NAME}"
    echo "       tag: ${IMAGE_TAG}"
    echo ""
    echo "2. Commit and push changes"
    echo "3. ArgoCD will automatically deploy the new image"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Backstage Custom Image Builder                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    get_aws_account
    create_ecr_repository
    login_to_ecr
    build_image
    test_image
    push_image
    get_image_info
}

main "$@"
