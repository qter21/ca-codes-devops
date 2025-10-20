# Data Sync Guide - Google Cloud to Local

This guide explains how to sync data from your Google Cloud production environment to your local machine.

## Overview

Two new scripts have been created for data synchronization:

1. **`sync-from-gcloud.sh`** - Downloads data from Google Cloud to local
2. **`restore-local.sh`** - Restores and runs MongoDB locally with the synced data

## Quick Start

### Sync MongoDB Data from Production

```bash
# Sync everything (MongoDB + configuration)
./sync-from-gcloud.sh --all

# Or just sync MongoDB data
./sync-from-gcloud.sh --mongodb
```

### Restore and Run Locally

```bash
# Restore the downloaded backup
./restore-local.sh --backup ~/gcloud-sync/mongodb-YYYYMMDD-HHMMSS/mongodb-backup-YYYYMMDD-HHMMSS.tar.gz

# Check status
./restore-local.sh --status
```

---

## Script 1: sync-from-gcloud.sh

### Purpose
Downloads MongoDB data and configuration files from your Google Cloud production environment.

### Prerequisites
- `gcloud` CLI installed and authenticated
- `gsutil` installed
- SSH access to the `codecond` instance

### Usage

#### List Available Cloud Backups
```bash
./sync-from-gcloud.sh --list-backups
```

#### Sync MongoDB Data (Fresh Backup)
Creates a fresh backup on the instance and downloads it:
```bash
./sync-from-gcloud.sh --mongodb
```

**What it does:**
1. Creates a compressed backup on the production instance
2. Downloads it to `~/gcloud-sync/mongodb-YYYYMMDD-HHMMSS/`
3. Cleans up the temporary file on the instance

#### Download Specific Backup from Cloud Storage
If you have backups stored in Google Cloud Storage:
```bash
./sync-from-gcloud.sh --from-backup mongodb-backup-20251020.tar.gz
```

#### Sync Configuration Files
Downloads docker-compose.yml and other config files:
```bash
./sync-from-gcloud.sh --config
```

#### Sync Everything
MongoDB data + configuration files:
```bash
./sync-from-gcloud.sh --all
```

#### Dry Run
See what would happen without actually doing it:
```bash
./sync-from-gcloud.sh --dry-run --mongodb
```

### Output Locations

All synced data goes to `~/gcloud-sync/`:

```
~/gcloud-sync/
├── mongodb-20251020-143022/
│   └── mongodb-backup-20251020-143022.tar.gz    # MongoDB data
├── config-20251020-143022/
│   ├── docker-compose.yml                        # Production config
│   ├── .env.production.backup                    # Env vars (if available)
│   └── logs-list.txt                             # Log files list
└── backups/
    └── mongodb-backup-20251020.tar.gz            # From Cloud Storage
```

### Options

| Option | Description |
|--------|-------------|
| `--mongodb` | Sync MongoDB data directly from instance |
| `--from-backup FILE` | Download specific backup from Cloud Storage |
| `--config` | Sync configuration files only |
| `--all` | Sync everything (default if no options) |
| `--list-backups` | List available backups in Cloud Storage |
| `--dry-run` | Show what would be done without doing it |
| `-h, --help` | Show help message |

---

## Script 2: restore-local.sh

### Purpose
Extracts and runs MongoDB locally using the synced backup data.

### Prerequisites
- Docker Desktop installed and running
- MongoDB backup file (from `sync-from-gcloud.sh`)

### Usage

#### Restore and Start MongoDB
```bash
./restore-local.sh --backup ~/gcloud-sync/mongodb-20251020-143022/mongodb-backup-20251020-143022.tar.gz
```

**What it does:**
1. Extracts the backup to `~/mongodb-local-data/data/`
2. Starts a MongoDB 7.0 container
3. Mounts the extracted data
4. Configures with production credentials

#### Just Extract (Don't Start)
```bash
./restore-local.sh --backup ~/gcloud-sync/mongodb-20251020-143022/mongodb-backup-20251020-143022.tar.gz --extract-only
```

#### Start MongoDB (If Already Extracted)
```bash
./restore-local.sh --start-mongodb
```

#### Check Status
```bash
./restore-local.sh --status
```

Output shows:
- Container status
- Data directory size
- Available databases

#### Stop MongoDB
```bash
./restore-local.sh --stop-mongodb
```

#### Clean Up Everything
Removes container and all local data:
```bash
./restore-local.sh --cleanup
```

### Connection Details

Once MongoDB is running locally:

```
Host:     localhost:27017
Username: admin
Password: legalcodes123
Database: ca_codes_db
```

**Connect with mongosh:**
```bash
mongosh mongodb://admin:legalcodes123@localhost:27017
```

**Connect in your application:**
```
mongodb://admin:legalcodes123@localhost:27017/ca_codes_db?authSource=admin
```

### Options

