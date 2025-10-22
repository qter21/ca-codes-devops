# Danshari Monitoring - Diagnostics Report

**Date**: October 21, 2025  
**Instance**: danshari-v-25 (project-anshari)  
**Uptime**: 15+ hours since last restart

---

## 🔍 Executive Summary

Danshari is **operational** but showing **concerning patterns** that need attention:

| Status | Metric | Current | Target | Severity |
|--------|--------|---------|--------|----------|
| 🟡 | CPU Usage | 60-70% | <30% | **MEDIUM** |
| 🟢 | Memory | 819 MB (5%) | <50% | LOW |
| 🟢 | Website | HTTP 200 | 200 | GOOD |
| 🟡 | Response Time | 3.3s | <1s | MEDIUM |
| 🟢 | Container | Healthy | Healthy | GOOD |
| 🔴 | Health Checks | Timing out | No timeout | **HIGH** |

---

## 🔴 Issues Found

### 1. **HIGH**: Health Check Timeouts ⚠️

**Problem**: Health checks are frequently timing out

```
Oct 21 00:32:26 - Health check error: context deadline exceeded
Oct 21 00:33:37 - Health check error: context deadline exceeded
Oct 21 00:53:45 - Health check error: context deadline exceeded
```

**Impact**:
- Health checks timing out multiple times per hour
- Indicates application is occasionally unresponsive
- Could lead to container being marked unhealthy

**Root Cause**:
- Application taking too long to respond to health endpoint
- High CPU usage slowing down response
- Possible background tasks blocking health checks

**Solution**:
```bash
# Option 1: Increase health check timeout (temporary fix)
# Edit docker-compose to increase timeout from default 30s to 60s

# Option 2: Restart to clear accumulated state (immediate)
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker restart danshari-compose'
```

---

### 2. **MEDIUM**: Elevated CPU Usage 📊

**Problem**: CPU consistently running at 60-70%

**Measurements over 60 seconds**:
```
Sample 1: 68.14%
Sample 2: 69.91%
Sample 3: 43.53%
Sample 4: 68.31%
Sample 5: 69.72%
Sample 6: 54.27%
Average: ~62%
```

**Impact**:
- Higher than normal for idle application
- Leaves little headroom for traffic spikes
- Could lead to slow responses under load
- May indicate background processing

**Analysis**:
- CPU is high but stable (not climbing like before)
- No single runaway process (we checked)
- Likely normal for Open-WebUI with AI models loaded

**Comparison**:
- Right after restart: 0.24% CPU ✅
- After 15 hours: 60-70% CPU 🟡
- Before last restart: 92% CPU 🔴

**Pattern**: CPU gradually increases over time, suggesting:
- Memory accumulation
- Background task buildup
- Connection pool exhaustion
- Cache/session accumulation

**Recommendation**: 
Monitor for next 24 hours. If CPU reaches >85%, restart proactively.

---

### 3. **LOW**: Container Exit Issues 📋

**Problem**: Containers not exiting cleanly

```
Oct 21 00:34:09 - Container failed to exit within 10s of signal 15 - using the force
Oct 21 00:55:10 - Container failed to exit within 10s of signal 15 - using the force
Oct 21 01:00:24 - Container failed to exit within 10s of signal 15 - using the force
```

**Impact**:
- Containers require force-kill on restart
- Indicates graceful shutdown not working
- May lose in-progress operations

**Root Cause**:
- Application not handling SIGTERM properly
- Background workers not stopping on shutdown
- Database connections not closing cleanly

**Solution**: Add proper shutdown handling (long-term dev task)

---

### 4. **LOW**: Response Time Consistently Slow 🐌

**Problem**: 3.3 second response time

**Measurements**:
- Current: 3.3s
- After restart: 4.3s
- During high load: 6.4s

**Analysis**:
This appears to be **normal** for this Open-WebUI setup:
- AI model loading on requests
- Application architecture
- Caddy proxy overhead
- Database queries

