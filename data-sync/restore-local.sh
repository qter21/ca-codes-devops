#!/bin/bash

# ============================================================================
# Restore MongoDB Data Locally
# ============================================================================
# This script helps restore MongoDB backups on your local machine
#
# Usage:
#   ./restore-local.sh [OPTIONS]
#
# Options:
#   --backup FILE       Path to backup tar.gz file to restore
#   --extract-only      Only extract, don't start MongoDB
#   --start-mongodb     Start local MongoDB container
#   --stop-mongodb      Stop local MongoDB container
#   --cleanup           Remove extracted data
#   -h, --help          Show this help
#
# Examples:
#   ./restore-local.sh --backup ~/gcloud-sync/mongodb-20251020/mongodb-backup-20251020.tar.gz
#   ./restore-local.sh --start-mongodb
# ============================================================================

set -e

# Configuration
LOCAL_DATA_DIR="${HOME}/mongodb-local-data"
CONTAINER_NAME="ca-codes-mongodb-local"
MONGO_PORT="27017"
MONGO_USERNAME="admin"
MONGO_PASSWORD="legalcodes123"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
# Functions
# ============================================================================

check_docker() {
    print_header "Checking Docker"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker Desktop first."
        exit 1
    fi
    print_success "Docker found"
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    print_success "Docker is running"
}

extract_backup() {
    print_header "Extracting Backup"
    
    BACKUP_FILE="$1"
    
    if [ -z "$BACKUP_FILE" ]; then
        print_error "No backup file specified"
        exit 1
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    print_info "Extracting $BACKUP_FILE..."
    
    # Create temporary extraction directory
    EXTRACT_DIR="${LOCAL_DATA_DIR}/extracted"
    mkdir -p "$EXTRACT_DIR"
    
    # Extract the backup
    tar -xzf "$BACKUP_FILE" -C "$EXTRACT_DIR"
    
    # Move the data directory to the right location
    if [ -d "$EXTRACT_DIR/data/mongodb" ]; then
        rm -rf "${LOCAL_DATA_DIR}/data"
        mv "$EXTRACT_DIR/data/mongodb" "${LOCAL_DATA_DIR}/data"
        rm -rf "$EXTRACT_DIR"
        print_success "Extracted to ${LOCAL_DATA_DIR}/data"
    else
        print_error "Unexpected backup structure. Expected /data/mongodb in archive."
        exit 1
    fi
}

start_mongodb() {
    print_header "Starting Local MongoDB Container"
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Container $CONTAINER_NAME already exists"
        
        # Check if it's running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            print_warning "Container is already running"
            docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            return
        else
            print_info "Starting existing container..."
            docker start "$CONTAINER_NAME"
            print_success "Container started"
            return
        fi
    fi
    
    # Create data directory if it doesn't exist
    mkdir -p "${LOCAL_DATA_DIR}/data"
    
    print_info "Creating new MongoDB container..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$MONGO_PORT:27017" \
        -v "${LOCAL_DATA_DIR}/data:/data/db" \
        -e MONGO_INITDB_ROOT_USERNAME="$MONGO_USERNAME" \
        -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_PASSWORD" \
        mongo:7.0 \
        mongod --auth
    
    print_success "MongoDB container started"
    
    # Wait for MongoDB to be ready
    print_info "Waiting for MongoDB to be ready..."
    sleep 5
    
    # Test connection
    if docker exec "$CONTAINER_NAME" mongosh --quiet --eval "db.adminCommand('ping')" &> /dev/null; then
        print_success "MongoDB is ready!"
    else
        print_warning "MongoDB may not be fully ready yet. Give it a few more seconds."
    fi
    
    echo ""
    print_info "Connection details:"
    echo "  Host:     localhost:$MONGO_PORT"
    echo "  Username: $MONGO_USERNAME"
    echo "  Password: $MONGO_PASSWORD"
    echo "  Database: ca_codes_db"
    echo ""
    print_info "Connect with:"
    echo "  mongosh mongodb://$MONGO_USERNAME:$MONGO_PASSWORD@localhost:$MONGO_PORT"
}

