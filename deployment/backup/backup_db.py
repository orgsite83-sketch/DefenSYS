#!/usr/bin/env python3
"""
DefenSYS Database Backup Script
Dumps the PostgreSQL database to a compressed custom-format file and cleans up old backups.
"""

import os
import sys
import subprocess
import datetime
import glob
from pathlib import Path

# Default configuration
DEFAULT_RETENTION_DAYS = 7
DEFAULT_BACKUP_DIR = "/var/backups/defensys"
FALLBACK_BACKUP_DIR = "./backups"

def load_env_file():
    """Locate and load the database environment configuration from .env."""
    script_dir = Path(__file__).resolve().parent
    
    # Check possible paths for .env
    possible_paths = [
        script_dir / "../../backend/.env",
        Path.cwd() / "backend/.env",
        Path.cwd() / ".env",
        Path.home() / ".defensys.env"
    ]
    
    # Override via environment variable if set
    env_override = os.environ.get("DEFENSYS_ENV_PATH")
    if env_override:
        possible_paths.insert(0, Path(env_override))

    loaded = False
    for path in possible_paths:
        if path.exists():
            print(f"Loading environment from: {path.resolve()}")
            # Simple manual parser to avoid dependency issues if run outside venv
            try:
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            parts = line.split("=", 1)
                            key = parts[0].strip()
                            val = parts[1].strip().strip("'").strip('"')
                            os.environ[key] = val
                loaded = True
                break
            except Exception as e:
                print(f"Warning: Failed to read {path}: {e}")
                
    if not loaded:
        print("Warning: No .env configuration file loaded. Falling back to environment defaults.")

def get_backup_dir():
    """Retrieve and verify the backup directory, with user and local fallbacks."""
    backup_dir = os.environ.get("DEFENSYS_BACKUP_DIR", DEFAULT_BACKUP_DIR)
    path = Path(backup_dir)
    
    try:
        path.mkdir(parents=True, exist_ok=True)
        # Try writing a small test file to verify permissions
        test_file = path / ".test_write"
        test_file.touch()
        test_file.unlink()
        return path
    except Exception:
        fallback_path = Path(__file__).resolve().parent / FALLBACK_BACKUP_DIR
        print(f"Warning: Cannot write to '{backup_dir}'. Using local fallback: '{fallback_path}'")
        fallback_path.mkdir(parents=True, exist_ok=True)
        return fallback_path

def perform_backup(backup_dir):
    """Execute pg_dump to back up the database."""
    # Retrieve configuration with defaults
    db_name = os.environ.get("POSTGRES_DB", "defensys_db")
    db_user = os.environ.get("POSTGRES_USER", "defensys")
    db_password = os.environ.get("POSTGRES_PASSWORD", "")
    db_host = os.environ.get("POSTGRES_HOST", "localhost")
    db_port = os.environ.get("POSTGRES_PORT", "5432")
    
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = backup_dir / f"defensys_db_{timestamp}.dump"
    
    print(f"Starting backup for database: '{db_name}' on '{db_host}:{db_port}'...")
    
    # Build command
    # -F c: Custom binary format (highly recommended for pg_restore)
    # -b: Include large objects
    # -v: Verbose output
    cmd = [
        "pg_dump",
        "-h", db_host,
        "-p", db_port,
        "-U", db_user,
        "-d", db_name,
        "-F", "c",
        "-b",
        "-f", str(backup_file)
    ]
    
    # Execute pg_dump, passing the password securely via environment variables
    env = os.environ.copy()
    env["PGPASSWORD"] = db_password
    
    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
        print(f"Success! Database backup completed: {backup_file.resolve()}")
        # Print pg_dump log warnings if any
        if result.stderr:
            print("pg_dump notes:\n" + result.stderr)
        return backup_file
    except subprocess.CalledProcessError as e:
        print(f"Error: Database backup failed!", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        # Clean up partial file if created
        if backup_file.exists():
            backup_file.unlink()
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'pg_dump' utility not found. Please make sure PostgreSQL client tools are installed.", file=sys.stderr)
        sys.exit(1)

def run_retention_cleanup(backup_dir):
    """Scan backup directory and remove files exceeding the retention limit."""
    try:
        retention_days = int(os.environ.get("DEFENSYS_BACKUP_RETENTION_DAYS", DEFAULT_RETENTION_DAYS))
    except ValueError:
        retention_days = DEFAULT_RETENTION_DAYS
        
    print(f"Cleaning up backups older than {retention_days} days in '{backup_dir}'...")
    
    cutoff = datetime.datetime.now() - datetime.timedelta(days=retention_days)
    pattern = str(backup_dir / "defensys_db_*.dump")
    files = glob.glob(pattern)
    
    removed_count = 0
    for file_path in files:
        path = Path(file_path)
        # Check modification time
        mtime = datetime.datetime.fromtimestamp(path.stat().st_mtime)
        if mtime < cutoff:
            try:
                path.unlink()
                print(f"Removed expired backup: {path.name} (Created {mtime.strftime('%Y-%m-%d %H:%M:%S')})")
                removed_count += 1
            except Exception as e:
                print(f"Warning: Failed to delete '{path.name}': {e}")
                
    print(f"Retention cleanup finished. Removed {removed_count} file(s).")

def main():
    load_env_file()
    backup_dir = get_backup_dir()
    perform_backup(backup_dir)
    run_retention_cleanup(backup_dir)

if __name__ == "__main__":
    main()
