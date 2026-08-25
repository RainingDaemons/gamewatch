#!/usr/bin/env python3
"""Weekly status.db backup + cleanup.

Creates a timestamped backup of the status database under ``backups/``
and then prunes check-history rows older than the retention window, so
the live database keeps only the most recent week of logs.

Paths and behaviour are driven by environment variables (mirroring the
status-page app):

    STATUS_DB_PATH        live database file (default /opt/status-page/data/status.db)
    STATUS_BACKUP_DIR     where backups are written (default /opt/status-page/backups)
    STATUS_RETENTION_DAYS how many days of checks to keep (default 7)
"""

import os
import secrets
import sqlite3
import string
import sys
from datetime import datetime, timedelta

DB_PATH = os.environ.get("STATUS_DB_PATH", "/opt/status-page/data/status.db")
BACKUP_DIR = os.environ.get("STATUS_BACKUP_DIR", "/opt/status-page/backups")
RETENTION_DAYS = int(os.environ.get("STATUS_RETENTION_DAYS", "7"))

ALPHANUMERIC = string.ascii_letters + string.digits


def random_suffix(length: int = 6) -> str:
    return "".join(secrets.choice(ALPHANUMERIC) for _ in range(length))


def backup_database(db_path: str, backup_dir: str) -> str:
    """Copy the live DB to ``backups/status-DDMMYYYY-xxxxxx.db`` (WAL-safe)."""
    os.makedirs(backup_dir, exist_ok=True)

    date_part = datetime.now().strftime("%d%m%Y")
    destination = os.path.join(backup_dir, f"status-{date_part}-{random_suffix()}.db")

    source = sqlite3.connect(db_path)
    target = sqlite3.connect(destination)
    try:
        source.backup(target)
    finally:
        target.close()
        source.close()

    return destination


def prune_old_rows(db_path: str, retention_days: int) -> int:
    """Delete check rows older than the retention window; returns rows removed."""
    cutoff = int((datetime.now() - timedelta(days=retention_days)).timestamp() * 1000)
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.execute("DELETE FROM checks WHERE checked_at < ?", (cutoff,))
        conn.commit()
        return cursor.rowcount
    finally:
        conn.close()


def main() -> int:
    if not os.path.exists(DB_PATH):
        print(f"error: {DB_PATH} not found", file=sys.stderr)
        return 1

    backup_path = backup_database(DB_PATH, BACKUP_DIR)
    print(f"backup created: {backup_path}")

    deleted = prune_old_rows(DB_PATH, RETENTION_DAYS)
    print(f"pruned {deleted} rows older than {RETENTION_DAYS} days")

    return 0


if __name__ == "__main__":
    sys.exit(main())
