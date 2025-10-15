# Production Configuration Reference

**⚠️ CONFIDENTIAL - Contains production credentials and configuration details**

This document describes the actual production configuration for the California Codes platform running on Google Cloud Platform.

## Current Production Setup

### Infrastructure

| Component | Value | Notes |
|-----------|-------|-------|
| **Project ID** | project-anshari | GCP Project |
| **Instance Name** | codecond | Compute Engine instance |
| **Zone** | us-west2-a | Region: us-west2 (Los Angeles) |
| **Machine Type** | e2-standard-2 | 2 vCPU, 8 GB RAM |
| **Internal IP** | 10.168.0.6 | Private VPC IP |
| **External IP** | 34.186.174.110 | Public IP |

### HTTPS & Load Balancer

| Component | Value | Status |
|-----------|-------|--------|
| **Public URL** | https://www.codecond.com | ✅ ACTIVE |
| **HTTPS IP** | 35.201.83.102 | Load balancer |
| **HTTP Redirect IP** | 34.120.183.213 | Auto-redirect to HTTPS |
| **SSL Certificate** | codecond-ssl | ✅ ACTIVE |
| **Domains** | www.codecond.com, codecond.com | Both working |
| **Certificate Type** | Google-managed | Auto-renewal |

### Database Credentials

**MongoDB**
- Username: `admin`
- Password: `legalcodes123`
- Database: `ca_codes_db`
- Port: 27017
- Data Volume: `/data/mongodb` (bind mount)

**Redis**
- Password: `legalcodes123`
- Port: 6379
- Max Memory: 512MB
- Policy: allkeys-lru

### API Keys

| Service | Key/Value | Purpose |
|---------|-----------|---------|
| **API_KEY** | project-19988-gcp-api-key | Internal API authentication |
| **FIRECRAWL_API_KEY** | fc-775cf5bacc0d4fb0adc87a7ece3b4b13 | Firecrawl data pipeline |

### Container Images

**Current (Old):**
- Website: `gcr.io/project-anshari/codecond-ca:empty-db-test`
- API: `gcr.io/project-anshari/california-codes-api:latest`

**New (After Upgrade):**
- Website: `us-west2-docker.pkg.dev/project-anshari/codecond/codecond-ca:latest`
- API: `us-west2-docker.pkg.dev/project-anshari/codecond/legal-codes-api:latest`
- Pipeline: `us-west2-docker.pkg.dev/project-anshari/codecond/ca-fire-pipeline:latest`

### Service Ports

| Service | Port | Accessibility |
|---------|------|--------------|
| **Website** | 3456 | Via load balancer (HTTPS) |
| **API** | 8000 | Internal + firewall open |
| **Pipeline** | 8001 | Internal only |
| **MongoDB** | 27017 | Internal only |
| **Redis** | 6379 | Internal only |

### Data Persistence

| Component | Type | Location |
|-----------|------|----------|
| **MongoDB Data** | Bind Mount | `/data/mongodb` on host |
| **Redis Data** | Docker Volume | `redis-data` volume |
| **API Logs** | Bind Mount | `~/ca-codes-platform/logs/api/` |
| **Pipeline Logs** | Bind Mount | `~/ca-codes-platform/logs/pipeline/` |

### Existing Directory Structure

**Old Setup (Before Upgrade):**
```
/home/daniel/
├── california-codes-service/
│   ├── docker-compose.production.yml
│   ├── .env
│   └── .env.production
└── codecond-ca/
    └── docker-compose.yml
```

**New Setup (After Upgrade):**
```
/home/daniel/
├── ca-codes-platform/              # NEW unified deployment
│   ├── docker-compose.yml
│   ├── .env.production
│   └── logs/
│       ├── api/
│       └── pipeline/
├── california-codes-service/       # OLD - kept for backup
│   └── [old files]
└── codecond-ca/                    # OLD - kept for backup
    └── [old files]
```

### MongoDB Connection Settings

**Production Optimized:**
- Max Pool Size: 50 connections
- Min Pool Size: 10 connections
- Max Idle Time: 60 seconds
- Wait Queue Timeout: 10 seconds
- Server Timeout: 5 seconds
- Connect Timeout: 10 seconds
- Socket Timeout: 30 seconds

### External Services

**California Legislative Information (leginfo.legislature.ca.gov):**
- Base URL: https://leginfo.legislature.ca.gov/faces/
- Codes Display: .../codes_displaySection.xhtml
- Print Window: .../printCodeSectionWindow.xhtml
- Select Multiples: .../selectFromMultiples.xhtml
- Code Expand: .../codedisplayexpand.xhtml

### Performance Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| **Rate Limit** | 0.1s | Delay between requests |
| **Max Retries** | 5 | Request retry attempts |
| **Request Timeout** | 60s | HTTP request timeout |
| **Batch Size** | 20 | Items per batch |
| **Playwright** | Enabled | For complex scraping |
| **Cache** | Enabled | Redis caching |

### Feature Flags

- **USE_PLAYWRIGHT**: `true` - Use Playwright for JavaScript-heavy pages
- **ENABLE_CACHE**: `true` - Enable Redis caching
- **DEBUG_MODE**: `false` - Production mode (no debug logs)

