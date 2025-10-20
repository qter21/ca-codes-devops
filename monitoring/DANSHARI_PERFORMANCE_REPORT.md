# Danshari Performance Issue Report

**Date**: October 20, 2025  
**Status**: 🔴 CRITICAL - High CPU Usage  
**Response Time**: 6.4 seconds (SLOW)

---

## Problem Summary

Danshari.ai is experiencing severe performance degradation due to a **runaway Python process consuming 93.8% CPU** that has been running continuously for **10 days and 14 hours**.

### Symptoms
- ⚠️ Website response time: **6.4 seconds** (should be <1 second)
- 🔴 CPU usage: **93.8%** sustained (critical)
- ✅ Memory usage: 9.7% (normal)
- ✅ Disk usage: 18% (normal)

### Root Cause
```
PID: 592157
Process: python3 (danshari-compose container)
CPU: 93.8%
Runtime: 10 days, 14+ hours without restart
```

The Open-WebUI application (Python/FastAPI) has a process that's been running at maximum CPU for over 10 days, likely due to:
1. Memory leak or runaway background task
2. Inefficient AI model loading/processing
3. Stuck background job or infinite loop
4. Resource-intensive operation that never completes

---

## Immediate Solutions

### 1. Restart Container (Quick Fix)
**Time**: 2-3 minutes  
**Downtime**: Minimal

```bash
# Restart the danshari-compose container
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker restart danshari-compose'

# Wait 30 seconds and verify
sleep 30
curl -I https://danshari.ai

# Check CPU usage after restart
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker stats --no-stream danshari-compose'
```

**Expected Result**: CPU should drop to 5-15% normal usage

### 2. Monitor After Restart
Watch for CPU to creep back up:

```bash
# Real-time monitoring
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='watch -n 5 docker stats --no-stream'

# Or check periodically
cd ~/github_19988/ca-codes-devops/monitoring
./check-danshari-status.sh
```

---

## Short-Term Solutions (If Issue Recurs)

### Upgrade Instance Size
If CPU stays high after restart, upgrade to more powerful instance:

**Current**: e2-standard-4 (4 vCPU, 16GB)  
**Recommended**: e2-standard-8 (8 vCPU, 32GB)

```bash
# Stop instance
gcloud compute instances stop danshari-v-25 --zone=us-west2-a

# Upgrade machine type
gcloud compute instances set-machine-type danshari-v-25 \
  --zone=us-west2-a \
  --machine-type=e2-standard-8

# Start instance
gcloud compute instances start danshari-v-25 --zone=us-west2-a
```

**Cost Impact**: ~$120/month → ~$240/month (+$120)

### Alternative: Use Spot Instance
For development, consider using spot/preemptible instance to save 60-70%:

```bash
# Create new spot instance (requires recreation)
# Not recommended for production
```

---

## Medium-Term Solutions

### 1. Deploy Proper Monitoring
Set up continuous monitoring to catch this early:

```bash
cd ~/github_19988/ca-codes-devops/monitoring
./deploy-danshari-monitoring.sh --email your.email@example.com
```

This creates:
- Real-time CPU/memory alerts (>85% for 5 mins)
- Dashboard for visualization
- Uptime checks every 60 seconds
- Email notifications for issues

### 2. Set Up Auto-Restart
Add a health check that restarts on sustained high CPU:

```bash
# On the instance, create a monitoring script
gcloud compute ssh danshari-v-25 --zone=us-west2-a

# Create restart script (run as cron job)
cat > ~/check-and-restart.sh << 'EOF'
#!/bin/bash
CPU=$(docker stats --no-stream danshari-compose --format "{{.CPUPerc}}" | tr -d '%')
if (( $(echo "$CPU > 90" | bc -l) )); then
    echo "$(date): High CPU detected ($CPU%), restarting..."
    docker restart danshari-compose
fi
EOF

chmod +x ~/check-and-restart.sh

# Add to crontab (runs every 10 minutes)
(crontab -l 2>/dev/null; echo "*/10 * * * * ~/check-and-restart.sh >> ~/restart.log 2>&1") | crontab -
```