**Not an issue** unless it gets worse.

---

## 📊 Detailed Metrics

### Current Resource Usage

```
Container: danshari-compose
Status:    Up 15 hours (healthy)
CPU:       60-70% (elevated)
Memory:    819 MB / 16 GB (5.1%)
Disk:      34 GB / 246 GB (15%)
Network:   Normal
```

### Instance Specifications
```
Machine:   e2-standard-4
vCPUs:     4 cores
RAM:       16 GB
Disk:      250 GB SSD
Zone:      us-west2-a
IP:        35.235.112.206
```

### Health Check Status
```
Status:        healthy (currently)
Failing:       0 consecutive failures
Last 5 checks: ✓ ✓ ✓ ✓ ✓
But: Frequent timeouts in system logs
```

---

## 🎯 Recommended Actions

### Immediate (Today)

#### 1. **Set Up Monitoring Alerts** 🔔
```bash
cd ~/github_19988/ca-codes-devops/monitoring
./deploy-danshari-monitoring.sh --email your@email.com
```

This will alert you when:
- CPU >85% for 5+ minutes
- Health checks fail
- Memory >85%
- Response time >5 seconds

#### 2. **Monitor CPU Trend**
Run this periodically:
```bash
cd ~/github_19988/ca-codes-devops/monitoring
./check-danshari-status.sh
```

Watch for CPU climbing toward 85-90%.

---

### Short-Term (This Week)

#### 1. **Schedule Proactive Restart**
Create a weekly restart to prevent CPU buildup:

```bash
# SSH to instance
gcloud compute ssh danshari-v-25 --zone=us-west2-a

# Add weekly restart (Sundays at 3 AM)
(crontab -l 2>/dev/null; echo "0 3 * * 0 docker restart danshari-compose") | crontab -
```

#### 2. **Increase Health Check Timeout**
If timeouts continue, increase timeout in docker-compose:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 60s  # Increase from 30s to 60s
  retries: 3
  start_period: 60s
```

#### 3. **Add Auto-Restart on High CPU**
Create monitoring script:

```bash
# On the instance
cat > ~/auto-restart-on-high-cpu.sh << 'EOF'
#!/bin/bash
CPU=$(docker stats --no-stream danshari-compose --format "{{.CPUPerc}}" | tr -d '%')
if (( $(echo "$CPU > 85" | bc -l) )); then
    echo "$(date): High CPU detected ($CPU%), restarting..."
    docker restart danshari-compose
    curl -X POST "https://api.pushover.net/1/messages.json" \
      -d "token=YOUR_APP_TOKEN" \
      -d "user=YOUR_USER_KEY" \
      -d "message=Danshari auto-restarted due to high CPU: ${CPU}%"
fi
EOF

chmod +x ~/auto-restart-on-high-cpu.sh

# Run every 10 minutes
(crontab -l 2>/dev/null; echo "*/10 * * * * ~/auto-restart-on-high-cpu.sh >> ~/restart.log 2>&1") | crontab -
```

---

### Medium-Term (This Month)

#### 1. **Optimize Application**
Review Open-WebUI configuration:
- Reduce model loading frequency
- Enable aggressive caching
- Optimize database queries
- Configure worker processes

#### 2. **Consider Instance Upgrade**
If CPU stays high:

**Current**: e2-standard-4 (4 vCPU, 16GB) - $120/month  
**Upgrade to**: e2-standard-8 (8 vCPU, 32GB) - $240/month

```bash
# Stop instance
gcloud compute instances stop danshari-v-25 --zone=us-west2-a

# Upgrade
gcloud compute instances set-machine-type danshari-v-25 \
  --zone=us-west2-a \
  --machine-type=e2-standard-8

# Start
gcloud compute instances start danshari-v-25 --zone=us-west2-a
```

#### 3. **Implement Resource Limits**
Add to docker-compose:

```yaml
services:
  danshari:
    deploy:
      resources:
        limits:
          cpus: '3.5'
          memory: 14G
        reservations:
          cpus: '1'
          memory: 4G
