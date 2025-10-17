#!/bin/bash

################################################################################
# Danshari.ai Monitoring Deployment Script
#
# This script sets up comprehensive monitoring for danshari.ai on GCP:
# - Cloud Monitoring Dashboard
# - Alert Policies
# - Uptime Checks
# - Notification Channels
#
# Usage: ./deploy-danshari-monitoring.sh [options]
#   Options:
#     --dry-run        Show what would be done without making changes
#     --email EMAIL    Set notification email address
#     --skip-alerts    Skip alert policy creation
#     --skip-uptime    Skip uptime check creation
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="project-anshari"
INSTANCE_NAME="danshari-v-25"
INSTANCE_ZONE="us-west2-a"
WEBSITE_URL="https://danshari.ai"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-danny.dx.xie@gmail.com}"

# Parse command line arguments
DRY_RUN=false
SKIP_ALERTS=false
SKIP_UPTIME=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --email)
      NOTIFICATION_EMAIL="$2"
      shift 2
      ;;
    --skip-alerts)
      SKIP_ALERTS=true
      shift
      ;;
    --skip-uptime)
      SKIP_UPTIME=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] [--email EMAIL] [--skip-alerts] [--skip-uptime]"
      exit 1
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

run_command() {
  local cmd="$1"
  local description="$2"

  log_info "$description"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Would execute: $cmd"
    return 0
  fi

  if eval "$cmd"; then
    log_success "$description - Done"
    return 0
  else
    log_error "$description - Failed"
    return 1
  fi
}

################################################################################
# Pre-flight Checks
################################################################################

log_info "Starting Danshari.ai Monitoring Setup"
echo "================================"
echo "Project: $PROJECT_ID"
echo "Instance: $INSTANCE_NAME"
echo "Zone: $INSTANCE_ZONE"
echo "Website: $WEBSITE_URL"
echo "Notification Email: $NOTIFICATION_EMAIL"
echo "Dry Run: $DRY_RUN"
echo "================================"
echo

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
  log_error "gcloud CLI is not installed. Please install it first."
  exit 1
fi

# Check authentication
log_info "Checking GCP authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  log_error "Not authenticated with gcloud. Run: gcloud auth login"
  exit 1
fi
log_success "Authenticated"

# Set project
run_command "gcloud config set project $PROJECT_ID" "Setting GCP project"

# Verify instance exists
log_info "Verifying instance exists..."
if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" &> /dev/null; then
  log_error "Instance $INSTANCE_NAME not found in zone $INSTANCE_ZONE"
  exit 1
fi
log_success "Instance verified"

