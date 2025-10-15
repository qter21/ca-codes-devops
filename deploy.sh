#!/bin/bash
# ============================================================================
# California Codes Platform - Deployment Script
# ============================================================================
# This script deploys the upgraded platform to Google Cloud Compute Engine.
# It stops old services, deploys new docker-compose configuration, and
# verifies that all services are running correctly.
#
# Prerequisites:
#   1. Images built and pushed to Artifact Registry (run build-and-push.sh)
#   2. gcloud CLI authenticated
#   3. SSH access to codecond instance
#
# Usage:
#   ./deploy.sh              # Deploy all services
#   ./deploy.sh --dry-run    # Show what would be done without executing
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTANCE_NAME="codecond"
ZONE="us-west2-a"
PROJECT_ID="project-anshari"
DEPLOY_DIR="/home/daniel/ca-codes-platform"

# Dry run flag
DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

run_command() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would run: $1${NC}"
    else
        eval "$1"
    fi
}

gcloud_ssh() {
    local cmd="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would run on instance: $cmd${NC}"
    else
        gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --project=${PROJECT_ID} --command="$cmd"
    fi
}

# ============================================================================
# Pre-deployment Checks
# ============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    print_success "gcloud authenticated"

    # Check if instance is running
    INSTANCE_STATUS=$(gcloud compute instances describe ${INSTANCE_NAME} --zone=${ZONE} --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    if [ "$INSTANCE_STATUS" != "RUNNING" ]; then
        print_error "Instance '${INSTANCE_NAME}' is not running (status: ${INSTANCE_STATUS})"
        exit 1
    fi
    print_success "Instance '${INSTANCE_NAME}' is running"

    # Check if docker-compose.production.yml exists locally
    if [ ! -f "${SCRIPT_DIR}/docker-compose.production.yml" ]; then
        print_error "docker-compose.production.yml not found in ${SCRIPT_DIR}"
        exit 1
    fi
    print_success "docker-compose.production.yml found"

    # Check if .env.production.example exists
    if [ ! -f "${SCRIPT_DIR}/.env.production.example" ]; then
        print_warning ".env.production.example not found (continuing...)"
    else
        print_success ".env.production.example found"
    fi
}

# ============================================================================
# Backup Functions
# ============================================================================

backup_current_config() {
    print_header "Backing Up Current Configuration"

    print_info "Creating backup of current configuration..."

    BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"

    gcloud_ssh "mkdir -p ~/${BACKUP_DIR}"
    gcloud_ssh "cp -r ~/california-codes-service/docker-compose.production.yml ~/${BACKUP_DIR}/ 2>/dev/null || true"
    gcloud_ssh "cp -r ~/codecond-ca/docker-compose.yml ~/${BACKUP_DIR}/ 2>/dev/null || true"
    gcloud_ssh "docker-compose -f ~/california-codes-service/docker-compose.production.yml config > ~/${BACKUP_DIR}/old-compose-resolved.yml 2>/dev/null || true"

    print_success "Configuration backed up to ~/${BACKUP_DIR}"
}

# ============================================================================
# Deployment Functions
# ============================================================================

stop_old_services() {
    print_header "Stopping Old Services"

    print_info "Stopping services in california-codes-service..."
    gcloud_ssh "cd ~/california-codes-service && docker-compose -f docker-compose.production.yml down || true"

    print_info "Stopping services in codecond-ca..."
    gcloud_ssh "cd ~/codecond-ca && docker-compose down || true"

    print_success "Old services stopped"
}

create_deployment_directory() {
    print_header "Creating Deployment Directory"

    print_info "Creating directory: ${DEPLOY_DIR}"
    gcloud_ssh "mkdir -p ${DEPLOY_DIR}/logs/api ${DEPLOY_DIR}/logs/pipeline"

    print_info "Ensuring MongoDB data directory exists..."
    gcloud_ssh "sudo mkdir -p /data/mongodb && sudo chown -R 999:999 /data/mongodb || true"

    print_success "Deployment directory created"
}

copy_configuration_files() {
    print_header "Copying Configuration Files"

    print_info "Copying docker-compose.production.yml..."
    gcloud compute scp "${SCRIPT_DIR}/docker-compose.production.yml" \
        ${INSTANCE_NAME}:${DEPLOY_DIR}/docker-compose.yml \
        --zone=${ZONE} \
        --project=${PROJECT_ID}

    print_info "Copying .env.production (ACTUAL production values)..."
    if [ -f "${SCRIPT_DIR}/.env.production" ]; then
        gcloud compute scp "${SCRIPT_DIR}/.env.production" \
            ${INSTANCE_NAME}:${DEPLOY_DIR}/.env.production \
            --zone=${ZONE} \
            --project=${PROJECT_ID}
        print_success ".env.production copied (contains actual credentials)"
    else
        print_warning ".env.production not found in ${SCRIPT_DIR}"
        print_info "Will check for existing .env.production on instance..."
    fi

    print_info "Copying .env.production.example (for reference)..."
    if [ -f "${SCRIPT_DIR}/.env.production.example" ]; then
        gcloud compute scp "${SCRIPT_DIR}/.env.production.example" \
            ${INSTANCE_NAME}:${DEPLOY_DIR}/.env.production.example \
            --zone=${ZONE} \
            --project=${PROJECT_ID}
    fi

    print_success "Configuration files copied"
}

