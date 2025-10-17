# Danshari.ai GCP Monitoring

Comprehensive monitoring setup for the danshari.ai production environment on Google Cloud Platform.

## Overview

**Instance**: `danshari-v-25`
**Machine Type**: e2-standard-4 (4 vCPU, 16GB RAM)
**Zone**: us-west2-a
**IP**: 35.235.112.206
**Website**: https://danshari.ai

### Running Services

| Container | Image | Port | Status |
|-----------|-------|------|--------|
| danshari-compose | us-west2-docker.pkg.dev/project-anshari/danshari-repo/danshari | 8080 | Running (6 weeks) |
| caddy | caddy:latest | 80, 443 | Running (7 weeks) |
| redis-cache | redis:7-alpine | 6379 | Running (7 weeks) |
| ollama | ollama/ollama:latest | 11434 | Running (7 weeks) |
| memgraph-mage | memgraph/memgraph-mage:latest | 7444, 7687 | Paused |
| memgraph-lab | memgraph/lab:latest | 3888 | Paused |

## Quick Start

### Deploy Monitoring (Recommended)

Deploy all monitoring components with one command:

```bash
cd monitoring/
./deploy-danshari-monitoring.sh
```

Options:
- `--dry-run` - Preview changes without applying
- `--email YOUR_EMAIL` - Set notification email
- `--skip-alerts` - Skip alert creation
- `--skip-uptime` - Skip uptime checks

Example with custom email:
```bash
./deploy-danshari-monitoring.sh --email your.email@example.com
```

### View Dashboard

After deployment:
```bash
# Open in browser
open "https://console.cloud.google.com/monitoring/dashboards?project=project-anshari"

# Or list dashboards
gcloud monitoring dashboards list
```

## Monitoring Components

### 1. Cloud Monitoring Dashboard

File: `danshari-dashboard.json`

**Widgets Include:**
- VM CPU utilization (%)
- VM memory utilization (%)
- Disk read/write rates
- Network traffic (inbound/outbound)
- VM uptime
- Current CPU utilization with thresholds
- Disk utilization percentage
- HTTP request rates
- Container health status
- Quick links and commands

### 2. Alert Policies

File: `danshari-alerts.yaml`

**Critical Alerts:**
- CPU > 95% (3 minutes)
- VM instance down (1 minute)

**Warning Alerts:**
- CPU > 85% (5 minutes)
- Memory > 85% (5 minutes)
- Disk usage > 80% (10 minutes)
- High network egress (>100 MB/s)
- Container unhealthy (restarts detected)

**Informational:**
- Disk usage > 70% (30 minutes)

### 3. Uptime Checks

File: `danshari-uptime-checks.yaml`

**Checks:**
- Main website HTTPS (every 60s)
- Direct IP check (every 300s)
- HTTP to HTTPS redirect
- Health endpoint (every 60s)
- API endpoint (every 120s)

**Regions Monitored:**
- USA
- Europe
- Asia Pacific

**Uptime Alerts:**
- Website down (2 minutes)
- Slow response time (>3 seconds)
- SSL certificate expiring (<30 days)
- Regional availability issues

## Manual Monitoring

### Check Instance Status

```bash
# Instance details
gcloud compute instances describe danshari-v-25 --zone=us-west2-a

# List all instances
gcloud compute instances list

# SSH into instance
gcloud compute ssh danshari-v-25 --zone=us-west2-a
```

### Check Container Status

```bash
# SSH to instance first
gcloud compute ssh danshari-v-25 --zone=us-west2-a

# View all containers
docker ps -a

# View container stats (real-time)
docker stats

# View container logs
docker logs -f danshari-compose
docker logs -f caddy
docker logs -f redis-cache

# Check container health
docker inspect danshari-compose | grep -A10 Health
```

### Check Resource Usage

```bash
# SSH to instance
gcloud compute ssh danshari-v-25 --zone=us-west2-a

# Memory usage
free -h

# Disk usage
df -h

# CPU and processes
top -bn1 | head -20

# Network connections
netstat -tuln
```

### Check Website

```bash
# Test website
curl -I https://danshari.ai

# Test with timing
curl -w "@-" -o /dev/null -s https://danshari.ai <<'EOF'
    time_namelookup:  %{time_namelookup}s\n
       time_connect:  %{time_connect}s\n
    time_appconnect:  %{time_appconnect}s\n
   time_pretransfer:  %{time_pretransfer}s\n
      time_redirect:  %{time_redirect}s\n
 time_starttransfer:  %{time_starttransfer}s\n
                    ----------\n
         time_total:  %{time_total}s\n
EOF

# Test from IP directly
curl -I http://35.235.112.206
```

## View Metrics & Logs

### Cloud Console

**Monitoring Dashboard:**
```
https://console.cloud.google.com/monitoring/dashboards?project=project-anshari
```

**Metrics Explorer:**
```
https://console.cloud.google.com/monitoring/metrics-explorer?project=project-anshari
```

**Logs Explorer:**
```
https://console.cloud.google.com/logs/query?project=project-anshari
```

**Alerts:**
```
https://console.cloud.google.com/monitoring/alerting?project=project-anshari
```

### Command Line

```bash
# View recent logs
gcloud logging read 'resource.type=gce_instance AND resource.labels.instance_id=danshari-v-25' \
  --limit 50 \
  --format json

# View specific time range
gcloud logging read 'resource.type=gce_instance AND resource.labels.instance_id=danshari-v-25' \
  --limit 50 \
  --format json \
  --freshness=1h

# Stream logs (real-time)
gcloud logging tail 'resource.type=gce_instance AND resource.labels.instance_id=danshari-v-25'

# View metrics
gcloud monitoring time-series list \
  --filter='resource.type="gce_instance" AND resource.labels.instance_id="danshari-v-25"' \
  --format=json
```

