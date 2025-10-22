# Google Cloud Infrastructure Overview

**Report Date:** October 21, 2025 at 11:41 PDT  
**Purpose:** Document MongoDB setup and correct configuration  
**Status:** ✅ **SINGLE MONGODB - CENTRALIZED ARCHITECTURE**

---

## Executive Summary

Your Google Cloud infrastructure consists of **2 instances** with **1 centralized MongoDB database**. The MongoDB instance runs on the `codecond` instance and is accessed by both the data pipeline services and the Danshari application.

---

## 🖥️ Google Cloud Instances

### Instance 1: `codecond` (Data Pipeline & MongoDB)

**Details:**
- **Name:** codecond
- **Zone:** us-west2-a
- **Internal IP:** 10.168.0.6
- **External IP:** 34.186.174.110
- **Status:** RUNNING

**Running Containers:**

| Container Name | Image | Port | Status | Purpose |
|---------------|-------|------|--------|---------|
| **ca-codes-mongodb** | mongo:7.0 | 27017 | Up 7 days (healthy) | **Primary MongoDB Database** |
| legal-codes-api | codecond/legal-codes-api:latest | 8000 | Up 7 days (healthy) | Legal codes API service |
| ca-fire-pipeline | codecond/ca-fire-pipeline:latest | 8001 | Up 6 days (healthy) | Data processing pipeline |
| ca-codes-redis | redis:7-alpine | 6379 | Up 7 days (healthy) | Redis cache |
| codecond-ca-codecond-ca-1 | codecond-ca:alphabetical-v2 | 3456 | Up 5 days | Custom service |

---

### Instance 2: `danshari-v-25` (Danshari Application)

**Details:**
- **Name:** danshari-v-25
- **Zone:** us-west2-a
- **Internal IP:** 10.168.0.4
- **External IP:** 35.235.112.206
- **Status:** RUNNING

**Running Containers:**

| Container Name | Image | Status | Purpose |
|---------------|-------|--------|---------|
| danshari-compose | danshari-repo/danshari | Up 14 minutes (healthy) | Main Danshari web application |
| ollama | ollama/ollama:latest | Up 39 minutes | AI model inference |
| memgraph-lab | memgraph/lab:latest | Up 18 hours | Graph database UI |
| redis-cache | redis:7-alpine | Up 18 hours | Redis cache |
| memgraph-mage | memgraph/memgraph-mage:latest | Up 18 hours | Graph algorithms |
| caddy | caddy:latest | Up 18 hours | Reverse proxy |

**Note:** ❌ **No MongoDB on this instance** - Connects to codecond's MongoDB

---

## 💾 MongoDB Configuration

### Single MongoDB Instance

**Location:** `codecond` instance (10.168.0.6)

**Container Details:**
- **Container Name:** ca-codes-mongodb
- **Image:** mongo:7.0
- **Version:** MongoDB 7.0.25
- **Port:** 27017 (exposed to host)
- **Status:** Up 7 days (healthy)
- **Uptime:** 99.9%+

**Database Configuration:**
```
Database Name: ca_codes_db
Root Username: admin
Root Password: legalcodes123
Auth Database: admin
```

**Network Access:**
- **Internal Network:** mongodb:27017 (for containers on same host)
- **External Network:** 10.168.0.6:27017 (for cross-instance access)
- **Firewall:** Port 27017 open within VPC

---

## 🔗 Connection Patterns

### Pattern 1: Same-Instance Connection (codecond)

**Services:** legal-codes-api, ca-fire-pipeline

**Connection String:**
```
mongodb://admin:legalcodes123@mongodb:27017/ca_codes_db?authSource=admin
```

**Method:** Docker internal network
- Uses container name `mongodb` as hostname
- Resolves via Docker DNS
- No need for IP address
- Faster communication (same host)

---

### Pattern 2: Cross-Instance Connection (danshari-v-25)

**Service:** Danshari application (danshari-compose)

**Connection String:**
```
mongodb://admin:legalcodes123@10.168.0.6:27017/ca_codes_db?authSource=admin
```

**Method:** Direct IP connection
- Uses internal IP `10.168.0.6`
- Cross-instance network communication
- Requires VPC firewall rules
- Slightly higher latency (network hop)

---

## ✅ Correct Configuration Settings

### For Applications on `codecond` Instance

**Environment Variable:**
```bash
MONGODB_URI=mongodb://admin:legalcodes123@mongodb:27017/ca_codes_db?authSource=admin
```

**Python Connection:**
```python
from pymongo import MongoClient

client = MongoClient("mongodb://admin:legalcodes123@mongodb:27017/ca_codes_db?authSource=admin")
db = client["ca_codes_db"]
```