# Enable required APIs
log_info "Enabling required GCP APIs..."
REQUIRED_APIS=(
  "monitoring.googleapis.com"
  "logging.googleapis.com"
  "cloudresourcemanager.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
  run_command "gcloud services enable $api" "Enabling $api"
done

################################################################################
# Create Notification Channel
################################################################################

log_info "Setting up notification channels..."

# Check if email notification channel already exists
EMAIL_CHANNEL_ID=$(gcloud alpha monitoring channels list \
  --filter="type=email AND labels.email_address=$NOTIFICATION_EMAIL" \
  --format="value(name)" 2>/dev/null | head -1)

if [ -z "$EMAIL_CHANNEL_ID" ]; then
  log_info "Creating email notification channel for $NOTIFICATION_EMAIL"

  if [ "$DRY_RUN" = false ]; then
    EMAIL_CHANNEL_ID=$(gcloud alpha monitoring channels create \
      --display-name="Danshari Alerts Email" \
      --type=email \
      --channel-labels=email_address="$NOTIFICATION_EMAIL" \
      --format="value(name)" 2>/dev/null)

    if [ -n "$EMAIL_CHANNEL_ID" ]; then
      log_success "Created email notification channel: $EMAIL_CHANNEL_ID"
    else
      log_warning "Could not create email notification channel. Will continue without notifications."
      EMAIL_CHANNEL_ID=""
    fi
  else
    log_info "[DRY-RUN] Would create email notification channel"
  fi
else
  log_success "Email notification channel already exists: $EMAIL_CHANNEL_ID"
fi

################################################################################
# Create Dashboard
################################################################################

log_info "Creating Cloud Monitoring Dashboard..."

DASHBOARD_FILE="$(dirname "$0")/danshari-dashboard.json"

if [ ! -f "$DASHBOARD_FILE" ]; then
  log_error "Dashboard file not found: $DASHBOARD_FILE"
  exit 1
fi

# Check if dashboard already exists
EXISTING_DASHBOARD=$(gcloud monitoring dashboards list \
  --filter="displayName='Danshari.ai Production Monitoring'" \
  --format="value(name)" 2>/dev/null | head -1)

if [ -n "$EXISTING_DASHBOARD" ]; then
  log_warning "Dashboard already exists. Updating..."

  if [ "$DRY_RUN" = false ]; then
    gcloud monitoring dashboards update "$EXISTING_DASHBOARD" \
      --config-from-file="$DASHBOARD_FILE" || log_warning "Dashboard update failed"
  fi
else
  if [ "$DRY_RUN" = false ]; then
    gcloud monitoring dashboards create --config-from-file="$DASHBOARD_FILE"
    log_success "Dashboard created"
  else
    log_info "[DRY-RUN] Would create dashboard from $DASHBOARD_FILE"
  fi
fi

################################################################################
# Create Alert Policies
################################################################################

if [ "$SKIP_ALERTS" = false ]; then
  log_info "Creating alert policies..."

  # Function to create an alert policy
  create_alert() {
    local alert_name="$1"
    local description="$2"
    local filter="$3"
    local threshold="$4"
    local duration="$5"
    local comparison="${6:-COMPARISON_GT}"

    # Check if alert already exists
    EXISTING_ALERT=$(gcloud alpha monitoring policies list \
      --filter="displayName='$alert_name'" \
      --format="value(name)" 2>/dev/null | head -1)

    if [ -n "$EXISTING_ALERT" ]; then
      log_warning "Alert '$alert_name' already exists. Skipping."
      return
    fi

    if [ "$DRY_RUN" = false ]; then
      local notification_flag=""
      if [ -n "$EMAIL_CHANNEL_ID" ]; then
        notification_flag="--notification-channels=$EMAIL_CHANNEL_ID"
      fi

      gcloud alpha monitoring policies create \
        --display-name="$alert_name" \
        --condition-display-name="$alert_name Condition" \
        --condition-threshold-value="$threshold" \
        --condition-threshold-duration="$duration" \
        --condition-filter="$filter" \
        --condition-comparison="$comparison" \
        $notification_flag \
        --documentation="$description" 2>/dev/null && \
        log_success "Created alert: $alert_name" || \
        log_warning "Failed to create alert: $alert_name"
    else
      log_info "[DRY-RUN] Would create alert: $alert_name"
    fi
  }

  # Critical CPU Alert
  create_alert \
    "Danshari - Critical CPU Usage (>95%)" \
    "CRITICAL: CPU usage exceeded 95% on danshari-v-25. Check docker stats and restart containers if needed." \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_NAME\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"" \
    "0.95" \
    "180s" \
    "COMPARISON_GT"

  # High CPU Alert
  create_alert \
    "Danshari - High CPU Usage (>85%)" \
    "CPU usage exceeded 85% on danshari-v-25. Monitor and investigate if sustained." \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_NAME\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"" \
    "0.85" \
    "300s" \
    "COMPARISON_GT"

  # High Memory Alert
  create_alert \
    "Danshari - High Memory Usage (>85%)" \
    "Memory usage exceeded 85% on danshari-v-25. Check for memory leaks." \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_NAME\" AND metric.type=\"agent.googleapis.com/memory/percent_used\"" \
    "85" \
    "300s" \
    "COMPARISON_GT"

  # Disk Usage Alert
  create_alert \
    "Danshari - Disk Usage >80%" \
    "Disk usage exceeded 80% on danshari-v-25. Clean up or expand disk." \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_NAME\" AND metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.labels.state=\"used\"" \
    "80" \
    "600s" \
    "COMPARISON_GT"

  # Instance Down Alert
  create_alert \
    "Danshari - VM Instance Down" \
    "CRITICAL: danshari-v-25 instance is not running! Start immediately." \
    "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"$INSTANCE_NAME\" AND metric.type=\"compute.googleapis.com/instance/uptime\"" \
    "60" \
    "60s" \
    "COMPARISON_LT"

  log_success "Alert policies created"
else
  log_info "Skipping alert policy creation (--skip-alerts)"
fi

################################################################################
# Create Uptime Checks
################################################################################

if [ "$SKIP_UPTIME" = false ]; then
  log_info "Creating uptime checks..."

  # Function to create uptime check
  create_uptime_check() {
    local check_name="$1"
    local host="$2"
    local path="$3"
    local port="$4"

    # Check if uptime check already exists
    EXISTING_CHECK=$(gcloud monitoring uptime-checks list \
      --filter="displayName='$check_name'" \
      --format="value(name)" 2>/dev/null | head -1)

    if [ -n "$EXISTING_CHECK" ]; then
      log_warning "Uptime check '$check_name' already exists. Skipping."
      return
    fi

    if [ "$DRY_RUN" = false ]; then
      gcloud monitoring uptime-checks create \
        --display-name="$check_name" \
        --resource-type=uptime-url \
        --host="$host" \
        --path="$path" \
        --port="$port" \
        --protocol=https \
        --timeout=10s \
        --check-interval=60s 2>/dev/null && \
        log_success "Created uptime check: $check_name" || \
        log_warning "Failed to create uptime check: $check_name"
    else
      log_info "[DRY-RUN] Would create uptime check: $check_name"
    fi
  }

  # Main website check
  create_uptime_check \
    "Danshari.ai Website (HTTPS)" \
    "danshari.ai" \
    "/" \
    "443"

  # Health endpoint check (if exists)
  create_uptime_check \
    "Danshari.ai Health Endpoint" \
    "danshari.ai" \
    "/health" \
    "443"

  log_success "Uptime checks created"
else
  log_info "Skipping uptime check creation (--skip-uptime)"
fi

################################################################################
# Install Monitoring Agent (Ops Agent)
################################################################################

log_info "Checking if Ops Agent is installed on instance..."

# Check if agent is already installed
AGENT_STATUS=$(gcloud compute ssh "$INSTANCE_NAME" \
  --zone="$INSTANCE_ZONE" \
  --command="systemctl is-active google-cloud-ops-agent || echo 'not-installed'" 2>/dev/null)

if [[ "$AGENT_STATUS" == "active" ]]; then
  log_success "Ops Agent is already installed and running"
else
  log_warning "Ops Agent not installed. Installing..."

  if [ "$DRY_RUN" = false ]; then
    # Install Ops Agent
    gcloud compute ssh "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" --command="curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh && sudo bash add-google-cloud-ops-agent-repo.sh --also-install" 2>/dev/null && \
      log_success "Ops Agent installed" || \
      log_warning "Failed to install Ops Agent. Some metrics may not be available."
  else
    log_info "[DRY-RUN] Would install Ops Agent"
  fi
fi

################################################################################
# Summary
################################################################################

echo
echo "================================"
log_success "Monitoring Setup Complete!"
echo "================================"
echo
echo "Next Steps:"
echo "1. View Dashboard:"
echo "   https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo
echo "2. View Alerts:"
echo "   https://console.cloud.google.com/monitoring/alerting/policies?project=$PROJECT_ID"
echo
echo "3. View Uptime Checks:"
echo "   https://console.cloud.google.com/monitoring/uptime?project=$PROJECT_ID"
echo
echo "4. Current Instance Status:"
gcloud compute instances describe "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" --format="table(name,status,machineType,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null
echo
echo "5. Test Website:"
echo "   curl -I $WEBSITE_URL"
echo
echo "6. SSH to Instance:"
echo "   gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE"
echo
echo "7. View Logs:"
echo "   gcloud logging read 'resource.type=gce_instance AND resource.labels.instance_id=$INSTANCE_NAME' --limit 50"
echo
echo "Notification Email: $NOTIFICATION_EMAIL"
echo
log_info "Monitor your infrastructure at: https://console.cloud.google.com/monitoring"
