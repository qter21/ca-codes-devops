# Quick Sync Reference Card

## 🚀 Most Common Commands

### Sync Everything from Production
```bash
./sync-from-gcloud.sh --all
```

### Restore and Run Locally  
```bash
./restore-local.sh --backup ~/gcloud-sync/mongodb-*/mongodb-backup-*.tar.gz
```

### Connect to Local MongoDB
```bash
mongosh mongodb://admin:legalcodes123@localhost:27017/ca_codes_db
```

---

## 📋 All Available Commands

### sync-from-gcloud.sh

| Command | Description |
|---------|-------------|
| `./sync-from-gcloud.sh --all` | Sync MongoDB + config (most common) |
| `./sync-from-gcloud.sh --mongodb` | Sync only MongoDB data |
| `./sync-from-gcloud.sh --config` | Sync only config files |
| `./sync-from-gcloud.sh --list-backups` | List backups in Cloud Storage |
| `./sync-from-gcloud.sh --from-backup FILE` | Download specific backup from GCS |
| `./sync-from-gcloud.sh --dry-run` | Preview without changes |
| `./sync-from-gcloud.sh --help` | Show help |

### restore-local.sh

| Command | Description |
|---------|-------------|
| `./restore-local.sh --backup FILE` | Restore backup and start MongoDB |
| `./restore-local.sh --status` | Check MongoDB status |
| `./restore-local.sh --start-mongodb` | Start MongoDB container |
| `./restore-local.sh --stop-mongodb` | Stop MongoDB container |
| `./restore-local.sh --cleanup` | Remove everything (with prompt) |
| `./restore-local.sh --help` | Show help |

---

## 📂 File Locations

| What | Where |
|------|-------|
| Synced backups | `~/gcloud-sync/mongodb-YYYYMMDD-HHMMSS/` |
| Config files | `~/gcloud-sync/config-YYYYMMDD-HHMMSS/` |
| Extracted data | `~/mongodb-local-data/data/` |
| Local container | `ca-codes-mongodb-local` |

---

## 🔌 Connection Info

**Local MongoDB:**
```
Host:     localhost:27017
Username: admin
Password: legalcodes123
Database: ca_codes_db
```

**Connection String:**
```
mongodb://admin:legalcodes123@localhost:27017/ca_codes_db?authSource=admin
```

---

## ⚡ Quick Workflows

### Development Setup (First Time)
```bash
# 1. Sync data
./sync-from-gcloud.sh --all

# 2. Restore
./restore-local.sh --backup ~/gcloud-sync/mongodb-*/mongodb-backup-*.tar.gz

# 3. Verify
./restore-local.sh --status
```

### Daily Development
```bash
# Start MongoDB (if stopped)
./restore-local.sh --start-mongodb

# Work on your code...

# Stop when done
./restore-local.sh --stop-mongodb
```

### Refresh Data
```bash
# Stop current
./restore-local.sh --stop-mongodb

# Sync fresh data
./sync-from-gcloud.sh --mongodb

# Restore new data
./restore-local.sh --backup ~/gcloud-sync/mongodb-*/mongodb-backup-*.tar.gz
```

---

## 🆘 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| "gcloud not found" | `brew install --cask google-cloud-sdk` |
| "Not authenticated" | `gcloud auth login` |
| "Docker not running" | Start Docker Desktop |
| "Port 27017 in use" | `./restore-local.sh --stop-mongodb` |
| Takes too long | Use `screen` or `tmux` |
| Out of disk space | Need ~75GB free |

---

## 📖 Full Documentation

- **[SYNC_GUIDE.md](SYNC_GUIDE.md)** - Complete usage guide
- **[SYNC_IMPLEMENTATION.md](SYNC_IMPLEMENTATION.md)** - Technical details
- **[README.md](README.md)** - Main DevOps documentation

---

## 💾 Disk Space Needed

- Compressed backup: **~25 GB**
- Extracted data: **~50 GB**
- **Total: ~75 GB free space required**

---

## 🎯 Pro Tips

1. **Use dry-run first**: `./sync-from-gcloud.sh --dry-run --mongodb`
2. **Check status often**: `./restore-local.sh --status`
3. **Keep backups**: Don't delete tar.gz files immediately
4. **Use screen/tmux**: For long downloads
5. **Stop when idle**: `./restore-local.sh --stop-mongodb` to save resources

---

**Quick Help**: Add `--help` to any command for more options