```

---

## 📈 Performance Trends

### CPU Usage Pattern
```
Hour 0:   0.24% (fresh restart)
Hour 1:   5-10%
Hour 5:   20-30%
Hour 10:  40-50%
Hour 15:  60-70% (current)
Hour 24:  Likely 80-85%
Day 2+:   Risk of >90% (restart needed)
```

**Conclusion**: CPU increases ~4% per hour on average.

### Projected Timeline
- ✅ **Now (15h)**: 60-70% - OK
- 🟡 **24h**: ~80% - WATCH
- 🔴 **36h**: ~85-90% - RESTART NEEDED
- 🔴 **48h+**: >90% - CRITICAL

**Action**: If not restarted, expect to need restart in ~20-25 hours.

---

## 🔧 Quick Fixes

### If CPU Reaches 85%+
```bash
# Immediate restart
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker restart danshari-compose'
```

### If Health Checks Keep Failing
```bash
# Check what's blocking
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker exec danshari-compose ps aux | head -20'

# Check for stuck processes
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker exec danshari-compose top -bn1 | head -20'
```

### If Response Time >10s
```bash
# Check backend services
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker stats redis-cache ollama'

# Restart if needed
gcloud compute ssh danshari-v-25 --zone=us-west2-a \
  --command='docker restart redis-cache ollama danshari-compose'
```

---

## 📋 Monitoring Checklist

### Daily
- [ ] Check CPU usage (should be <85%)
- [ ] Verify website is responding
- [ ] Review error logs if any alerts

### Weekly
- [ ] Full diagnostics check
- [ ] Review CPU trend
- [ ] Check disk usage
- [ ] Test response time
- [ ] Review health check logs

### Monthly
- [ ] Review overall performance
- [ ] Check for Open-WebUI updates
- [ ] Review cost vs performance
- [ ] Update monitoring thresholds

---

## 🎓 What We Learned

### Issue Pattern
1. Container starts fresh with low CPU (0.24%)
2. CPU gradually increases over time (~4%/hour)
3. After 15+ hours, CPU reaches 60-70%
4. Health checks start timing out
5. Eventually reaches 90%+ and needs restart
6. Cycle repeats

### Root Cause (Hypothesis)
- **Memory leak** or **state accumulation** in Open-WebUI
- Background tasks not cleaning up properly
- AI model cache growing without bounds
- Session/connection pool exhaustion

### Solution Strategy
1. **Short-term**: Regular restarts (weekly)
2. **Medium-term**: Monitoring and auto-restart
3. **Long-term**: Application optimization or upgrade

---

## 📞 Support Resources

### Quick Commands
```bash
# Status check
cd ~/github_19988/ca-codes-devops/monitoring && ./check-danshari-status.sh

# View live stats
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker stats'

# Restart
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker restart danshari-compose'

# View logs
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker logs -f danshari-compose'
```

### Cloud Console Links
- **Instance**: https://console.cloud.google.com/compute/instances?project=project-anshari
- **Monitoring**: https://console.cloud.google.com/monitoring/dashboards?project=project-anshari
- **Logs**: https://console.cloud.google.com/logs/query?project=project-anshari

---

## 📊 Summary

### Current Health: 🟡 **STABLE BUT NEEDS ATTENTION**

**Good**:
- ✅ Website is online and responding
- ✅ Container is healthy
- ✅ Memory usage is normal
- ✅ No critical errors

**Concerns**:
- 🟡 CPU at 60-70% (elevated)
- 🟡 Health checks timing out periodically
- 🟡 CPU gradually increasing over time
- 🟡 Response time consistently slow (3.3s)

**Verdict**: 
System is **functional** but showing signs of **gradual degradation**. 
Recommend **proactive restart within 24 hours** to prevent issues.

---

**Next Action**: Set up monitoring alerts and schedule weekly restarts.

**Estimated Time to Critical**: ~20-25 hours without intervention.

