#!/usr/bin/env python3
"""
DefenSYS Database Restore Script
Restores the PostgreSQL database from a compressed custom-format backup (.dump) file.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

DEFAULT_BACKUP_DIR = "/var/backups/defensys"

def load_env_file():
    """Locate and load the database environment configuration from .env."""
    script_dir = Path(__file__).resolve().parent
    
    possible_paths = [
        script_dir / "../../backend/.env",
        Path.cwd() / "backend/.env",
        Path.cwd() / ".env",
        Path.home() / ".defensys.env"
    ]
    
    env_override = os.environ.get("DEFENSYS_ENV_PATH")
    if env_override:
        possible_paths.insert(0, Path(env_override))

    loaded = False
    for path in possible_paths:
        if path.exists():
            print(f"Loading environment from: {path.resolve()}")
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

def get_backup_files():
    """Scan the backup directories and return a list of available .dump files."""
    backup_dir = os.environ.get("DEFENSYS_BACKUP_DIR", DEFAULT_BACKUP_DIR)
    local_dir = Path(__file__).resolve().parent / "backups"
    
    paths_to_scan = [Path(backup_dir), local_dir]
    dump_files = []
    
    for path in paths_to_scan:
        if path.exists() and path.is_dir():
            dump_files.extend(list(path.glob("defensys_db_*.dump")))
            
    # Sort by modification time (newest first)
    dump_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return dump_files

def prompt_select_backup(files):
    """Prompt the user to select a backup file from a list."""
    if not files:
        print("No backup files (.dump) found in standard directories.")
        return None
        
    print("\nAvailable backup files:")
    for idx, filepath in enumerate(files):
        mtime = filepath.stat().st_mtime
        import time
        time_str = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(mtime))
        size_mb = filepath.stat().st_size / (1024 * 1024)
        print(f" [{idx + 1}] {filepath.name} ({time_str} - {size_mb:.2f} MB)")
        
    while True:
        try:
            choice = input(f"\nSelect a backup to restore (1-{len(files)}) or press Enter to cancel: ").strip()
            if not choice:
                return None
            idx = int(choice) - 1
            if 0 <= idx < len(files):
                return files[idx]
            print(f"Invalid selection. Please choose between 1 and {len(files)}.")
        except ValueError:
            print("Please enter a valid number.")

def perform_restore(backup_file, force=False):
    """Execute pg_restore to restore the database dump."""
    db_name = os.environ.get("POSTGRES_DB", "defensys_db")
    db_user = os.environ.get("POSTGRES_USER", "defensys")
    db_password = os.environ.get("POSTGRES_PASSWORD", "")
    db_host = os.environ.get("POSTGRES_HOST", "localhost")
    db_port = os.environ.get("POSTGRES_PORT", "5432")
    
    if not Path(backup_file).exists():
        print(f"Error: Backup file not found: {backup_file}", file=sys.stderr)
        sys.exit(1)
        
    print(f"\nTarget Database Details:")
    print(f" Host: {db_host}:{db_port}")
    print(f" Database: {db_name}")
    print(f" User: {db_user}")
    print(f" Backup file: {backup_file.resolve()}")
    
    if not force:
        confirm = input(f"\nWARNING: This will clean/overwrite the database '{db_name}'. Are you sure? (yes/no): ").strip().lower()
        if confirm not in ("yes", "y"):
            print("Restoration cancelled.")
            sys.exit(0)
            
    print(f"\nRestoring database from '{backup_file.name}'...")
    
    # Build command
    # --clean: Drop database objects before recreating them
    # --if-exists: Use IF EXISTS when dropping objects (reduces stderr noise)
    # --no-owner: Skip restoration of object ownership to match current DB user
    # --no-privileges: Skip restoration of access privileges (ACLs)
    cmd = [
        "pg_restore",
        "-h", db_host,
        "-p", db_port,
        "-U", db_user,
        "-d", db_name,
        "--clean",
        "--if-exists",
        "--no-owner",
        "--no-privileges",
        "-v",
        str(backup_file)
    ]
    
    # Set password in environment
    env = os.environ.copy()
    env["PGPASSWORD"] = db_password
    
    try:
        # Run restore, capture stderr for warning filtration
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        
        # pg_restore often issues harmless warnings (e.g. about privileges it skipped)
        # We consider return code 0 as success.
        if result.returncode == 0:
            print("\nDatabase restoration completed successfully!")
            if result.stderr:
                # Filter out standard non-critical messages if verbose is desired
                print("\nRestore notes/warnings:\n" + result.stderr)
        else:
            print(f"\nError: Database restoration failed with exit code {result.returncode}!", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            sys.exit(1)
            
    except FileNotFoundError:
        print("Error: 'pg_restore' utility not found. Please make sure PostgreSQL client tools are installed.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Restore PostgreSQL database from custom backup files (.dump)")
    parser.add_index = parser.add_argument(
        "backup_path", 
        nargs="?", 
        help="Path to the .dump file. If omitted, you will be prompted to select from standard backup directories."
    )
    parser.add_argument(
        "--force", 
        action="store_true", 
        help="Skip database overwrite confirmation prompt."
    )
    args = parser.parse_args()
    
    load_env_file()
    
    if args.backup_path:
        backup_file = Path(args.backup_path)
    else:
        files = get_backup_files()
        backup_file = prompt_select_backup(files)
        if not backup_file:
            print("No backup selected. Exiting.")
            sys.exit(0)
            
    perform_restore(backup_file, args.force)

if __name__ == "__main__":
    main()