## Security Notes

### Credentials Management

1. **Never commit credentials to git**
   - `.env.production` is in `.gitignore`
   - Keep backup in secure location (1Password, etc.)

2. **Access Control**
   - Only authorized personnel have instance access
   - SSH keys required for instance access
   - API key required for API access

3. **Network Security**
   - MongoDB: Internal only (no external access)
   - Redis: Internal only (no external access)
   - API: Protected by API key
   - Website: Public via HTTPS only

### Firewall Rules

| Rule Name | Protocol | Ports | Source | Target |
|-----------|----------|-------|--------|--------|
| allow-codecond-ca | TCP | 3456 | 0.0.0.0/0 | web-server |
| allow-http | TCP | 80 | 0.0.0.0/0 | web-server |
| allow-https | TCP | 443 | 0.0.0.0/0 | web-server |
| mongodb-access | TCP | 27017 | VPC only | mongodb-access |

## Monitoring & Health

### Health Check Endpoints

- **Website**: `http://localhost:3456` or `https://www.codecond.com`
- **API**: `http://localhost:8000/health`
- **Pipeline**: `http://localhost:8001/health`
- **MongoDB**: `mongosh` ping command
- **Redis**: `redis-cli ping`

### Load Balancer Health Checks

- **Protocol**: HTTP
- **Port**: 3456
- **Path**: `/api/codes` (proxy to API)
- **Interval**: 30 seconds
- **Timeout**: 10 seconds
- **Healthy Threshold**: 2 consecutive successes
- **Unhealthy Threshold**: 3 consecutive failures

### Log Locations

**On Instance:**
- Docker logs: `docker logs <container_name>`
- Application logs: `~/ca-codes-platform/logs/`
- System logs: `/var/log/syslog`

**Cloud Console:**
- Compute Engine > VM instances > codecond > Logs
- Load Balancing > Backend Services > Health checks

## Backup & Recovery

### What's Backed Up

1. **MongoDB Data**: `/data/mongodb` (25+ GB)
2. **Configuration Files**: `.env.production`, `docker-compose.yml`
3. **Application Images**: In Artifact Registry

### Backup Strategy

**Manual Backup:**
```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Backup MongoDB data
sudo tar -czf mongodb-backup-$(date +%Y%m%d).tar.gz /data/mongodb/

# Copy to Cloud Storage (recommended)
gsutil cp mongodb-backup-*.tar.gz gs://project-anshari-backups/
```

**Automated Backup (Recommended):**
- Set up GCP Persistent Disk snapshots
- Schedule: Daily at 2 AM PST
- Retention: 7 days

### Recovery Procedure

1. Stop all services
2. Restore MongoDB data from backup
3. Verify data integrity
4. Start services
5. Test all endpoints

## Cost Analysis

### Current Monthly Costs

| Component | Cost (USD/month) | Notes |
|-----------|------------------|-------|
| **Compute Engine** | ~$60 | e2-standard-2 |
| **Load Balancer** | ~$18 | HTTPS + HTTP redirect |
| **Disk Storage** | ~$4 | 100 GB Standard PD |
| **Network Egress** | ~$5-10 | Varies with traffic |
| **Artifact Registry** | ~$0.10 | Image storage |
| **SSL Certificate** | $0 | Google-managed, free |
| **Total** | **~$87-92** | Approximate |

### Optimization Opportunities

1. **Committed Use Discounts**: Save 30-50% on compute
2. **Preemptible VMs**: Not recommended (need uptime)
3. **Cloud Run Migration**: Could reduce to $50-70/month

## Maintenance Schedule

### Regular Tasks

**Daily:**
- Check service health (automated)
- Review error logs (if any alerts)

**Weekly:**
- Review disk usage
- Check MongoDB size
- Review API performance

**Monthly:**
- Update Docker images
- Review security updates
- Test backup/recovery

**Quarterly:**
- Review cost analysis
- Performance optimization
- Security audit

## Emergency Contacts

### Quick Links

- **GCP Console**: https://console.cloud.google.com/
- **Project Dashboard**: https://console.cloud.google.com/home/dashboard?project=project-anshari
- **Compute Engine**: https://console.cloud.google.com/compute/instances?project=project-anshari
- **Load Balancer**: https://console.cloud.google.com/net-services/loadbalancing?project=project-anshari

### SSH Access

```bash
# Direct SSH
gcloud compute ssh codecond --zone=us-west2-a --project=project-anshari

# With port forwarding (MongoDB)
gcloud compute ssh codecond --zone=us-west2-a -- -L 27017:localhost:27017

# With port forwarding (API)
gcloud compute ssh codecond --zone=us-west2-a -- -L 8000:localhost:8000
```

## Version History

| Date | Version | Changes | Deployed By |
|------|---------|---------|-------------|
| 2025-09-29 | v0.2.8 | HTTPS deployment, complete section access | DevOps |
| 2025-10-13 | v0.3.0 | Unified deployment, ca_fire_pipeline added | DevOps |

---

**Last Updated**: October 13, 2025
**Document Owner**: DevOps Team
**Classification**: CONFIDENTIAL

**⚠️ Security Reminder**: This document contains production credentials. Store securely and restrict access to authorized personnel only.
