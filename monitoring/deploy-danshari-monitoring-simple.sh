#!/bin/bash

################################################################################
# Danshari.ai Simple Monitoring Deployment Script
# Uses standard gcloud commands (no alpha features)
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ID="project-anshari"
INSTANCE_NAME="danshari-v-25"
INSTANCE_ZONE="us-west2-a"
WEBSITE_URL="https://danshari.ai"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-danny.dx.xie@gmail.com}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "======================================================================"
log_info "Danshari.ai Monitoring Setup (Simplified)"
echo "======================================================================"
echo "Project: $PROJECT_ID"
echo "Instance: $INSTANCE_NAME"
echo "Website: $WEBSITE_URL"
echo "======================================================================"
echo

# Set project
log_info "Setting GCP project..."
gcloud config set project $PROJECT_ID --quiet
log_success "Project set"

# Enable APIs
log_info "Enabling required APIs..."
gcloud services enable monitoring.googleapis.com logging.googleapis.com --quiet 2>/dev/null || true
log_success "APIs enabled"

# Create dashboard
log_info "Creating Cloud Monitoring Dashboard..."
DASHBOARD_FILE="./danshari-dashboard.json"

if [ -f "$DASHBOARD_FILE" ]; then
  EXISTING_DASHBOARD=$(gcloud monitoring dashboards list \
    --filter="displayName='Danshari.ai Production Monitoring'" \
    --format="value(name)" 2>/dev/null | head -1)

  if [ -n "$EXISTING_DASHBOARD" ]; then
    log_warning "Dashboard already exists: $EXISTING_DASHBOARD"
    gcloud monitoring dashboards update "$EXISTING_DASHBOARD" \
      --config-from-file="$DASHBOARD_FILE" 2>/dev/null || log_warning "Update failed, skipping"
  else
    gcloud monitoring dashboards create --config-from-file="$DASHBOARD_FILE" 2>/dev/null && \
      log_success "Dashboard created" || log_warning "Dashboard creation failed"
  fi
else
  log_error "Dashboard file not found: $DASHBOARD_FILE"
fi

# Create uptime checks
log_info "Creating uptime checks..."

# Check if uptime check exists
EXISTING_CHECK=$(gcloud monitoring uptime-checks list \
  --filter="displayName='Danshari.ai Website (HTTPS)'" \
  --format="value(name)" 2>/dev/null | head -1)

if [ -z "$EXISTING_CHECK" ]; then
  gcloud monitoring uptime-checks create \
    --display-name="Danshari.ai Website (HTTPS)" \
    --resource-type=uptime-url \
    --host="danshari.ai" \
    --path="/" \
    --protocol=https \
    --timeout=10s \
    --check-interval=60s 2>/dev/null && \
    log_success "Uptime check created" || \
    log_warning "Uptime check creation failed"
else
  log_warning "Uptime check already exists"
fi

# Install Ops Agent
log_info "Checking Ops Agent installation..."
AGENT_STATUS=$(gcloud compute ssh "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --command="systemctl is-active google-cloud-ops-agent 2>/dev/null || echo 'not-installed'" 2>/dev/null)

if [[ "$AGENT_STATUS" == "active" ]]; then
  log_success "Ops Agent is already installed and running"
else
  log_info "Installing Ops Agent..."
  gcloud compute ssh "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" \
    --command="curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh && sudo bash add-google-cloud-ops-agent-repo.sh --also-install" 2>/dev/null && \
    log_success "Ops Agent installed" || \
    log_warning "Ops Agent installation failed"
fi

echo
echo "======================================================================"
log_success "Monitoring Setup Complete!"
echo "======================================================================"
echo
echo "View your monitoring at:"
echo "  Dashboard: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo "  Metrics:   https://console.cloud.google.com/monitoring/metrics-explorer?project=$PROJECT_ID"
echo "  Uptime:    https://console.cloud.google.com/monitoring/uptime?project=$PROJECT_ID"
echo "  Logs:      https://console.cloud.google.com/logs/query?project=$PROJECT_ID"
echo
echo "Instance Status:"
gcloud compute instances describe "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" \
  --format="table(name,status,machineType.basename(),networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)" 2>/dev/null
echo
log_info "Run './check-danshari-status.sh' to check current status"
echo
