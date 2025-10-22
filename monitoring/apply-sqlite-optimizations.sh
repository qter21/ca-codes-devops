#!/bin/bash
# Apply SQLite optimizations to Danshari and restart container

set -e

echo "🔧 Applying SQLite Optimizations to Danshari Production"
echo "======================================================="
echo ""

# Step 1: Apply permanent settings
echo "Step 1: Applying permanent optimizations..."
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker exec danshari-compose python3 -c "
import sqlite3
conn = sqlite3.connect(\"/app/backend/data/webui.db\")
cursor = conn.cursor()
cursor.execute(\"PRAGMA journal_mode = WAL\")
cursor.execute(\"PRAGMA synchronous = NORMAL\")
cursor.execute(\"ANALYZE\")
conn.commit()
print(\"✅ Permanent optimizations applied\")
conn.close()
"'

echo ""
echo "Step 2: Creating startup optimization script..."

# Create a startup script that applies optimizations on every container start
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='cat > /tmp/optimize-sqlite-startup.py << '\''EOF'\''
#!/usr/bin/env python3
import sqlite3
import time

# Wait for application to start
time.sleep(5)

try:
    conn = sqlite3.connect("/app/backend/data/webui.db")
    cursor = conn.cursor()

    # Apply connection-specific optimizations
    cursor.execute("PRAGMA cache_size = -262144")  # 256 MB
    cursor.execute("PRAGMA temp_store = MEMORY")

    conn.commit()
    conn.close()
    print("✅ SQLite startup optimizations applied")
except Exception as e:
    print(f"❌ Error applying optimizations: {e}")
EOF
'

echo "✅ Optimization scripts created"
echo ""
echo "Step 3: Restarting container to apply all optimizations..."
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker restart danshari-compose'

echo ""
echo "⏳ Waiting for container to restart (30 seconds)..."
sleep 30

echo ""
echo "Step 4: Verifying optimizations..."
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker exec danshari-compose python3 -c "
import sqlite3
conn = sqlite3.connect(\"/app/backend/data/webui.db\")
cursor = conn.cursor()

print(\"📊 Current SQLite Settings:\")
cursor.execute(\"PRAGMA journal_mode\")
print(f\"  journal_mode: {cursor.fetchone()[0]}\")
cursor.execute(\"PRAGMA synchronous\")
sync_val = cursor.fetchone()[0]
print(f\"  synchronous: {sync_val} (1=NORMAL, 2=FULL)\")
cursor.execute(\"PRAGMA cache_size\")
cache = cursor.fetchone()[0]
print(f\"  cache_size: {cache} ({abs(cache)//1024 if cache < 0 else cache} {'MB' if cache < 0 else 'pages'})\")

conn.close()
"'

echo ""
echo "Step 5: Checking performance..."
echo "CPU Usage:"
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker stats --no-stream danshari-compose'

echo ""
echo "✅ Optimization Complete!"
echo ""
echo "Monitor these metrics over the next hour:"
echo "  - CPU should decrease by 10-20%"
echo "  - Response time should improve to 1-2s"
echo "  - No errors in logs"
