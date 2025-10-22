#!/bin/bash
# Create SQLite configuration file for Open-WebUI to apply on every connection

set -e

echo "🔧 Creating SQLite Configuration for Danshari"
echo "=============================================="
echo ""

# Create Python script to set persistent PRAGMA settings
gcloud compute ssh danshari-v-25 --zone=us-west2-a << 'ENDSSH'

# Create the optimization script
cat > /tmp/set-sqlite-pragmas.py << 'EOF'
import sqlite3
import sys

db_path = "/app/backend/data/webui.db"

try:
    # Connect and set pragmas
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    conn.execute("PRAGMA temp_store = MEMORY")
    conn.execute("PRAGMA cache_size = -262144")
    conn.execute("PRAGMA optimize")
    conn.commit()

    # Verify
    cursor = conn.cursor()
    cursor.execute("PRAGMA journal_mode")
    jm = cursor.fetchone()[0]
    cursor.execute("PRAGMA synchronous")
    sync = cursor.fetchone()[0]

    print(f"✅ Applied settings: journal_mode={jm}, synchronous={sync}")

    conn.close()
    sys.exit(0)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
EOF

# Copy script into container
docker cp /tmp/set-sqlite-pragmas.py danshari-compose:/tmp/

# Run the script
echo "Applying SQLite settings..."
docker exec danshari-compose python3 /tmp/set-sqlite-pragmas.py

# Create a cron job to apply settings on container restart
echo "Creating startup script..."
cat > /tmp/optimize-sqlite-on-start.sh << 'CRONEOF'
#!/bin/bash
sleep 10
docker exec danshari-compose python3 /tmp/set-sqlite-pragmas.py >> /var/log/sqlite-optimize.log 2>&1
CRONEOF

chmod +x /tmp/optimize-sqlite-on-start.sh

# Add to root crontab to run on reboot
(crontab -l 2>/dev/null | grep -v "optimize-sqlite-on-start"; echo "@reboot /tmp/optimize-sqlite-on-start.sh") | crontab -

echo "✅ Cron job created to apply settings on reboot"

# Restart container
echo ""
echo "Restarting container..."
docker restart danshari-compose

ENDSSH

echo ""
echo "⏳ Waiting for container to restart (30 seconds)..."
sleep 30

echo ""
echo "📊 Verifying settings..."
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker exec danshari-compose python3 -c "
import sqlite3
conn = sqlite3.connect(\"/app/backend/data/webui.db\")
cursor = conn.cursor()

cursor.execute(\"PRAGMA journal_mode\")
jm = cursor.fetchone()[0]
cursor.execute(\"PRAGMA synchronous\")
sync = cursor.fetchone()[0]

print(f\"journal_mode: {jm}\")
print(f\"synchronous: {sync} (1=NORMAL is optimal)\")

conn.close()
"'

echo ""
echo "📈 Current CPU Usage:"
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker stats --no-stream danshari-compose'

echo ""
echo "✅ Optimization Complete!"
