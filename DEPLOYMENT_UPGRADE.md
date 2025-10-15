# California Codes Platform - Upgrade Deployment Guide

## Overview

This guide provides step-by-step instructions for upgrading the California Codes platform from the old version to the new unified deployment with the ca_fire_pipeline data pipeline.

## What's New in This Upgrade

### 1. **Unified Docker Compose**
- All services now managed in a single `docker-compose.production.yml`
- Easier to manage and deploy
- Better service dependency management

### 2. **New Data Pipeline**
- **ca_fire_pipeline** - Firecrawl-based data pipeline (10-25x faster)
- Replaces the old Playwright-based pipeline
- Manual start only (on-demand data processing)
- FastAPI with REST endpoints

### 3. **Artifact Registry**
- Images now stored in Google Artifact Registry
- Better version control and rollback capabilities
- Faster deployments with image caching

### 4. **Updated Services**
- **codecond-ca** - Latest website version
- **legal-codes-api** - Renamed from california-codes-api

## Architecture

```
┌─────────────────────────────────────────────────┐
│          Load Balancer (HTTPS)                  │
│        https://www.codecond.com                 │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│       Compute Engine (codecond)                 │
│       10.168.0.6 / 34.186.174.110               │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │  Docker Containers                        │ │
│  │                                           │ │
│  │  • codecond-ca          (port 3456)      │ │
│  │  • legal-codes-api      (port 8000)      │ │
│  │  • ca-fire-pipeline     (port 8001)      │ │
│  │  • ca-codes-mongodb     (port 27017)     │ │
│  │  • ca-codes-redis       (port 6379)      │ │
│  │                                           │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## Prerequisites

### Local Machine (Mac)
- Docker Desktop with buildx support
- gcloud CLI installed and authenticated
- SSH access to codecond instance
- Git repositories cloned:
  - `/Users/daniel/github_19988/codecond-ca`
  - `/Users/daniel/github_19988/legal-codes-api`
  - `/Users/daniel/github_19988/ca_fire_pipeline`
  - `/Users/daniel/github_19988/dev_ops` (this directory)

### Google Cloud
- Project: `project-anshari`
- Instance: `codecond` (e2-standard-2, us-west2-a)
- Existing services running
- Load balancer configured for https://www.codecond.com

## Deployment Steps

### Phase 1: Local Preparation (15-20 minutes)

#### 1. Navigate to dev_ops directory

```bash
cd /Users/daniel/github_19988/dev_ops
```

#### 2. Review configuration files

Check that all files exist:
```bash
ls -la
# Should show:
# - docker-compose.production.yml
# - build-and-push.sh
# - deploy.sh
# - .env.production.example
# - DEPLOYMENT_UPGRADE.md (this file)
```

#### 3. Build and push Docker images

This will build all three images locally and push to Artifact Registry:

```bash
./build-and-push.sh
```

**What it does:**
- Creates buildx builder for multi-arch support
- Authenticates with Google Artifact Registry
- Creates repository (if doesn't exist)
- Builds 3 images:
  - `codecond-ca:latest` (website)
  - `legal-codes-api:latest` (API)
  - `ca-fire-pipeline:latest` (pipeline)
- Pushes to `us-west2-docker.pkg.dev/project-anshari/codecond/`

**Expected time:** 10-15 minutes depending on internet speed

**Troubleshooting:**
- If buildx fails: `docker buildx rm multiarch-builder && docker buildx create --name multiarch-builder --use`
- If auth fails: `gcloud auth login && gcloud auth configure-docker us-west2-docker.pkg.dev`

#### 4. Verify images in Artifact Registry

```bash
gcloud artifacts docker images list us-west2-docker.pkg.dev/project-anshari/codecond
```

You should see three images with their tags.

### Phase 2: Production Deployment (10-15 minutes)

#### 1. Prepare environment file

Before deploying, you need to create `.env.production` on the GCloud instance with your actual secrets.

**Option A: Create it manually on the instance**

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Create deployment directory
mkdir -p ~/ca-codes-platform

# Create .env.production file
nano ~/ca-codes-platform/.env.production
```

Then add:
```bash
# MongoDB
MONGO_USERNAME=admin
MONGO_PASSWORD=your-actual-mongodb-password

# Redis
REDIS_PASSWORD=your-actual-redis-password

# API
API_KEY=your-actual-api-key
LOG_LEVEL=INFO

# Firecrawl (for pipeline)
FIRECRAWL_API_KEY=fc-775cf5bacc0d4fb0adc87a7ece3b4b13
```

**Option B: Copy from existing setup**