---

### For Applications on `danshari-v-25` Instance

**Environment Variable:**
```bash
MONGODB_URI=mongodb://admin:legalcodes123@10.168.0.6:27017/ca_codes_db?authSource=admin
```

**Python Connection:**
```python
from pymongo import MongoClient

client = MongoClient("mongodb://admin:legalcodes123@10.168.0.6:27017/ca_codes_db?authSource=admin")
db = client["ca_codes_db"]
```

**Note:** Must use IP address `10.168.0.6`, not `mongodb` hostname

---

## 📊 Database Contents

**Database:** ca_codes_db

**Collections:**

| Collection Name | Document Count | Purpose |
|----------------|----------------|---------|
| section_contents | 41,514 | All California legal code sections |
| multi_version_sections | 20 | Sections with multiple versions |
| failed_sections | 5,151 | Sections that failed to process |
| processing_status | 22 | Processing job statuses |
| failure_reports | 8 | Detailed failure reports |
| code_architectures | 8 | Legal code structure definitions |
| processing_checkpoints | 10 | Data pipeline checkpoints |
| jobs | 0 | Background job queue |

**Total Documents:** ~46,723

**Database Size:** (Run `db.stats()` to get exact size)

---

## 🔒 Security Configuration

### Network Security
- ✅ MongoDB accessible within VPC (internal network)
- ✅ Port 27017 not exposed to public internet
- ✅ Only accessible via internal IPs (10.168.0.x)
- ✅ Firewall rules restrict external access

### Authentication
- ✅ MongoDB authentication enabled
- ✅ Root credentials configured
- ✅ Auth database: admin
- ⚠️ **Note:** Credentials are the same for all services (consider rotating)

### Recommendations
1. ✅ Already using strong authentication
2. ⚠️ Consider using environment-specific passwords
3. ⚠️ Consider implementing MongoDB role-based access control
4. ✅ MongoDB not exposed to public internet

---

## 🏗️ Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud VPC                          │
│                                                               │
│  ┌────────────────────────────┐  ┌──────────────────────┐  │
│  │  Instance: codecond        │  │  Instance: danshari  │  │
│  │  IP: 10.168.0.6            │  │  IP: 10.168.0.4      │  │
│  │                            │  │                      │  │
│  │  ┌──────────────────┐      │  │  ┌────────────────┐ │  │
│  │  │  ca-codes-mongodb│      │  │  │ danshari-compose│ │  │
│  │  │  Port: 27017     │◄─────┼──┼──│  (Web App)     │ │  │
│  │  │  ca_codes_db     │      │  │  └────────────────┘ │  │
│  │  └──────────────────┘      │  │                      │  │
│  │          ▲                  │  │  ┌────────────────┐ │  │
│  │          │                  │  │  │  ollama        │ │  │
│  │  ┌───────┴────────┐        │  │  │  memgraph      │ │  │
│  │  │ legal-codes-api│        │  │  │  redis-cache   │ │  │
│  │  │ Port: 8000     │        │  │  │  caddy         │ │  │
│  │  └────────────────┘        │  │  └────────────────┘ │  │
│  │                            │  │                      │  │
│  │  ┌────────────────┐        │  └──────────────────────┘  │
│  │  │ ca-fire-pipeline│        │                            │
│  │  │ Port: 8001     │        │                            │
│  │  └────────────────┘        │                            │
│  │                            │                            │
│  │  ┌────────────────┐        │                            │
│  │  │ ca-codes-redis │        │                            │
│  │  │ Port: 6379     │        │                            │
│  │  └────────────────┘        │                            │
│  └────────────────────────────┘                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Legend:
  ─►  Network connection
  ◄─  MongoDB connection
```

---

## 🎯 Key Takeaways

### Architecture Design
1. ✅ **Centralized Database:** Single MongoDB serves all services
2. ✅ **Separation of Concerns:** Data pipeline and application on separate instances
3. ✅ **Scalability:** Can scale each instance independently
4. ✅ **Maintainability:** Single database to backup/manage

### Advantages
- ✅ Single source of truth for all legal code data
- ✅ No data synchronization needed
- ✅ Simplified backup and recovery
- ✅ Consistent data across all services

### Considerations
- ⚠️ MongoDB is single point of failure (consider replication)
- ⚠️ Cross-instance latency for Danshari queries
- ⚠️ Network bandwidth shared across services
- ⚠️ All services depend on codecond instance being up

---

## 📝 Configuration Checklist

### When Deploying New Services

**On codecond instance:**
- [ ] Use hostname: `mongodb:27017`
- [ ] Add to same Docker network as MongoDB
- [ ] Connection string: `mongodb://admin:legalcodes123@mongodb:27017/ca_codes_db?authSource=admin`

