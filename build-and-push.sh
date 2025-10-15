#!/bin/bash
# ============================================================================
# California Codes Platform - Build and Push Script
# ============================================================================
# This script builds Docker images locally (on Mac) and pushes them to
# Google Artifact Registry for deployment on GCloud Compute Engine.
#
# Prerequisites:
#   1. Docker Desktop with buildx support
#   2. gcloud CLI authenticated
#   3. Artifact Registry repository created
#
# Usage:
#   ./build-and-push.sh              # Build and push all images
#   ./build-and-push.sh website      # Build and push only website
#   ./build-and-push.sh api          # Build and push only API
#   ./build-and-push.sh pipeline     # Build and push only pipeline
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="project-anshari"
REGION="us-west2"
REPO_NAME="codecond"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"

# Image names
WEBSITE_IMAGE="${REGISTRY}/codecond-ca"
API_IMAGE="${REGISTRY}/legal-codes-api"
PIPELINE_IMAGE="${REGISTRY}/ca-fire-pipeline"

# Version tag (use git commit hash or timestamp)
VERSION_TAG=$(date +%Y%m%d-%H%M%S)

# Project directories (relative to dev_ops)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="${SCRIPT_DIR}/../codecond-ca"
API_DIR="${SCRIPT_DIR}/../legal-codes-api"
PIPELINE_DIR="${SCRIPT_DIR}/../ca_fire_pipeline"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

# ============================================================================
# Setup Functions
# ============================================================================

setup_buildx() {
    print_header "Setting up Docker Buildx"

    # Create buildx builder if it doesn't exist
    if ! docker buildx inspect multiarch-builder &> /dev/null; then
        print_info "Creating multiarch builder..."
        docker buildx create --name multiarch-builder --use --platform linux/amd64,linux/arm64
    else
        print_info "Using existing multiarch builder..."
        docker buildx use multiarch-builder
    fi

    # Bootstrap builder
    docker buildx inspect --bootstrap
    print_success "Buildx ready"
}

authenticate_registry() {
    print_header "Authenticating with Google Artifact Registry"

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    # Configure Docker to use gcloud credentials
    gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
    print_success "Authenticated with Artifact Registry"
}

create_repository() {
    print_header "Checking Artifact Registry Repository"

    # Check if repository exists
    if gcloud artifacts repositories describe ${REPO_NAME} --location=${REGION} &> /dev/null; then
        print_success "Repository '${REPO_NAME}' already exists"
    else
        print_info "Creating repository '${REPO_NAME}'..."
        gcloud artifacts repositories create ${REPO_NAME} \
            --repository-format=docker \
            --location=${REGION} \
            --description="California Codes Platform - Docker images"
        print_success "Repository created"
    fi
}

# ============================================================================
# Build Functions
# ============================================================================

build_website() {
    print_header "Building codecond-ca (Website)"

    if [ ! -d "$WEBSITE_DIR" ]; then
        print_error "Website directory not found: $WEBSITE_DIR"
        exit 1
    fi

    print_info "Building from: $WEBSITE_DIR"
    print_info "Image: ${WEBSITE_IMAGE}:latest"
    print_info "Version tag: ${WEBSITE_IMAGE}:${VERSION_TAG}"

    cd "$WEBSITE_DIR"

    docker buildx build \
        --platform linux/amd64 \
        --build-arg NEXT_PUBLIC_API_BASE_URL=/api \
        -t "${WEBSITE_IMAGE}:latest" \
        -t "${WEBSITE_IMAGE}:${VERSION_TAG}" \
        --push \
        .

    print_success "Website image built and pushed"
}

build_api() {
    print_header "Building legal-codes-api (API)"

    if [ ! -d "$API_DIR" ]; then
        print_error "API directory not found: $API_DIR"
        exit 1
    fi

    print_info "Building from: $API_DIR"
    print_info "Image: ${API_IMAGE}:latest"
    print_info "Version tag: ${API_IMAGE}:${VERSION_TAG}"

    cd "$API_DIR"

    docker buildx build \
        --platform linux/amd64 \
        -t "${API_IMAGE}:latest" \
        -t "${API_IMAGE}:${VERSION_TAG}" \
        --push \
        .

    print_success "API image built and pushed"
}

build_pipeline() {
    print_header "Building ca-fire-pipeline (Data Pipeline)"

    if [ ! -d "$PIPELINE_DIR" ]; then
        print_error "Pipeline directory not found: $PIPELINE_DIR"
        exit 1
    fi

    print_info "Building from: $PIPELINE_DIR"
    print_info "Image: ${PIPELINE_IMAGE}:latest"
    print_info "Version tag: ${PIPELINE_IMAGE}:${VERSION_TAG}"

    cd "$PIPELINE_DIR"

    docker buildx build \
        --platform linux/amd64 \
        -t "${PIPELINE_IMAGE}:latest" \
        -t "${PIPELINE_IMAGE}:${VERSION_TAG}" \
        --push \
        .

    print_success "Pipeline image built and pushed"
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    print_header "California Codes Platform - Build & Push"
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Registry: ${REGISTRY}"
    echo "Version: ${VERSION_TAG}"
    echo ""

    # Setup
    setup_buildx
    authenticate_registry
    create_repository

    # Build based on argument
    case "${1:-all}" in
        website)
            build_website
            ;;
        api)
            build_api
            ;;
        pipeline)
            build_pipeline
            ;;
        all)
            build_website
            build_api
            build_pipeline
            ;;
        *)
            print_error "Invalid argument: $1"
            echo "Usage: $0 [website|api|pipeline|all]"
            exit 1
            ;;
    esac

    # Summary
    print_header "Build Complete!"
    echo ""
    echo "Images pushed to Artifact Registry:"
    if [ "${1:-all}" = "all" ] || [ "$1" = "website" ]; then
        echo "  • ${WEBSITE_IMAGE}:latest"
        echo "  • ${WEBSITE_IMAGE}:${VERSION_TAG}"
    fi
    if [ "${1:-all}" = "all" ] || [ "$1" = "api" ]; then
        echo "  • ${API_IMAGE}:latest"
        echo "  • ${API_IMAGE}:${VERSION_TAG}"
    fi
    if [ "${1:-all}" = "all" ] || [ "$1" = "pipeline" ]; then
        echo "  • ${PIPELINE_IMAGE}:latest"
        echo "  • ${PIPELINE_IMAGE}:${VERSION_TAG}"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Review images in Artifact Registry"
    echo "  2. Run deploy.sh to deploy to production"
    echo ""
    print_success "Done!"
}

# Run main function
main "$@"
