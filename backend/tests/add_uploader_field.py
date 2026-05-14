"""
Script to add is_uploader field to User model directly in the database.
Run this if you can't run migrations.
"""
import os
import django
import sys

# Setup Django
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

def add_uploader_field():
    """Add is_uploader column to the user table"""
    with connection.cursor() as cursor:
        try:
            # Check if column already exists
            cursor.execute("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name='authentication_access_control_user' 
                AND column_name='is_uploader';
            """)
            
            if cursor.fetchone():
                print("✓ Column 'is_uploader' already exists")
                return
            
            # Add the column
            print("Adding 'is_uploader' column...")
            cursor.execute("""
                ALTER TABLE authentication_access_control_user 
                ADD COLUMN is_uploader BOOLEAN DEFAULT FALSE NOT NULL;
            """)
            
            print("✓ Column 'is_uploader' added successfully")
            
            # Record the migration
            cursor.execute("""
                INSERT INTO django_migrations (app, name, applied) 
                VALUES ('authentication_access_control', '0002_user_is_uploader', CURRENT_TIMESTAMP);
            """)
            
            print("✓ Migration recorded")
            
        except Exception as e:
            print(f"✗ Error: {e}")
            raise

if __name__ == '__main__':
    add_uploader_field()
    print("\n✓ Done! You can now restart the Django server.")
