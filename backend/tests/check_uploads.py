#!/usr/bin/env python
"""
Check uploaded documents in database
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from team_documents.models import TeamDocument
from django.db import connection

print("=" * 60)
print("UPLOADED DOCUMENTS CHECK")
print("=" * 60)

# Check if table exists
with connection.cursor() as cursor:
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'team_documents_teamdocument'
        );
    """)
    table_exists = cursor.fetchone()[0]
    
if not table_exists:
    print("\n❌ Table 'team_documents_teamdocument' does not exist!")
    print("   Run: python manage.py migrate team_documents")
else:
    print("\n✅ Table 'team_documents_teamdocument' exists")

# Check documents
documents = TeamDocument.objects.all()
print(f"\n📊 Total documents in database: {documents.count()}")

if documents.exists():
    print("\n📄 Uploaded Documents:")
    print("-" * 60)
    for doc in documents:
        print(f"\nDocument ID: {doc.id}")
        print(f"  File Name: {doc.file_name}")
        print(f"  Team: {doc.team.name} (ID: {doc.team_id})")
        print(f"  Document Type: {doc.get_document_type_display()}")
        print(f"  File Size: {doc.file_size_mb} MB ({doc.file_size:,} bytes)")
        print(f"  MIME Type: {doc.mime_type}")
        print(f"  Uploaded By: {doc.uploaded_by.username if doc.uploaded_by else 'Unknown'}")
        print(f"  Uploaded At: {doc.uploaded_at}")
        print(f"  Description: {doc.description or '(none)'}")
        print(f"  ✅ File Data Stored: {len(doc.file_data):,} bytes in database")
        print("-" * 60)
else:
    print("\nℹ️  No documents uploaded yet")
    print("\nTo test upload:")
    print("1. Login as uploader (username: 1017)")
    print("2. Click 'Upload Document' button")
    print("3. Select a file and team")
    print("4. Upload the document")
    print("5. Run this script again to verify")

# Check database storage
print("\n💾 Storage Information:")
print(f"   Database: PostgreSQL (defensys_db)")
print(f"   Table: team_documents_teamdocument")
print(f"   File Storage: Binary data in 'file_data' column (BYTEA)")
print(f"   Max File Size: 10 MB (enforced by serializer)")

# Calculate total storage used
if documents.exists():
    total_bytes = sum(doc.file_size for doc in documents)
    total_mb = total_bytes / (1024 * 1024)
    print(f"   Total Storage Used: {total_mb:.2f} MB ({total_bytes:,} bytes)")

print("\n" + "=" * 60)