## Alert Response Playbooks

### Website Down

1. **Check website**: `curl -I https://danshari.ai`
2. **Check VM status**: `gcloud compute instances describe danshari-v-25 --zone=us-west2-a`
3. **SSH to instance**: `gcloud compute ssh danshari-v-25 --zone=us-west2-a`
4. **Check containers**: `docker ps -a`
5. **Check logs**: `docker logs caddy --tail 100`, `docker logs danshari-compose --tail 100`

**If VM is down:**
```bash
gcloud compute instances start danshari-v-25 --zone=us-west2-a
```

**If containers are down:**
```bash
docker restart caddy danshari-compose
```

### High CPU Usage

1. **Check container stats**: `docker stats --no-stream`
2. **Check logs for errors**: `docker logs danshari-compose --tail 100`
3. **Check processes**: `top -bn1 | head -20`
4. **Consider restarting high-usage container**: `docker restart danshari-compose`
5. **If persistent, upgrade instance**:
   ```bash
   # Stop instance
   gcloud compute instances stop danshari-v-25 --zone=us-west2-a

   # Change machine type
   gcloud compute instances set-machine-type danshari-v-25 \
     --zone=us-west2-a \
     --machine-type=e2-standard-8

   # Start instance
   gcloud compute instances start danshari-v-25 --zone=us-west2-a
   ```

### High Memory Usage

1. **Check memory**: `free -h`
2. **Check container memory**: `docker stats --no-stream`
3. **Check for memory leaks**: `docker logs danshari-compose --tail 100`
4. **Restart container if leak suspected**: `docker restart danshari-compose`
5. **Monitor after restart**: `watch -n 5 docker stats --no-stream`

### Disk Full

1. **Check disk usage**: `df -h`
2. **Find large directories**: `du -sh /* | sort -h`
3. **Clean Docker**: `docker system prune -a --volumes`
4. **Clean logs**:
   ```bash
   sudo journalctl --vacuum-time=7d
   sudo find /var/log -type f -name "*.log" -mtime +30 -delete
   ```
5. **Expand disk if needed**:
   ```bash
   # Resize disk
   gcloud compute disks resize danshari-v-25 --size=500GB --zone=us-west2-a

   # Resize filesystem (SSH to instance)
   sudo growpart /dev/sda 1
   sudo resize2fs /dev/sda1
   ```

### Slow Response Time

1. **Check CPU/Memory**: `docker stats --no-stream`
2. **Check logs**: `docker logs danshari-compose --tail 100`
3. **Test database**: `docker exec -it redis-cache redis-cli ping`
4. **Check network**: `ping -c 5 google.com`
5. **Restart containers if needed**: `docker restart danshari-compose redis-cache`

## Maintenance Tasks

### Weekly

- [ ] Review dashboard for anomalies
- [ ] Check disk usage trend
- [ ] Review error logs
- [ ] Verify all alerts are configured correctly

### Monthly

- [ ] Review alert history and adjust thresholds
- [ ] Clean up old Docker images: `docker system prune -a`
- [ ] Check for security updates: `gcloud compute ssh danshari-v-25 --zone=us-west2-a --command="sudo apt update && sudo apt list --upgradable"`
- [ ] Review and optimize container resource allocation
- [ ] Backup critical data

### Quarterly

- [ ] Review monitoring effectiveness
- [ ] Update alert policies based on learned patterns
- [ ] Evaluate instance size and cost optimization
- [ ] Review SSL certificate auto-renewal status
- [ ] Update documentation

## Cost Monitoring

Current estimated monthly costs:
- **Compute Engine (e2-standard-4)**: ~$120
- **Persistent Disk (250GB)**: ~$10
- **Network Egress**: ~$10-20 (varies)
- **Cloud Monitoring**: Free tier (usually covered)
- **Total**: ~$140-150/month

View actual costs:
```
https://console.cloud.google.com/billing?project=project-anshari
```

## Troubleshooting

### Monitoring Agent Not Collecting Metrics

```bash
# SSH to instance
gcloud compute ssh danshari-v-25 --zone=us-west2-a

# Check agent status
sudo systemctl status google-cloud-ops-agent

# Restart agent
sudo systemctl restart google-cloud-ops-agent

# View agent logs
sudo journalctl -u google-cloud-ops-agent -f
```

### Dashboard Not Showing Data

1. Verify monitoring API is enabled:
   ```bash
   gcloud services enable monitoring.googleapis.com
   ```

2. Check if instance has proper service account permissions

3. Verify Ops Agent is installed and running (see above)

4. Wait 5-10 minutes for metrics to populate

### Alerts Not Firing

1. Check notification channel is verified:
   ```bash
   gcloud alpha monitoring channels list
   ```

2. Verify alert policies are enabled:
   ```bash
   gcloud alpha monitoring policies list
   ```

3. Check alert conditions are properly configured

4. Test by manually triggering condition (e.g., stress test CPU)

## Additional Resources

- [GCP Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Ops Agent Documentation](https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent)
- [Alert Policy Documentation](https://cloud.google.com/monitoring/alerts)
- [Uptime Checks Documentation](https://cloud.google.com/monitoring/uptime-checks)

## Support

For issues or questions:
1. Check GCP Status: https://status.cloud.google.com/
2. Review logs in Cloud Console
3. Contact GCP Support if infrastructure issues
4. Check application logs for application-level issues

---

**Last Updated**: 2025-10-17
**Maintained By**: DevOps Team
**Instance**: danshari-v-25 (project-anshari)