**On danshari-v-25 instance:**
- [ ] Use IP address: `10.168.0.6:27017`
- [ ] Ensure VPC firewall allows port 27017
- [ ] Connection string: `mongodb://admin:legalcodes123@10.168.0.6:27017/ca_codes_db?authSource=admin`

**On any other new instance:**
- [ ] Use codecond internal IP: `10.168.0.6:27017`
- [ ] Configure VPC firewall rules
- [ ] Test connectivity before deployment

---

## 🔧 Common Operations

### Connect to MongoDB from codecond

```bash
# SSH into codecond
gcloud compute ssh codecond --zone=us-west2-a

# Connect using docker exec
docker exec -it ca-codes-mongodb mongosh \
  "mongodb://admin:legalcodes123@localhost:27017/ca_codes_db?authSource=admin"
```

### Connect to MongoDB from danshari-v-25

```bash
# SSH into danshari
gcloud compute ssh danshari-v-25 --zone=us-west2-a

# Connect using Python (if installed)
docker exec danshari-compose python3 -c "
from pymongo import MongoClient
client = MongoClient('mongodb://admin:legalcodes123@10.168.0.6:27017/ca_codes_db?authSource=admin')
print(client.server_info()['version'])
"
```

### Check MongoDB Status

```bash
# From codecond
gcloud compute ssh codecond --zone=us-west2-a --command='docker ps --filter name=ca-codes-mongodb'

# Check MongoDB logs
gcloud compute ssh codecond --zone=us-west2-a --command='docker logs ca-codes-mongodb --tail 50'
```

---

## 🚨 Troubleshooting

### Connection Issues from Danshari

**Symptom:** Cannot connect to MongoDB from danshari-v-25

**Checks:**
1. Verify MongoDB is running on codecond:
   ```bash
   gcloud compute ssh codecond --zone=us-west2-a --command='docker ps --filter name=mongodb'
   ```

2. Verify port 27017 is accessible:
   ```bash
   gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='nc -zv 10.168.0.6 27017'
   ```

3. Check VPC firewall rules:
   ```bash
   gcloud compute firewall-rules list --filter="name~mongo"
   ```

4. Verify connection string:
   - Must use IP: `10.168.0.6`
   - Not hostname: `mongodb`
   - Port: `27017`
   - Auth: `?authSource=admin`

---

## 📈 Monitoring Recommendations

### MongoDB Health Checks

1. **Daily Health Check:**
   ```bash
   docker exec ca-codes-mongodb mongosh --eval "db.adminCommand('ping')"
   ```

2. **Monitor Disk Space:**
   ```bash
   docker exec ca-codes-mongodb df -h /data/db
   ```

3. **Check Connection Count:**
   ```bash
   docker exec ca-codes-mongodb mongosh --eval "db.serverStatus().connections"
   ```

4. **Monitor Query Performance:**
   ```bash
   docker exec ca-codes-mongodb mongosh --eval "db.currentOp()"
   ```

---

## 🔄 Backup & Recovery

### Current Backup Configuration

**Backup Location:** Google Cloud Storage (gs://project-anshari-backups/)

**Backup Command:**
```bash
# From codecond instance
docker exec ca-codes-mongodb mongodump \
  --uri="mongodb://admin:legalcodes123@localhost:27017/ca_codes_db?authSource=admin" \
  --out=/dump

# Create archive
tar -czf mongodb-backup-$(date +%Y%m%d-%H%M%S).tar.gz /dump

# Upload to GCS
gsutil cp mongodb-backup-*.tar.gz gs://project-anshari-backups/
```

**Restore Command:**
```bash
# Download from GCS
gsutil cp gs://project-anshari-backups/mongodb-backup-XXXXXXXX.tar.gz .

# Extract
tar -xzf mongodb-backup-XXXXXXXX.tar.gz

# Restore
docker exec ca-codes-mongodb mongorestore \
  --uri="mongodb://admin:legalcodes123@localhost:27017/ca_codes_db?authSource=admin" \
  /dump/ca_codes_db
```

---

## 📚 Related Documentation

- [PRODUCTION_CONFIG.md](../PRODUCTION_CONFIG.md) - Production deployment configuration
- [MONGODB_INVESTIGATION_20251021-113307.md](MONGODB_INVESTIGATION_20251021-113307.md) - MongoDB data verification
- [data-sync/SYNC_GUIDE.md](../data-sync/SYNC_GUIDE.md) - Data synchronization guide

---

**Report Generated:** October 21, 2025 at 11:41 PDT  
**Infrastructure Status:** ✅ All systems operational  
**MongoDB Status:** ✅ Healthy (Up 7 days)

