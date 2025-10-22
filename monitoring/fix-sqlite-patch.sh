#!/bin/bash
# Fix the SQLite patch to properly apply optimizations

set -e

echo "🔧 Fixing SQLite Optimization Patch"
echo "===================================="
echo ""

gcloud compute ssh danshari-v-25 --zone=us-west2-a << 'ENDSSH'

# Create corrected patch
cat > /tmp/fix-db-patch.py << 'EOF'
import re

db_file = "/app/backend/open_webui/internal/db.py"

# Read the file
with open(db_file, 'r') as f:
    content = f.read()

# Find the SQLite section and replace with correct implementation
# We need to attach the event listener right after creating the engine

pattern = r'elif "sqlite" in SQLALCHEMY_DATABASE_URL:.*?from sqlalchemy import event\s+engine = create_engine\(\s+SQLALCHEMY_DATABASE_URL, connect_args=\{"check_same_thread": False\}\s+\)\s+event\.listen\(engine, "connect", _on_connect\)'

replacement = '''elif "sqlite" in SQLALCHEMY_DATABASE_URL:
    # SQLite performance optimizations
    from sqlalchemy import event

    engine = create_engine(
        SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
    )

    # Attach event listener to apply PRAGMA settings on every connection
    @event.listens_for(engine, "connect")
    def receive_connect(dbapi_conn, connection_record):
        """Apply performance optimizations on each new connection"""
        dbapi_conn.execute("PRAGMA synchronous = NORMAL")
        dbapi_conn.execute("PRAGMA cache_size = -262144")  # 256 MB
        dbapi_conn.execute("PRAGMA temp_store = MEMORY")
        dbapi_conn.execute("PRAGMA mmap_size = 268435456")  # 256 MB memory-mapped I/O
        dbapi_conn.execute("PRAGMA journal_mode = WAL")'''

# Try to replace
new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

if new_content != content:
    with open(db_file, 'w') as f:
        f.write(new_content)
    print("✅ Successfully applied corrected patch")
else:
    print("⚠️  Exact pattern not found, applying manual fix...")

    # Manual approach - find and replace line by line
    lines = content.split('\n')
    new_lines = []
    skip_until = None
    i = 0

    while i < len(lines):
        line = lines[i]

        if skip_until and i < skip_until:
            i += 1
            continue
        elif skip_until and i >= skip_until:
            skip_until = None

        # Find the section to replace
        if 'elif "sqlite" in SQLALCHEMY_DATABASE_URL:' in line:
            # Keep the elif line
            new_lines.append(line)

            # Skip old implementation and add new one
            indent = '    '
            new_lines.append(f'{indent}# SQLite performance optimizations')
            new_lines.append(f'{indent}from sqlalchemy import event')
            new_lines.append('')
            new_lines.append(f'{indent}engine = create_engine(')
            new_lines.append(f'{indent}    SQLALCHEMY_DATABASE_URL, connect_args={{"check_same_thread": False}}')
            new_lines.append(f'{indent})')
            new_lines.append('')
            new_lines.append(f'{indent}# Attach event listener to apply PRAGMA settings on every connection')
            new_lines.append(f'{indent}@event.listens_for(engine, "connect")')
            new_lines.append(f'{indent}def receive_connect(dbapi_conn, connection_record):')
            new_lines.append(f'{indent}    """Apply performance optimizations on each new connection"""')
            new_lines.append(f'{indent}    dbapi_conn.execute("PRAGMA synchronous = NORMAL")')
            new_lines.append(f'{indent}    dbapi_conn.execute("PRAGMA cache_size = -262144")  # 256 MB')
            new_lines.append(f'{indent}    dbapi_conn.execute("PRAGMA temp_store = MEMORY")')
            new_lines.append(f'{indent}    dbapi_conn.execute("PRAGMA mmap_size = 268435456")  # 256 MB memory-mapped I/O')
            new_lines.append(f'{indent}    dbapi_conn.execute("PRAGMA journal_mode = WAL")')

            # Skip until we find the else or next section
            j = i + 1
            while j < len(lines):
                if lines[j].strip().startswith('else:') or lines[j].strip().startswith('if '):
                    skip_until = j
                    break
                if 'event.listen(engine, "connect"' in lines[j]:
                    # Skip the old event.listen line
                    j += 1
                    continue
                j += 1

            i += 1
            continue

        new_lines.append(line)
        i += 1

    with open(db_file, 'w') as f:
        f.write('\n'.join(new_lines))

    print("✅ Applied manual fix")

EOF

# Run the fix
docker cp /tmp/fix-db-patch.py danshari-compose:/tmp/
docker exec danshari-compose python3 /tmp/fix-db-patch.py

# Verify
echo ""
echo "🔍 Verifying corrected patch..."
docker exec danshari-compose grep -A12 "elif \"sqlite\" in SQLALCHEMY" /app/backend/open_webui/internal/db.py

# Restart to apply
echo ""
echo "🔄 Restarting container..."
docker restart danshari-compose

ENDSSH

echo ""
echo "⏳ Waiting 40 seconds for restart..."
sleep 40

echo ""
echo "✅ Testing optimizations..."
gcloud compute ssh danshari-v-25 --zone=us-west2-a --command='docker stats --no-stream danshari-compose'

echo ""
echo "Done! Monitor CPU over next 10 minutes - should be lower than before."