### 3. Add Resource Limits
Limit container resources to prevent runaway processes:

```yaml
# In docker-compose.yml
services:
  danshari:
    deploy:
      resources:
        limits:
          cpus: '3.5'
          memory: 14G
        reservations:
          cpus: '2'
          memory: 8G
```

---

## Long-Term Solutions

### 1. Code Investigation
Check Open-WebUI for:
- Background tasks running indefinitely
- AI model loading issues
- Memory leaks in Python code
- Inefficient database queries

```bash
# Check for error patterns in logs
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker logs danshari-compose --tail 1000 | grep -i "error\|warning\|exception"'

# Check for specific issues
docker logs danshari-compose | grep -E "model|loading|processing" | tail -50
```

### 2. Optimize Configuration
- Enable caching (Redis is already running)
- Reduce AI model size
- Configure worker processes properly
- Enable connection pooling

### 3. Consider Containerization Alternatives
- Use Kubernetes for better resource management
- Deploy on Cloud Run for auto-scaling
- Use managed services for AI (Vertex AI)

---

## Performance Benchmarks

### Expected Performance
| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Response Time | <1s | 6.4s | 🔴 |
| CPU Usage | <30% | 93% | 🔴 |
| Memory Usage | <50% | 9.7% | ✅ |
| Uptime | 99.9% | ✅ | ✅ |

### After Restart (Expected)
| Metric | Expected |
|--------|----------|
| Response Time | 0.5-1.5s |
| CPU Usage | 5-15% idle, 30-50% under load |
| Memory Usage | 15-25% |

---

## Monitoring Setup

### Deploy Monitoring Dashboard
```bash
cd ~/github_19988/ca-codes-devops/monitoring
./deploy-danshari-monitoring.sh --email daniel@example.com
```

### Check Status Regularly
```bash
# Quick status check
./check-danshari-status.sh

# Continuous monitoring
watch -n 10 './check-danshari-status.sh | grep -A5 "Resource Usage"'
```

### Key Metrics to Watch
1. **CPU**: Should be <30% average, <60% peak
2. **Response Time**: Should be <2 seconds
3. **Memory**: Should be <50% and stable
4. **Restart Count**: Should be minimal

---

## Action Plan

### Immediate (Now)
- [ ] Restart danshari-compose container
- [ ] Verify response time improves
- [ ] Monitor CPU usage for 30 minutes

### Short-Term (Today)
- [ ] Deploy monitoring dashboard
- [ ] Set up email alerts
- [ ] Document baseline performance after restart

### Medium-Term (This Week)
- [ ] Review application logs for errors
- [ ] Check for known Open-WebUI issues
- [ ] Consider instance upgrade if needed
- [ ] Set up auto-restart script

### Long-Term (This Month)
- [ ] Optimize application configuration
- [ ] Implement resource limits
- [ ] Review cost optimization opportunities
- [ ] Plan for scaling strategy

---

## Quick Commands

```bash
# Restart container
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker restart danshari-compose'

# Check status
cd ~/github_19988/ca-codes-devops/monitoring
./check-danshari-status.sh

# Deploy monitoring
./deploy-danshari-monitoring.sh --email your@email.com

# View real-time stats
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker stats'

# Check logs
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker logs -f danshari-compose'
```

---

## Support Resources

- **GCP Console**: https://console.cloud.google.com/compute/instances?project=project-anshari
- **Monitoring**: https://console.cloud.google.com/monitoring/dashboards?project=project-anshari
- **Logs**: https://console.cloud.google.com/logs/query?project=project-anshari
- **Open-WebUI Docs**: https://docs.openwebui.com/

---

**Next Step**: **Restart the container immediately** to restore normal performance.

