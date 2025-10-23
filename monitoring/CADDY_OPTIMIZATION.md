# Caddy Reverse Proxy Optimization Guide

Best practices and optimization guide for Caddy reverse proxy configuration based on danshari.ai production experience.

## Overview

This guide documents optimal Caddy configuration for production deployments, particularly for high-traffic applications with many concurrent connections.

## Key Learnings

### What We Discovered

**Problem:** 50% of requests experiencing 3-second delays

**Root Cause:** Complex Caddy configuration with HTTP/2 server push

**Solution:** Simplified configuration with optimized connection pooling

## Recommended Configuration

### ✅ Optimal Caddyfile

```caddyfile
your-domain.com {
    # Enable compression
    encode gzip

    # Single reverse proxy block
    reverse_proxy your-backend:8080 {
        transport http {
            keepalive 90s
            keepalive_idle_conns 100
        }
    }

    # Basic security headers
    header {
        X-Content-Type-Options nosniff
        -Server
    }
}
```

### Why This Works

1. **Single reverse_proxy block**
   - Caddy handles WebSocket upgrades automatically
   - No need for separate `@websocket` matcher
   - Reduces configuration complexity

2. **Optimized keepalive settings**
   - `keepalive 90s` - Keeps connections alive for 90 seconds
   - `keepalive_idle_conns 100` - Maintains pool of 100 idle connections
   - Prevents connection churn under high load

3. **Essential features only**
   - Compression for bandwidth optimization
   - Security headers for basic protection
   - No unnecessary directives

## Configuration Pitfalls to Avoid

### ❌ Avoid: HTTP/2 Server Push

```caddyfile
# DON'T DO THIS
push /_app/immutable/assets/*.css
push /_app/immutable/chunks/*.js
```

**Problems:**
- Can cause connection overhead
- Modern browsers have good caching
- May trigger performance issues under load
- Not necessary for most applications

**When to use:**
- Only if you have proven it helps via load testing
- Only for very specific high-traffic scenarios
- Test thoroughly before production

### ❌ Avoid: Duplicate reverse_proxy Blocks

```caddyfile
# DON'T DO THIS
@websocket {
    header Connection *Upgrade*
    header Upgrade websocket
}

reverse_proxy @websocket backend:8080 {
    # WebSocket-specific config
}

reverse_proxy backend:8080 {
    # Regular HTTP config
}
```

**Problems:**
- Adds routing complexity
- Can cause race conditions
- Unnecessary - Caddy handles WebSockets by default

**Better approach:**
- Use single reverse_proxy block
- Caddy automatically detects and handles WebSocket upgrades
- Cleaner and more maintainable

### ❌ Avoid: Low keepalive_idle_conns

```caddyfile
# DON'T DO THIS for high-traffic sites
transport http {
    keepalive_idle_conns 10  # Too low!
}
```

**Problems:**
- Under high load (>100 concurrent connections), pool exhausted
- Forces new connection creation for each request
- Can cause connection refused errors
- Performance degradation

**Solution:**
- Set to at least 100 for production
- Monitor connection count: `netstat -an | grep :PORT | wc -l`
- Adjust based on actual concurrent connection count

### ❌ Avoid: Overly Complex Matchers

```caddyfile
# Avoid unless necessary
@static {
    path /_app/* *.js *.css *.woff2
}

header @static Cache-Control "public, max-age=31536000, immutable"

@hiddenFiles {
    path *.env* *.git*
}

respond @hiddenFiles 403
```

**When to use:**
- Only if you have specific security or caching requirements
- Test performance impact
- Consider handling at application level instead

## Advanced Configurations

### For High-Traffic Sites

If you need advanced features, add them incrementally and test:

```caddyfile
your-domain.com {
    # Essential: Compression
    encode gzip zstd

    # Essential: Reverse proxy with good defaults
    reverse_proxy backend:8080 {
        # Optimized transport settings
        transport http {
            read_timeout 300s
            write_timeout 300s
            dial_timeout 10s
            keepalive 90s
            keepalive_idle_conns 100
        }

        # Optional: Buffering settings
        flush_interval -1
    }

    # Essential: Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        -Server
    }

    # Optional: Request size limit (if needed)
    request_body {
        max_size 10MB
    }
}
```

### For Multiple Protocols

If you need HTTP/1.1, HTTP/2, and HTTP/3:

```caddyfile
{
    servers {
        protocols h1 h2  # Start with just h1 and h2
        max_header_size 16384
    }
}

your-domain.com {
    # ... rest of config
}
```

**Note:** Only enable HTTP/3 if you have proven need and tested it.

## Testing Your Configuration

### 1. Syntax Check

```bash
caddy validate --config /etc/caddy/Caddyfile
```

### 2. Format Check

```bash
caddy fmt --overwrite /etc/caddy/Caddyfile
```

### 3. Performance Test

Before and after configuration changes:

```bash
# Single request timing
curl -o /dev/null -s -w "Total: %{time_total}s\n" https://your-domain.com

# Statistical test (100 requests)
for i in {1..100}; do
  curl -o /dev/null -s -w "%{time_total}s\n" https://your-domain.com
done | awk '{
  sum+=$1;
  if($1>1) slow++;
  if($1<min||min==0) min=$1;
  if($1>max) max=$1;
} END {
  printf "Avg: %.3fs | Min: %.3fs | Max: %.3fs | Slow (>1s): %d/100\n",
  sum/NR, min, max, slow
}'
```