If you have existing environment variables in the old setup:

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Copy from old setup
cd ~/california-codes-service
cat .env  # View existing values

# Create new .env.production with same values
# (adjust any changed variable names)
```

#### 2. Run deployment script

Back on your local machine:

```bash
# Dry run first to see what will happen
./deploy.sh --dry-run

# If everything looks good, run the actual deployment
./deploy.sh
```

**What it does:**
1. Checks prerequisites (gcloud auth, instance running)
2. Backs up current configuration
3. Stops old services gracefully
4. Creates deployment directory (`/home/daniel/ca-codes-platform`)
5. Copies configuration files
6. Authenticates Docker on instance
7. Pulls latest images from Artifact Registry
8. Starts all services (except pipeline)
9. Verifies deployment

**Expected time:** 5-10 minutes

#### 3. Monitor deployment

During deployment, you can monitor logs in another terminal:

```bash
# Watch docker containers starting
gcloud compute ssh codecond --zone=us-west2-a --command="watch docker ps"

# View logs
gcloud compute ssh codecond --zone=us-west2-a --command="cd ~/ca-codes-platform && docker-compose logs -f"
```

### Phase 3: Verification (5 minutes)

#### 1. Check service health

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Check all containers are running
docker ps

# Should show:
# - codecond-ca (healthy)
# - legal-codes-api (healthy)
# - ca-codes-mongodb (healthy)
# - ca-codes-redis (healthy)
```

#### 2. Test endpoints

```bash
# On the instance:

# Test website
curl -I http://localhost:3456
# Should return: HTTP/1.1 200 OK

# Test API health
curl http://localhost:8000/health
# Should return: {"status":"ok"}

# Test MongoDB
docker exec ca-codes-mongodb mongosh --quiet --eval 'db.adminCommand({ping: 1})'
# Should return: { ok: 1 }

# Test Redis
docker exec ca-codes-redis redis-cli ping
# Should return: PONG
```

#### 3. Test public website

Open in browser: https://www.codecond.com

- Check homepage loads
- Test code browsing (FAM, CCP, etc.)
- Test section navigation
- Verify all content displays correctly

### Phase 4: Running the Pipeline (Optional)

The data pipeline (ca-fire-pipeline) is NOT started automatically. It should only be run when you need to update or add data.

#### To start the pipeline:

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Navigate to deployment directory
cd ~/ca-codes-platform

# Start pipeline
docker-compose --profile pipeline up ca-fire-pipeline

# Or run in background
docker-compose --profile pipeline up -d ca-fire-pipeline

# Monitor logs
docker-compose logs -f ca-fire-pipeline
```

#### To use pipeline API:

```bash
# Start processing a code
curl -X POST http://localhost:8001/api/v2/crawler/start/EVID

# Check job status
curl http://localhost:8001/api/v2/crawler/status/{job_id}

# API docs
open http://34.186.174.110:8001/docs
```

## Post-Deployment

### Service Management

#### View logs
```bash
gcloud compute ssh codecond --zone=us-west2-a --command="cd ~/ca-codes-platform && docker-compose logs -f"
```

#### Restart a service
```bash
gcloud compute ssh codecond --zone=us-west2-a --command="cd ~/ca-codes-platform && docker-compose restart codecond-ca"
```

#### Stop all services
```bash
gcloud compute ssh codecond --zone=us-west2-a --command="cd ~/ca-codes-platform && docker-compose down"
```

#### Start all services
```bash
gcloud compute ssh codecond --zone=us-west2-a --command="cd ~/ca-codes-platform && docker-compose up -d"
```

### Updating a Single Service

If you only need to update one service (e.g., website):

```bash
# Local: Build and push only the website
cd /Users/daniel/github_19988/dev_ops
./build-and-push.sh website

# On instance: Pull and restart
gcloud compute ssh codecond --zone=us-west2-a --command="cd ~/ca-codes-platform && docker-compose pull codecond-ca && docker-compose up -d codecond-ca"
```

## Rollback Procedure

If something goes wrong, you can rollback to the old configuration:

### Quick Rollback

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Stop new services
cd ~/ca-codes-platform
docker-compose down

# Start old services
cd ~/california-codes-service
docker-compose -f docker-compose.production.yml up -d

cd ~/codecond-ca
docker-compose up -d
```

### Full Rollback with Backup

The deploy script creates a timestamped backup before making changes:

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# List backups
ls -la ~/backup-*

# Restore from backup
cd ~/backup-YYYYMMDD-HHMMSS
# Review backed up files and restore as needed
```

## Troubleshooting

### Issue: Images not pulling

**Symptoms:** `docker-compose pull` fails with authentication error

**Solution:**
```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Re-authenticate
gcloud auth configure-docker us-west2-docker.pkg.dev --quiet

