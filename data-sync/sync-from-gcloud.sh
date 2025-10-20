#!/bin/bash

# ============================================================================
# Sync Data from Google Cloud to Local
# ============================================================================
# This script syncs MongoDB data and configuration from Google Cloud to local
#
# Usage:
#   ./sync-from-gcloud.sh [OPTIONS]
#
# Options:
#   --mongodb           Sync MongoDB data from instance
#   --from-backup       Download backup from Cloud Storage
#   --config            Sync configuration files
#   --all               Sync everything (default)
#   --list-backups      List available backups in Cloud Storage
#   --dry-run           Show what would be done without doing it
#
# Examples:
#   ./sync-from-gcloud.sh --mongodb
#   ./sync-from-gcloud.sh --from-backup mongodb-backup-20251020.tar.gz
#   ./sync-from-gcloud.sh --all
# ============================================================================

set -e

# Configuration
PROJECT_ID="project-anshari"
INSTANCE_NAME="codecond"
ZONE="us-west2-a"
GCS_BUCKET="gs://project-anshari-backups"
LOCAL_SYNC_DIR="${HOME}/gcloud-sync"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================================================
# Validation Functions
# ============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    print_success "gcloud CLI found"

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    print_success "gcloud authenticated"

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        print_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    print_success "gsutil found"

    # Check if instance exists
    if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" &> /dev/null; then
        print_error "Instance $INSTANCE_NAME not found in zone $ZONE"
        exit 1
    fi
    print_success "Instance $INSTANCE_NAME found"

    # Set project
    gcloud config set project "$PROJECT_ID" --quiet
    print_success "Project set to $PROJECT_ID"
}

# ============================================================================
# Sync Functions
# ============================================================================

list_backups() {
    print_header "Available Backups in Cloud Storage"
    
    if gsutil ls "$GCS_BUCKET/" &> /dev/null; then
        print_info "Listing backups in $GCS_BUCKET/"
        gsutil ls -lh "$GCS_BUCKET/" | grep -E "\.tar\.gz$|\.zip$" || {
            print_warning "No backup files found in $GCS_BUCKET/"
        }
    else
        print_warning "Cloud Storage bucket $GCS_BUCKET not found or empty"
        print_info "To create backups, run the following on the instance:"
        echo ""
        echo "  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
        echo "  sudo tar -czf mongodb-backup-\$(date +%Y%m%d).tar.gz /data/mongodb/"
        echo "  gsutil cp mongodb-backup-*.tar.gz $GCS_BUCKET/"
    fi
}

sync_mongodb_direct() {
    print_header "Syncing MongoDB Data from Instance"
    
    LOCAL_MONGODB_DIR="$LOCAL_SYNC_DIR/mongodb-$TIMESTAMP"
    mkdir -p "$LOCAL_MONGODB_DIR"
    
    print_info "Creating backup on instance first..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would run: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='sudo tar -czf /tmp/mongodb-backup-$TIMESTAMP.tar.gz /data/mongodb/'"
    else
        gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
            --command="sudo tar -czf /tmp/mongodb-backup-$TIMESTAMP.tar.gz /data/mongodb/ 2>/dev/null && sudo chmod 644 /tmp/mongodb-backup-$TIMESTAMP.tar.gz"
        print_success "Backup created on instance"
    fi
    
    print_info "Downloading backup from instance to local..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would run: gcloud compute scp $INSTANCE_NAME:/tmp/mongodb-backup-$TIMESTAMP.tar.gz $LOCAL_MONGODB_DIR/"
    else
        gcloud compute scp "$INSTANCE_NAME:/tmp/mongodb-backup-$TIMESTAMP.tar.gz" \
            "$LOCAL_MONGODB_DIR/" --zone="$ZONE" --project="$PROJECT_ID"
        print_success "Downloaded to $LOCAL_MONGODB_DIR/mongodb-backup-$TIMESTAMP.tar.gz"
    fi
    
    print_info "Cleaning up temporary file on instance..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would run: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='sudo rm /tmp/mongodb-backup-$TIMESTAMP.tar.gz'"
    else
        gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
            --command="sudo rm /tmp/mongodb-backup-$TIMESTAMP.tar.gz"
        print_success "Cleanup complete"
    fi
    
    # Show extraction instructions
    print_success "MongoDB data synced successfully!"
    echo ""
    print_info "To extract the backup:"
    echo "  cd $LOCAL_MONGODB_DIR"
    echo "  tar -xzf mongodb-backup-$TIMESTAMP.tar.gz"
    echo ""
    print_info "Backup location: $LOCAL_MONGODB_DIR/mongodb-backup-$TIMESTAMP.tar.gz"
}