| Option | Description |
|--------|-------------|
| `--backup FILE` | Extract and restore backup from tar.gz file |
| `--extract-only` | Only extract backup, don't start MongoDB |
| `--start-mongodb` | Start local MongoDB container |
| `--stop-mongodb` | Stop local MongoDB container |
| `--status` | Show status of local MongoDB |
| `--cleanup` | Remove container and data (with confirmation) |
| `-h, --help` | Show help message |

---

## Complete Workflow Examples

### Example 1: Full Sync and Restore

```bash
# Step 1: Sync data from production
./sync-from-gcloud.sh --all

# Step 2: Restore and start MongoDB locally
./restore-local.sh --backup ~/gcloud-sync/mongodb-20251020-143022/mongodb-backup-20251020-143022.tar.gz

# Step 3: Verify it's working
./restore-local.sh --status

# Step 4: Connect and query
mongosh mongodb://admin:legalcodes123@localhost:27017/ca_codes_db
```

### Example 2: Download Specific Backup

```bash
# Step 1: List available backups
./sync-from-gcloud.sh --list-backups

# Step 2: Download a specific one
./sync-from-gcloud.sh --from-backup mongodb-backup-20251015.tar.gz

# Step 3: Restore it
./restore-local.sh --backup ~/gcloud-sync/backups/mongodb-backup-20251015.tar.gz
```

### Example 3: Test Before Running

```bash
# See what would happen
./sync-from-gcloud.sh --dry-run --mongodb

# If looks good, run for real
./sync-from-gcloud.sh --mongodb
```

### Example 4: Update Local Data

```bash
# Stop current local MongoDB
./restore-local.sh --stop-mongodb

# Sync fresh data from production
./sync-from-gcloud.sh --mongodb

# Restore the new backup
./restore-local.sh --backup ~/gcloud-sync/mongodb-20251020-150000/mongodb-backup-20251020-150000.tar.gz
```

---

## Troubleshooting

### Error: "gcloud CLI is not installed"
```bash
# Install gcloud CLI
brew install --cask google-cloud-sdk

# Or download from: https://cloud.google.com/sdk/docs/install
```

### Error: "Not authenticated with gcloud"
```bash
gcloud auth login
gcloud config set project project-anshari
```

### Error: "Docker is not running"
```bash
# Start Docker Desktop application
open -a Docker
```

### Error: "Instance not found"
```bash
# Verify instance details
gcloud compute instances list --project=project-anshari

# Check if you're in the right project
gcloud config get-value project
```

### Backup is Too Large
If the MongoDB backup is very large (25+ GB), the download may take a while:

```bash
# Check size first
./sync-from-gcloud.sh --list-backups

# Use screen/tmux for long-running downloads
screen
./sync-from-gcloud.sh --mongodb
# Press Ctrl+A, then D to detach
```

### Local Disk Space Issues

Check available space before syncing:
```bash
df -h ~

# MongoDB backup is ~25GB compressed
# Needs ~50GB uncompressed
```

---

## Data Safety Notes

### Production Data
- ✅ Scripts are **read-only** on production
- ✅ No data is modified or deleted on the production instance
- ✅ Temporary backup files are cleaned up automatically

### Local Data
- ⚠️ The `--cleanup` option will delete all local data
- ⚠️ Always verify before running cleanup
- ✅ Original backup tar.gz files are preserved

### Credentials
- 🔒 `.env.production` may not be downloadable (expected for security)
- 🔒 Local MongoDB uses same credentials as production
- 🔒 Keep downloaded backups secure

---

## Advanced Usage

### Automating Backups

Create a cron job to sync regularly:

```bash
# Edit crontab
crontab -e

# Add: Sync every day at 2 AM
0 2 * * * /Users/daniel/github_19988/ca-codes-devops/sync-from-gcloud.sh --mongodb >> /tmp/gcloud-sync.log 2>&1
```

### Syncing to a Different Location

```bash
# Edit sync-from-gcloud.sh
LOCAL_SYNC_DIR="/path/to/your/backup/location"
```

### Using with Development

```bash
# Sync production data
./sync-from-gcloud.sh --mongodb

# Restore locally
./restore-local.sh --backup ~/gcloud-sync/mongodb-*/mongodb-backup-*.tar.gz

# Now your local dev environment has production data
# Update your .env file to point to localhost:27017
```

---

## Files Created

| File | Purpose |
|------|---------|
| `sync-from-gcloud.sh` | Main sync script - downloads from cloud |
| `restore-local.sh` | Restore script - runs MongoDB locally |
| `SYNC_GUIDE.md` | This documentation |

---

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Run with `--dry-run` to see what would happen
3. Use `--help` flag for detailed options
4. Review the scripts - they're well-commented

---

## Related Documentation

- [`README.md`](./README.md) - Main DevOps documentation
- [`DEPLOYMENT_UPGRADE.md`](./DEPLOYMENT_UPGRADE.md) - Deployment procedures
- [`PRODUCTION_CONFIG.md`](./PRODUCTION_CONFIG.md) - Production configuration reference