# Try pulling again
cd ~/ca-codes-platform
docker-compose pull
```

### Issue: MongoDB data not accessible

**Symptoms:** API can't connect to MongoDB

**Solution:**
```bash
# Check MongoDB container
docker logs ca-codes-mongodb

# Check data directory permissions
ls -la /data/mongodb

# Ensure correct ownership
sudo chown -R 999:999 /data/mongodb
```

### Issue: Website showing 502 Bad Gateway

**Symptoms:** Load balancer shows 502 error

**Solution:**
```bash
# Check if website container is running
docker ps | grep codecond-ca

# Check website logs
docker logs codecond-ca

# Check health endpoint
curl http://localhost:3456

# Restart if needed
docker-compose restart codecond-ca
```

### Issue: Old services still running

**Symptoms:** Port conflicts or duplicate containers

**Solution:**
```bash
# Stop ALL containers
docker stop $(docker ps -aq)

# Remove stopped containers
docker rm $(docker ps -aq)

# Remove old networks
docker network prune -f

# Start fresh
cd ~/ca-codes-platform
docker-compose up -d
```

## Performance Monitoring

### Check resource usage

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Container stats
docker stats

# Disk usage
df -h

# MongoDB size
docker exec ca-codes-mongodb mongosh --quiet --eval 'db.stats()'
```

### Logs rotation

Logs are stored in `/home/daniel/ca-codes-platform/logs/`. Consider setting up log rotation:

```bash
# Create logrotate config
sudo nano /etc/logrotate.d/ca-codes-platform

# Add:
/home/daniel/ca-codes-platform/logs/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

## Cost Optimization

Current setup (e2-standard-2):
- Cost: ~$60-80/month
- Suitable for moderate traffic

If you need better performance:
```bash
# Upgrade to e2-standard-4
gcloud compute instances stop codecond --zone=us-west2-a
gcloud compute instances set-machine-type codecond --machine-type=e2-standard-4 --zone=us-west2-a
gcloud compute instances start codecond --zone=us-west2-a
```

## Maintenance Schedule

### Weekly
- Review logs for errors
- Check disk usage
- Verify all services healthy

### Monthly
- Update Docker images (rebuild and push)
- Review MongoDB size and performance
- Check for security updates

### As Needed
- Run data pipeline to update codes
- Add new codes to database
- Update SSL certificates (auto-renewed by Google)

## Support and Resources

### Useful Commands Reference

```bash
# View all containers
docker ps -a

# View logs for specific service
docker-compose logs -f codecond-ca

# Enter container shell
docker exec -it codecond-ca sh

# Check MongoDB data
docker exec -it ca-codes-mongodb mongosh -u admin -p <password>

# Redis CLI
docker exec -it ca-codes-redis redis-cli

# Rebuild and restart a service
docker-compose up -d --build codecond-ca

# View network connections
docker network inspect ca-codes-network
```

### Files and Directories

**On local machine:**
- `/Users/daniel/github_19988/dev_ops/` - Deployment scripts
- `/Users/daniel/github_19988/codecond-ca/` - Website source
- `/Users/daniel/github_19988/legal-codes-api/` - API source
- `/Users/daniel/github_19988/ca_fire_pipeline/` - Pipeline source

**On GCloud instance:**
- `/home/daniel/ca-codes-platform/` - Deployment directory
- `/home/daniel/ca-codes-platform/docker-compose.yml` - Main config
- `/home/daniel/ca-codes-platform/.env.production` - Environment variables
- `/home/daniel/ca-codes-platform/logs/` - Application logs
- `/data/mongodb/` - MongoDB data (persistent)

### Google Cloud Resources

- **Project:** project-anshari
- **Instance:** codecond (us-west2-a)
- **Artifact Registry:** us-west2-docker.pkg.dev/project-anshari/codecond
- **Load Balancer:** HTTPS with SSL cert for www.codecond.com
- **Firewall:** Ports 80, 443, 3456, 8000 open

## Conclusion

This upgrade provides a modern, unified deployment with better maintainability and a much faster data pipeline. The deployment should be seamless with zero downtime as the load balancer continues serving traffic during the upgrade.

If you encounter any issues not covered in this guide, check:
1. Container logs: `docker-compose logs -f`
2. Instance logs: Cloud Console > Compute Engine > VM instances > codecond > Logs
3. Load balancer health: Cloud Console > Network Services > Load balancing

---

**Document Version:** 1.0
**Last Updated:** October 13, 2025
**Author:** DevOps Team