stop_mongodb() {
    print_header "Stopping Local MongoDB Container"
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Stopping container..."
        docker stop "$CONTAINER_NAME"
        print_success "Container stopped"
    else
        print_warning "Container $CONTAINER_NAME is not running"
    fi
}

cleanup() {
    print_header "Cleaning Up"
    
    print_warning "This will remove the local MongoDB container and data!"
    read -p "Are you sure? (yes/no): " -r
    echo
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        # Stop and remove container
        if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            print_info "Removing container..."
            docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
            print_success "Container removed"
        fi
        
        # Remove data directory
        if [ -d "$LOCAL_DATA_DIR" ]; then
            print_info "Removing data directory..."
            rm -rf "$LOCAL_DATA_DIR"
            print_success "Data directory removed"
        fi
        
        print_success "Cleanup complete"
    else
        print_info "Cleanup cancelled"
    fi
}

show_status() {
    print_header "Local MongoDB Status"
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        # Show data directory size
        if [ -d "$LOCAL_DATA_DIR" ]; then
            echo ""
            print_info "Data directory: $LOCAL_DATA_DIR"
            du -sh "$LOCAL_DATA_DIR" 2>/dev/null || print_warning "Could not determine size"
        fi
        
        # If running, show databases
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo ""
            print_info "Databases:"
            docker exec "$CONTAINER_NAME" mongosh --quiet \
                -u "$MONGO_USERNAME" -p "$MONGO_PASSWORD" --authenticationDatabase admin \
                --eval "db.adminCommand('listDatabases')" 2>/dev/null | grep -A 100 "databases" || \
                print_warning "Could not list databases"
        fi
    else
        print_warning "Container $CONTAINER_NAME does not exist"
        print_info "Use --start-mongodb to create it"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Restore and manage MongoDB backups locally.

Options:
  --backup FILE       Extract and restore backup from tar.gz file
  --extract-only      Only extract backup, don't start MongoDB
  --start-mongodb     Start local MongoDB container
  --stop-mongodb      Stop local MongoDB container
  --status            Show status of local MongoDB
  --cleanup           Remove container and data (prompts for confirmation)
  -h, --help          Show this help message

Examples:
  # Restore a backup and start MongoDB
  $0 --backup ~/gcloud-sync/mongodb-20251020/mongodb-backup-20251020.tar.gz

  # Just extract without starting
  $0 --backup ~/gcloud-sync/mongodb-20251020/mongodb-backup-20251020.tar.gz --extract-only

  # Start MongoDB (if already extracted)
  $0 --start-mongodb

  # Check status
  $0 --status

  # Stop MongoDB
  $0 --stop-mongodb

  # Clean up everything
  $0 --cleanup

Data directory: $LOCAL_DATA_DIR
Container name: $CONTAINER_NAME
Port: $MONGO_PORT

EOF
}

# ============================================================================
# Main Script
# ============================================================================

# Parse arguments
BACKUP_FILE=""
EXTRACT_ONLY=false
START_MONGODB=false
STOP_MONGODB=false
CLEANUP=false
SHOW_STATUS=false

if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --extract-only)
            EXTRACT_ONLY=true
            shift
            ;;
        --start-mongodb)
            START_MONGODB=true
            shift
            ;;
        --stop-mongodb)
            STOP_MONGODB=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
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

# Execute operations
if [ "$SHOW_STATUS" = true ]; then
    show_status
    exit 0
fi

if [ "$CLEANUP" = true ]; then
    cleanup
    exit 0
fi

if [ "$STOP_MONGODB" = true ]; then
    stop_mongodb
    exit 0
fi

if [ -n "$BACKUP_FILE" ]; then
    check_docker
    extract_backup "$BACKUP_FILE"
    
    if [ "$EXTRACT_ONLY" = false ]; then
        start_mongodb
    else
        print_success "Backup extracted. Use --start-mongodb to start the container."
    fi
elif [ "$START_MONGODB" = true ]; then
    check_docker
    start_mongodb
fi

print_success "Done!"

