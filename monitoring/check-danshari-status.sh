#!/bin/bash

################################################################################
# Danshari.ai Quick Status Check Script
#
# This script provides a quick overview of danshari.ai infrastructure status
#
# Usage: ./check-danshari-status.sh
################################################################################

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

echo "======================================================================"
echo "               Danshari.ai Infrastructure Status Check"
echo "======================================================================"
echo

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: gcloud CLI is not installed${NC}"
  exit 1
fi

# Set project
gcloud config set project $PROJECT_ID --quiet 2>/dev/null

echo -e "${BLUE}1. GCP Instance Status${NC}"
echo "----------------------------------------------------------------------"
INSTANCE_STATUS=$(gcloud compute instances describe $INSTANCE_NAME --zone=$INSTANCE_ZONE --format="value(status)" 2>/dev/null)

if [ "$INSTANCE_STATUS" == "RUNNING" ]; then
  echo -e "   Status: ${GREEN}✓ RUNNING${NC}"
else
  echo -e "   Status: ${RED}✗ $INSTANCE_STATUS${NC}"
fi

# Get instance details
gcloud compute instances describe $INSTANCE_NAME --zone=$INSTANCE_ZONE \
  --format="table(name,machineType.basename(),networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP,disks[0].diskSizeGb:label=DISK_GB)" 2>/dev/null

echo

echo -e "${BLUE}2. Website Availability${NC}"
echo "----------------------------------------------------------------------"

# Test website
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 $WEBSITE_URL 2>/dev/null)

if [ "$HTTP_CODE" == "200" ]; then
  echo -e "   Website: ${GREEN}✓ Online (HTTP $HTTP_CODE)${NC}"
elif [ -z "$HTTP_CODE" ]; then
  echo -e "   Website: ${RED}✗ Unreachable${NC}"
else
  echo -e "   Website: ${YELLOW}⚠ HTTP $HTTP_CODE${NC}"
fi

# Response time
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time 10 $WEBSITE_URL 2>/dev/null)
echo "   Response Time: ${RESPONSE_TIME}s"

echo

echo -e "${BLUE}3. Container Status (via SSH)${NC}"
echo "----------------------------------------------------------------------"

if [ "$INSTANCE_STATUS" == "RUNNING" ]; then
  # Get container status
  gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE \
    --command="docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null | head -10

  echo
  echo -e "${BLUE}4. Resource Usage${NC}"
  echo "----------------------------------------------------------------------"

  # Get resource usage
  echo "Memory Usage:"
  gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE \
    --command="free -h | grep -E 'Mem:|Swap:'" 2>/dev/null

  echo
  echo "Disk Usage:"
  gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE \
    --command="df -h | grep -E '^Filesystem|^/dev/sda1'" 2>/dev/null

  echo
  echo "Container Resource Usage:"
  gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE \
    --command="docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' | head -7" 2>/dev/null
else
  echo -e "   ${RED}Cannot check containers - instance not running${NC}"
fi

echo
echo -e "${BLUE}5. Recent Alerts (Last 24h)${NC}"
echo "----------------------------------------------------------------------"

# Check recent incidents (requires alpha component)
INCIDENTS=$(gcloud alpha monitoring policies conditions list 2>/dev/null | grep -i danshari | head -5)

if [ -z "$INCIDENTS" ]; then
  echo -e "   ${GREEN}No recent alerts${NC}"
else
  echo "$INCIDENTS"
fi

echo
echo -e "${BLUE}6. Quick Links${NC}"
echo "----------------------------------------------------------------------"
echo "   Dashboard:    https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo "   Logs:         https://console.cloud.google.com/logs/query?project=$PROJECT_ID"
echo "   Metrics:      https://console.cloud.google.com/monitoring/metrics-explorer?project=$PROJECT_ID"
echo "   Alerts:       https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
echo "   VM Console:   https://console.cloud.google.com/compute/instances?project=$PROJECT_ID"

echo
echo -e "${BLUE}7. Quick Commands${NC}"
echo "----------------------------------------------------------------------"
echo "   SSH to instance:       gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE"
echo "   View container logs:   gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE --command='docker logs -f danshari-compose'"
echo "   Restart container:     gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE --command='docker restart danshari-compose'"
echo "   View live stats:       gcloud compute ssh $INSTANCE_NAME --zone=$INSTANCE_ZONE --command='docker stats'"

echo
echo "======================================================================"
echo "                      Status Check Complete"
echo "======================================================================"
