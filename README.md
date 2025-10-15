# California Codes Platform - DevOps

Deployment scripts and configuration for the California Codes platform on Google Cloud Platform.

## Quick Start

### 1. Build Images (Local Mac)

```bash
./build-and-push.sh
```

Builds and pushes all Docker images to Google Artifact Registry.

### 2. Deploy to Production

```bash
./deploy.sh
```

Deploys the platform to Google Cloud Compute Engine instance.

## Files

| File | Description |
|------|-------------|
| `docker-compose.production.yml` | Unified docker-compose for all 5 services |
| `build-and-push.sh` | Build images locally (Mac ARM64 → AMD64) and push to Artifact Registry |
| `deploy.sh` | Deploy to GCloud instance `codecond` |
| `.env.production.example` | Environment variables template |
| `DEPLOYMENT_UPGRADE.md` | Complete deployment guide with troubleshooting |

## Services

The platform consists of 5 Docker containers:

1. **codecond-ca** (port 3456) - Next.js website
2. **legal-codes-api** (port 8000) - FastAPI read-only API
3. **ca-fire-pipeline** (port 8001) - Data pipeline (manual start only)
4. **ca-codes-mongodb** (port 27017) - MongoDB database
5. **ca-codes-redis** (port 6379) - Redis cache

## Architecture

```
Load Balancer (HTTPS)
  ↓
https://www.codecond.com
  ↓
Compute Engine (codecond)
  ├── codecond-ca (website)
  ├── legal-codes-api (API)
  ├── ca-fire-pipeline (pipeline)
  ├── ca-codes-mongodb (database)
  └── ca-codes-redis (cache)
```

## Prerequisites

- Docker Desktop with buildx
- gcloud CLI authenticated
- SSH access to `codecond` instance
- All project repositories cloned:
  - `../codecond-ca`
  - `../legal-codes-api`
  - `../ca_fire_pipeline`

## Usage

### Build and Deploy All

```bash
# 1. Build and push images
./build-and-push.sh

# 2. Deploy to production
./deploy.sh
```

### Build Individual Services

```bash
./build-and-push.sh website   # Only website
./build-and-push.sh api       # Only API
./build-and-push.sh pipeline  # Only pipeline
```

### Dry Run

```bash
./deploy.sh --dry-run  # Show what would be done
```

### Running the Pipeline

The data pipeline is not started automatically. To run it:

```bash
# SSH to instance
gcloud compute ssh codecond --zone=us-west2-a

# Start pipeline
cd ~/ca-codes-platform
docker-compose --profile pipeline up ca-fire-pipeline
```

## Configuration

### Environment Variables

**IMPORTANT**: The `.env.production` file in this directory contains **ACTUAL production credentials** from the GCloud instance. It will be automatically copied during deployment.

**Files:**
- `.env.production` - **ACTUAL production values** (used for deployment)
- `.env.production.example` - Template with placeholder values

**Security:**
- `.env.production` is in `.gitignore` - never commit it!
- Keep backup in secure location (1Password, etc.)
- See `PRODUCTION_CONFIG.md` for complete credential reference

**Production Values:**
- MongoDB: admin / legalcodes123
- Redis: legalcodes123
- API Key: project-19988-gcp-api-key
- Firecrawl: fc-775cf5bacc0d4fb0adc87a7ece3b4b13

See `.env.production` for the complete list of environment variables.

## Deployment Details

### Google Cloud Resources

- **Project**: project-anshari
- **Instance**: codecond (e2-standard-2, us-west2-a)
- **Region**: us-west2
- **Artifact Registry**: us-west2-docker.pkg.dev/project-anshari/codecond
- **Public URL**: https://www.codecond.com

### Deployment Directory

All files are deployed to `/home/daniel/ca-codes-platform/` on the instance:

```
/home/daniel/ca-codes-platform/
├── docker-compose.yml
├── .env.production
└── logs/
    ├── api/
    └── pipeline/
```

MongoDB data is persisted to `/data/mongodb/` on the host.

## Common Tasks

### View Logs

```bash
gcloud compute ssh codecond --zone=us-west2-a \
  --command="cd ~/ca-codes-platform && docker-compose logs -f"
```

### Restart a Service

```bash
gcloud compute ssh codecond --zone=us-west2-a \
  --command="cd ~/ca-codes-platform && docker-compose restart codecond-ca"
```

### Check Service Health

```bash
# Website
curl https://www.codecond.com

# API
curl http://34.186.174.110:8000/health

# Direct from instance
gcloud compute ssh codecond --zone=us-west2-a \
  --command="curl http://localhost:3456"
```

### Update a Single Service

```bash
# Build and push
./build-and-push.sh website

# Pull and restart on instance
gcloud compute ssh codecond --zone=us-west2-a \
  --command="cd ~/ca-codes-platform && docker-compose pull codecond-ca && docker-compose up -d codecond-ca"
```

## Troubleshooting

### Images not pulling

```bash
# Re-authenticate on instance
gcloud compute ssh codecond --zone=us-west2-a \
  --command="gcloud auth configure-docker us-west2-docker.pkg.dev --quiet"
```

### Containers not starting

```bash
# Check logs
docker-compose logs <service-name>

# Check status
docker ps -a

# Restart
docker-compose restart <service-name>
```

### Port conflicts

```bash
# Stop old services
cd ~/california-codes-service && docker-compose down
cd ~/codecond-ca && docker-compose down

# Start new services
cd ~/ca-codes-platform && docker-compose up -d
```

## Rollback

If deployment fails, rollback to previous version:

```bash
# Stop new services
cd ~/ca-codes-platform
docker-compose down

# Start old services
cd ~/california-codes-service
docker-compose -f docker-compose.production.yml up -d

cd ~/codecond-ca
docker-compose up -d
```

## Documentation

- **[DEPLOYMENT_UPGRADE.md](DEPLOYMENT_UPGRADE.md)** - Complete deployment guide with troubleshooting
- **[PRODUCTION_CONFIG.md](PRODUCTION_CONFIG.md)** - **Production credentials and configuration reference**
- **[docker-compose.production.yml](docker-compose.production.yml)** - Service configuration
- **[.env.production](.env.production)** - **ACTUAL production environment variables**
- **[.env.production.example](.env.production.example)** - Environment template (for reference)

## Support

For issues or questions:
1. Check logs: `docker-compose logs -f`
2. Review [DEPLOYMENT_UPGRADE.md](DEPLOYMENT_UPGRADE.md)
3. Check GCloud Console for instance/network issues

---

**Last Updated**: October 13, 2025
