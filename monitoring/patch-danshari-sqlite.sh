#!/bin/bash
# Patch Open-WebUI to use optimized SQLite settings

set -e

echo "🔧 Patching Danshari Open-WebUI for Optimized SQLite Performance"
echo "================================================================"
echo ""

gcloud compute ssh danshari-v-25 --zone=us-west2-a << 'ENDSSH'

# Backup the original file
echo "📦 Backing up original db.py..."
docker exec danshari-compose cp /app/backend/open_webui/internal/db.py /app/backend/open_webui/internal/db.py.backup

# Create the patch script
cat > /tmp/patch-db.py << 'EOF'
import re

db_file = "/app/backend/open_webui/internal/db.py"

# Read the file
with open(db_file, 'r') as f:
    content = f.read()

# Find and replace the SQLite engine creation
old_pattern = r'elif "sqlite" in SQLALCHEMY_DATABASE_URL:\s+engine = create_engine\(\s+SQLALCHEMY_DATABASE_URL, connect_args=\{"check_same_thread": False\}\s+\)'

new_code = '''elif "sqlite" in SQLALCHEMY_DATABASE_URL:
    def _on_connect(conn, record):
        """Apply optimizations on each connection"""
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA cache_size = -262144")  # 256 MB
        conn.execute("PRAGMA temp_store = MEMORY")
        conn.execute("PRAGMA mmap_size = 268435456")  # 256 MB mmap
        conn.execute("PRAGMA journal_mode = WAL")

    from sqlalchemy import event
    engine = create_engine(
        SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
    )
    event.listen(engine, "connect", _on_connect)'''

# Replace
if re.search(old_pattern, content, re.DOTALL):
    content = re.sub(old_pattern, new_code, content, flags=re.DOTALL)

    # Write back
    with open(db_file, 'w') as f:
        f.write(content)

    print("✅ Successfully patched db.py with SQLite optimizations")
else:
    print("⚠️  Pattern not found, trying alternative approach...")

    # Try simpler replacement
    if 'connect_args={"check_same_thread": False}' in content:
        # Insert the optimization function before the engine creation
        insert_pos = content.find('elif "sqlite" in SQLALCHEMY_DATABASE_URL:')
        if insert_pos != -1:
            lines = content.split('\n')
            new_lines = []
            for i, line in enumerate(lines):
                new_lines.append(line)
                if 'elif "sqlite" in SQLALCHEMY_DATABASE_URL:' in line:
                    # Add the optimization code
                    new_lines.append('    def _on_connect(conn, record):')
                    new_lines.append('        """Apply optimizations on each connection"""')
                    new_lines.append('        conn.execute("PRAGMA synchronous = NORMAL")')
                    new_lines.append('        conn.execute("PRAGMA cache_size = -262144")')
                    new_lines.append('        conn.execute("PRAGMA temp_store = MEMORY")')
                    new_lines.append('        conn.execute("PRAGMA mmap_size = 268435456")')
                    new_lines.append('        conn.execute("PRAGMA journal_mode = WAL")')
                    new_lines.append('')
                    new_lines.append('    from sqlalchemy import event')
                elif 'engine = create_engine(' in line and i > 0 and '"sqlite"' in '\n'.join(lines[max(0,i-5):i]):
                    new_lines.append('    event.listen(engine, "connect", _on_connect)')

            with open(db_file, 'w') as f:
                f.write('\n'.join(new_lines))

            print("✅ Successfully patched db.py with alternative method")
        else:
            print("❌ Could not find insertion point")
            exit(1)
    else:
        print("❌ Could not find connect_args")
        exit(1)
EOF

# Copy patch script to container
docker cp /tmp/patch-db.py danshari-compose:/tmp/

# Run the patch
echo "🔨 Applying patch..."
docker exec danshari-compose python3 /tmp/patch-db.py

# Verify the patch
echo ""
echo "🔍 Verifying patch..."
docker exec danshari-compose grep -A5 "def _on_connect" /app/backend/open_webui/internal/db.py || echo "⚠️  Could not verify (but may still work)"

# Restart container to apply changes
echo ""
echo "🔄 Restarting container to apply changes..."
docker restart danshari-compose

ENDSSH

echo ""
echo "⏳ Waiting for container to restart (40 seconds)..."
sleep 40

echo ""
echo "📊 Checking if optimizations are active..."
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker exec danshari-compose python3 -c "
import sqlite3
conn = sqlite3.connect(\"/app/backend/data/webui.db\")
cursor = conn.cursor()

print(\"SQLite Settings:\")
cursor.execute(\"PRAGMA synchronous\")
sync = cursor.fetchone()[0]
print(f\"  synchronous: {sync} (0=OFF, 1=NORMAL, 2=FULL, 3=EXTRA)\")

cursor.execute(\"PRAGMA cache_size\")
cache = cursor.fetchone()[0]
if cache < 0:
    print(f\"  cache_size: {cache} ({abs(cache)//1024} MB)\")
else:
    print(f\"  cache_size: {cache} pages\")

cursor.execute(\"PRAGMA temp_store\")
temp = cursor.fetchone()[0]
print(f\"  temp_store: {temp} (0=DEFAULT, 1=FILE, 2=MEMORY)\")

cursor.execute(\"PRAGMA journal_mode\")
jm = cursor.fetchone()[0]
print(f\"  journal_mode: {jm}\")

conn.close()

if sync == 1:
    print(\"\n✅ Optimizations appear to be active!\")
else:
    print(\"\n⚠️  Optimizations may not be active yet\")
"'

echo ""
echo "📈 Current Performance:"
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker stats --no-stream danshari-compose'

echo ""
echo "✅ Patch Complete!"
echo ""
echo "Monitor over the next hour for:"
echo "  - CPU usage should stabilize at 40-50%"
echo "  - Response time should be 1-2s"
echo "  - No application errors"