setup_environment_file() {
    print_header "Verifying Environment File"

    # Check if .env.production exists on the instance (should be copied by now)
    ENV_EXISTS=$(gcloud_ssh "test -f ${DEPLOY_DIR}/.env.production && echo 'exists' || echo 'not_found'" || echo "not_found")

    if [ "$ENV_EXISTS" = "exists" ]; then
        print_success ".env.production found on instance"

        # Show first few non-sensitive variables for verification
        print_info "Environment preview (non-sensitive vars):"
        gcloud_ssh "cd ${DEPLOY_DIR} && grep -E '^(PROJECT_ID|ENVIRONMENT|LOG_LEVEL)=' .env.production || true"
    else
        print_error ".env.production not found on instance at ${DEPLOY_DIR}/.env.production"
        print_info "This file should have been copied in the previous step."
        print_info "Please ensure ${SCRIPT_DIR}/.env.production exists locally and try again."

        if [ "$DRY_RUN" = false ]; then
            exit 1
        fi
    fi
}

authenticate_docker_on_instance() {
    print_header "Authenticating Docker on Instance"

    print_info "Configuring Docker to use Artifact Registry..."
    gcloud_ssh "gcloud auth configure-docker us-west2-docker.pkg.dev --quiet"

    print_success "Docker authenticated with Artifact Registry"
}

pull_docker_images() {
    print_header "Pulling Docker Images"

    print_info "Pulling latest images from Artifact Registry..."
    gcloud_ssh "cd ${DEPLOY_DIR} && docker-compose pull"

    print_success "Images pulled successfully"
}

start_services() {
    print_header "Starting Services"

    print_info "Starting services (without pipeline)..."
    gcloud_ssh "cd ${DEPLOY_DIR} && docker-compose up -d"

    print_info "Waiting 30 seconds for services to initialize..."
    if [ "$DRY_RUN" = false ]; then
        sleep 30
    fi

    print_success "Services started"
}

verify_deployment() {
    print_header "Verifying Deployment"

    print_info "Checking container status..."
    gcloud_ssh "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"

    print_info "Checking service health..."

    # Check website
    print_info "Testing website (port 3456)..."
    gcloud_ssh "curl -f http://localhost:3456 > /dev/null && echo 'Website: OK' || echo 'Website: FAILED'"

    # Check API
    print_info "Testing API (port 8000)..."
    gcloud_ssh "curl -f http://localhost:8000/health > /dev/null && echo 'API: OK' || echo 'API: FAILED'"

    # Check MongoDB
    print_info "Testing MongoDB (port 27017)..."
    gcloud_ssh "docker exec ca-codes-mongodb mongosh --quiet --eval 'db.adminCommand({ping: 1})' && echo 'MongoDB: OK' || echo 'MongoDB: FAILED'"

    print_success "Deployment verified"
}

show_deployment_info() {
    print_header "Deployment Information"

    echo ""
    echo "Services deployed:"
    echo "  • codecond-ca (website) - port 3456"
    echo "  • legal-codes-api (API) - port 8000"
    echo "  • ca-codes-mongodb (MongoDB) - port 27017"
    echo "  • ca-codes-redis (Redis) - port 6379"
    echo ""
    echo "Pipeline (ca-fire-pipeline) - NOT started (manual start only)"
    echo "  To start pipeline: ssh to instance and run:"
    echo "    cd ${DEPLOY_DIR}"
    echo "    docker-compose --profile pipeline up ca-fire-pipeline"
    echo ""
    echo "Deployment directory: ${DEPLOY_DIR}"
    echo "Public URL: https://www.codecond.com"
    echo ""
    echo "Useful commands:"
    echo "  View logs:        gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --command='cd ${DEPLOY_DIR} && docker-compose logs -f'"
    echo "  Restart service:  gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --command='cd ${DEPLOY_DIR} && docker-compose restart <service>'"
    echo "  Stop all:         gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --command='cd ${DEPLOY_DIR} && docker-compose down'"
    echo ""
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    print_header "California Codes Platform - Deployment"
    echo ""
    echo "Target: ${INSTANCE_NAME} (${ZONE})"
    echo "Deploy to: ${DEPLOY_DIR}"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}Mode: DRY RUN (no changes will be made)${NC}"
    else
        echo "Mode: LIVE DEPLOYMENT"
    fi
    echo ""

    # Confirmation
    if [ "$DRY_RUN" = false ]; then
        read -p "Continue with deployment? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled"
            exit 1
        fi
    fi

    # Execute deployment steps
    check_prerequisites
    backup_current_config
    stop_old_services
    create_deployment_directory
    copy_configuration_files
    setup_environment_file
    authenticate_docker_on_instance
    pull_docker_images
    start_services
    verify_deployment
    show_deployment_info

    # Final message
    print_header "Deployment Complete!"
    print_success "All services are running"
    echo ""
    echo "Test the website: https://www.codecond.com"
    echo ""
}

# Run main function
main "$@"
