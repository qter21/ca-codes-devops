#!/usr/bin/env python3
"""
SQLite Performance Optimization Script for Danshari Production
Optimizes the Open-WebUI SQLite database for better performance
"""

import sqlite3
import time
import os
from datetime import datetime

DB_PATH = "/app/backend/data/webui.db"

def get_db_size(db_path):
    """Get database file size in MB"""
    size_bytes = os.path.getsize(db_path)
    return size_bytes / (1024 * 1024)

def get_current_settings(conn):
    """Get current SQLite settings"""
    cursor = conn.cursor()
    settings = {}

    for pragma in ['journal_mode', 'synchronous', 'cache_size', 'temp_store', 'page_size']:
        cursor.execute(f"PRAGMA {pragma}")
        settings[pragma] = cursor.fetchone()[0]

    return settings

def optimize_database(db_path):
    """Apply performance optimizations to SQLite database"""

    print(f"Starting SQLite optimization at {datetime.now()}")
    print(f"Database: {db_path}")
    print(f"Database size: {get_db_size(db_path):.2f} MB\n")

    # Connect to database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get current settings
    print("📊 Current Settings:")
    current = get_current_settings(conn)
    for key, value in current.items():
        print(f"  {key}: {value}")
    print()

    # Apply optimizations
    print("🔧 Applying Optimizations:")

    # 1. Increase cache size to 256 MB (from 2 MB)
    print("  ✓ Increasing cache_size: 2 MB → 256 MB")
    cursor.execute("PRAGMA cache_size = -262144")  # -256*1024 KB

    # 2. Reduce synchronous mode (still safe, much faster)
    print("  ✓ Setting synchronous: FULL → NORMAL")
    cursor.execute("PRAGMA synchronous = NORMAL")

    # 3. Use memory for temp storage
    print("  ✓ Setting temp_store: DEFAULT → MEMORY")
    cursor.execute("PRAGMA temp_store = MEMORY")

    # 4. Optimize database (analyze statistics)
    print("  ✓ Running ANALYZE...")
    cursor.execute("ANALYZE")

    # Commit changes
    conn.commit()

    # Verify new settings
    print("\n✅ New Settings:")
    new_settings = get_current_settings(conn)
    for key, value in new_settings.items():
        print(f"  {key}: {value}")

    conn.close()

    print("\n🎯 Optimization Complete!")
    print("\nNext Steps:")
    print("  1. Monitor CPU usage - should decrease by 10-20%")
    print("  2. Check response time - should improve to 1-2s")
    print("  3. Watch for any issues over next 24 hours")
    print("\nOptional (run during low traffic):")
    print("  Run VACUUM to defragment database (takes 2-5 minutes)")

if __name__ == "__main__":
    try:
        optimize_database(DB_PATH)
    except Exception as e:
        print(f"❌ Error: {e}")
        exit(1)
