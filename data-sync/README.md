# Data Sync Scripts

This folder contains scripts and documentation for syncing data from Google Cloud production to your local development environment.

## 📂 Contents

| File | Description |
|------|-------------|
| `sync-from-gcloud.sh` | Main script to download data from Google Cloud |
| `restore-local.sh` | Script to restore and run MongoDB locally |
| `SYNC_GUIDE.md` | Complete usage guide with examples |
| `SYNC_IMPLEMENTATION.md` | Technical implementation details |
| `QUICK_SYNC_REFERENCE.md` | Quick reference card for common commands |

## 🚀 Quick Start

### 1. Sync Data from Production
```bash
./sync-from-gcloud.sh --all
```

### 2. Restore Locally
```bash
./restore-local.sh --backup ~/gcloud-sync/mongodb-*/mongodb-backup-*.tar.gz
```

### 3. Connect to MongoDB
```bash
mongosh mongodb://admin:legalcodes123@localhost:27017/ca_codes_db
```

## 📖 Documentation

For complete documentation, see:
- **[QUICK_SYNC_REFERENCE.md](QUICK_SYNC_REFERENCE.md)** - Quick reference
- **[SYNC_GUIDE.md](SYNC_GUIDE.md)** - Complete guide
- **[SYNC_IMPLEMENTATION.md](SYNC_IMPLEMENTATION.md)** - Technical details

## ⚡ Common Commands

```bash
# List available options
./sync-from-gcloud.sh --help
./restore-local.sh --help

# List backups in Cloud Storage
./sync-from-gcloud.sh --list-backups

# Check local MongoDB status
./restore-local.sh --status

# Stop local MongoDB
./restore-local.sh --stop-mongodb
```

## 💾 Storage Requirements

- Compressed backup: ~25 GB
- Extracted data: ~50 GB
- **Total: ~75 GB free space needed**

## 🔒 Connection Info

**Local MongoDB:**
- Host: `localhost:27017`
- Username: `admin`
- Password: `legalcodes123`
- Database: `ca_codes_db`

## 📍 Data Locations

- Synced backups: `~/gcloud-sync/`
- Extracted data: `~/mongodb-local-data/`
- Container name: `ca-codes-mongodb-local`