**Expected results:**
- Average: <0.5s
- Max: <1s
- Slow requests: 0/100

### 4. Load Test

Use a tool like `wrk` or `ab`:

```bash
# Install wrk
brew install wrk  # macOS
sudo apt install wrk  # Ubuntu

# Run load test (10 connections, 30 seconds)
wrk -t2 -c10 -d30s https://your-domain.com

# Analyze results
# Look for:
# - Consistent latency
# - No connection errors
# - High requests/sec
```

### 5. Monitor Connections

During load test:

```bash
# On server
watch -n 1 'netstat -an | grep :443 | wc -l'

# Check Caddy logs
docker logs caddy --tail 100 --follow
```

**Look for:**
- Connection count stabilizes (not constantly growing)
- No "connection refused" errors
- No timeout errors

## Configuration Change Process

1. **Backup current config:**
   ```bash
   cp Caddyfile Caddyfile.backup-$(date +%Y%m%d-%H%M%S)
   ```

2. **Make changes incrementally:**
   - Change one thing at a time
   - Test after each change
   - Document what you changed

3. **Test in staging first:**
   - If possible, test on staging environment
   - Run load tests
   - Monitor for 24 hours

4. **Apply to production:**
   - Apply during low-traffic period
   - Monitor closely for 1 hour
   - Have rollback plan ready

5. **Rollback if needed:**
   ```bash
   cp Caddyfile.backup-YYYYMMDD-HHMMSS Caddyfile
   docker exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```

## Monitoring Recommendations

### Key Metrics to Track

1. **Response Time Percentiles:**
   - p50 (median): Should be <200ms
   - p95: Should be <500ms
   - p99: Should be <1s

2. **Connection Pool Usage:**
   - Active connections
   - Idle connections
   - Connection errors

3. **Error Rates:**
   - 502 Bad Gateway
   - 504 Gateway Timeout
   - Connection refused

4. **Backend Health:**
   - Backend response time
   - Backend error rate

### Alert Thresholds

```yaml
# Recommended alerts
- Response time p95 > 1s for 5 minutes
- Connection errors > 10/minute
- 502 errors > 5/minute
- Active connections > 1000
```

## Troubleshooting

### Symptom: Intermittent Slow Requests

**Check:**
1. Connection pool exhaustion
   ```bash
   docker exec caddy netstat -an | grep :443 | wc -l
   ```
2. Backend response time
   ```bash
   docker exec backend curl -s http://localhost:8080 -w "Time: %{time_total}s\n"
   ```

**Solution:**
- Increase `keepalive_idle_conns`
- Check backend performance

### Symptom: Connection Refused Errors

**Check Caddy logs:**
```bash
docker logs caddy --tail 100 | grep -i "connection refused"
```

**Common causes:**
- Backend not listening
- Backend restarting
- Too many connections

**Solution:**
- Check backend is running: `docker ps`
- Increase backend worker count
- Check backend logs

### Symptom: High Latency

**Compare:**
```bash
# Direct to backend
docker exec backend curl -s http://localhost:8080 -w "%{time_total}s\n"

# Through Caddy
curl -s https://your-domain.com -w "%{time_total}s\n"
```

**If latency is:**
- **Same**: Problem is backend
- **Only through Caddy**: Problem is Caddy config

**Solution:**
- If backend: Optimize application
- If Caddy: Simplify configuration

## Production Configuration Example

Current danshari.ai configuration (proven to work):

```caddyfile
chat.danshari.ai {
    # Enable compression
    encode gzip

    # Single reverse proxy block
    reverse_proxy danshari-compose:8080 {
        transport http {
            keepalive 90s
            keepalive_idle_conns 100
        }
    }

    # Basic security headers
    header {
        X-Content-Type-Options nosniff
        -Server
    }
}
```

**Performance:**
- Average response time: 0.289s
- Slow requests (>1s): 0%
- Concurrent connections: ~460
- Uptime: 99.9%

## Best Practices Summary

1. ✅ **Keep it simple** - Start with minimal config
2. ✅ **Test before production** - Always load test changes
3. ✅ **Monitor after changes** - Watch for 24 hours
4. ✅ **Optimize connection pooling** - Set keepalive_idle_conns based on traffic
5. ✅ **Use single reverse_proxy** - Caddy handles WebSockets automatically
6. ✅ **Enable compression** - Gzip is usually sufficient
7. ✅ **Add security headers** - Basic protection is essential
8. ❌ **Avoid HTTP/2 push** - Unless proven beneficial via testing
9. ❌ **Avoid complex matchers** - Unless absolutely necessary
10. ❌ **Don't assume** - Test and measure everything

## References

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddy reverse_proxy Directive](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [HTTP/2 Server Push](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Link) (Why it's often unnecessary)
- [Performance Troubleshooting Guide](PERFORMANCE_TROUBLESHOOTING.md)

## Version History

- **2025-10-22**: Initial version based on danshari.ai production experience
- **Issue Resolved**: 50% of requests with 3s delays → 0% slow requests
- **Configuration**: Complex → Simplified
- **Performance**: 3.3s → 0.289s average response time

---

**Maintained By**: DevOps Team
**Last Updated**: 2025-10-22
**Status**: Production-tested and verified
