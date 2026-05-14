import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from team_documents.models import TeamDocument

print("=" * 60)
print("CHECKING TEAM DOCUMENTS IN DATABASE")
print("=" * 60)

documents = TeamDocument.objects.all()
count = documents.count()

print(f"\n📊 Total documents in database: {count}")

if count > 0:
    print("\n📄 Documents:")
    for doc in documents:
        print(f"\n  ID: {doc.id}")
        print(f"  File: {doc.file_name}")
        print(f"  Team: {doc.team.name if doc.team else 'No team'}")
        print(f"  Uploaded by: {doc.uploaded_by.username if doc.uploaded_by else 'Unknown'}")
        print(f"  Type: {doc.document_type}")
        print(f"  Size: {doc.file_size_mb} MB")
        print(f"  Uploaded: {doc.uploaded_at}")
else:
    print("\n❌ No documents found in database!")
    print("\nTo upload documents:")
    print("1. Log in as an uploader user")
    print("2. Go to the uploader dashboard")
    print("3. Click 'Upload Document' button")
    print("4. Select a team and file to upload")

print("\n" + "=" * 60)