sync_from_cloud_storage() {
    print_header "Downloading Backup from Cloud Storage"
    
    BACKUP_FILE="$1"
    LOCAL_BACKUP_DIR="$LOCAL_SYNC_DIR/backups"
    mkdir -p "$LOCAL_BACKUP_DIR"
    
    if [ -z "$BACKUP_FILE" ]; then
        print_error "No backup file specified. Use --from-backup <filename>"
        print_info "Available backups:"
        list_backups
        exit 1
    fi
    
    # Check if backup exists
    if ! gsutil ls "$GCS_BUCKET/$BACKUP_FILE" &> /dev/null; then
        print_error "Backup file not found: $GCS_BUCKET/$BACKUP_FILE"
        print_info "Available backups:"
        list_backups
        exit 1
    fi
    
    print_info "Downloading $BACKUP_FILE from Cloud Storage..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would run: gsutil cp $GCS_BUCKET/$BACKUP_FILE $LOCAL_BACKUP_DIR/"
    else
        gsutil cp "$GCS_BUCKET/$BACKUP_FILE" "$LOCAL_BACKUP_DIR/"
        print_success "Downloaded to $LOCAL_BACKUP_DIR/$BACKUP_FILE"
        
        # Show extraction instructions
        echo ""
        print_info "To extract the backup:"
        echo "  cd $LOCAL_BACKUP_DIR"
        echo "  tar -xzf $BACKUP_FILE"
    fi
}

sync_configuration() {
    print_header "Syncing Configuration Files"
    
    LOCAL_CONFIG_DIR="$LOCAL_SYNC_DIR/config-$TIMESTAMP"
    mkdir -p "$LOCAL_CONFIG_DIR"
    
    print_info "Downloading docker-compose.yml..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would download configuration files"
    else
        gcloud compute scp "$INSTANCE_NAME:~/ca-codes-platform/docker-compose.yml" \
            "$LOCAL_CONFIG_DIR/" --zone="$ZONE" --project="$PROJECT_ID" 2>/dev/null || \
            print_warning "docker-compose.yml not found"
    fi
    
    print_info "Downloading .env.production (if exists)..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would download .env.production"
    else
        gcloud compute scp "$INSTANCE_NAME:~/ca-codes-platform/.env.production" \
            "$LOCAL_CONFIG_DIR/.env.production.backup" --zone="$ZONE" --project="$PROJECT_ID" 2>/dev/null || \
            print_warning ".env.production not found (this is expected for security)"
    fi
    
    print_info "Downloading logs structure..."
    if [ "$DRY_RUN" = true ]; then
        print_warning "[DRY RUN] Would download logs"
    else
        gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" \
            --command="cd ~/ca-codes-platform && find logs -type f -name '*.log' | head -10" > "$LOCAL_CONFIG_DIR/logs-list.txt" 2>/dev/null || \
            print_warning "Could not list logs"
    fi
    
    print_success "Configuration synced to $LOCAL_CONFIG_DIR/"
}

sync_all() {
    print_header "Syncing All Data from Google Cloud"
    
    sync_mongodb_direct
    sync_configuration
    
    print_header "Sync Complete!"
    print_success "All data synced to $LOCAL_SYNC_DIR/"
    echo ""
    print_info "Summary:"
    echo "  MongoDB backup: $LOCAL_SYNC_DIR/mongodb-$TIMESTAMP/"
    echo "  Configuration:  $LOCAL_SYNC_DIR/config-$TIMESTAMP/"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Sync data from Google Cloud to local machine.

Options:
  --mongodb           Sync MongoDB data from instance (creates fresh backup)
  --from-backup FILE  Download specific backup from Cloud Storage
  --config            Sync configuration files only
  --all               Sync everything (default)
  --list-backups      List available backups in Cloud Storage
  --dry-run           Show what would be done without doing it
  -h, --help          Show this help message

Examples:
  $0 --mongodb
      Sync MongoDB data directly from the instance

  $0 --from-backup mongodb-backup-20251020.tar.gz
      Download a specific backup from Cloud Storage

  $0 --list-backups
      List all available backups in Cloud Storage

  $0 --all
      Sync MongoDB data and configuration files

  $0 --dry-run --mongodb
      Show what would be done without actually doing it

Local sync directory: $LOCAL_SYNC_DIR

EOF
}

# ============================================================================
# Main Script
# ============================================================================

# Parse arguments
SYNC_MONGODB=false
SYNC_FROM_BACKUP=false
SYNC_CONFIG=false
SYNC_ALL=false
LIST_BACKUPS=false
DRY_RUN=false
BACKUP_FILE=""

if [ $# -eq 0 ]; then
    SYNC_ALL=true
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --mongodb)
            SYNC_MONGODB=true
            shift
            ;;
        --from-backup)
            SYNC_FROM_BACKUP=true
            BACKUP_FILE="$2"
            shift 2
            ;;
        --config)
            SYNC_CONFIG=true
            shift
            ;;
        --all)
            SYNC_ALL=true
            shift
            ;;
        --list-backups)
            LIST_BACKUPS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Show dry run warning
if [ "$DRY_RUN" = true ]; then
    print_warning "DRY RUN MODE - No actual changes will be made"
    echo ""
fi

# Check prerequisites
check_prerequisites

# Execute requested operations
if [ "$LIST_BACKUPS" = true ]; then
    list_backups
    exit 0
fi

if [ "$SYNC_ALL" = true ]; then
    sync_all
elif [ "$SYNC_MONGODB" = true ]; then
    sync_mongodb_direct
elif [ "$SYNC_FROM_BACKUP" = true ]; then
    sync_from_cloud_storage "$BACKUP_FILE"
elif [ "$SYNC_CONFIG" = true ]; then
    sync_configuration
fi

print_success "Done!"

