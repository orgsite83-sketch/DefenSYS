import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from capstone_deliverables.models import DeliverableSubmission
from django.conf import settings

print('='*80)
print('CHECKING ALL DELIVERABLE SUBMISSIONS')
print('='*80)
print()

# Check all deliverable submissions
all_subs = DeliverableSubmission.objects.all().order_by('-uploaded_at')
print(f'Total deliverable submissions: {all_subs.count()}')
print()

# Group by type
for dtype in ['vault', 'deliverable', 'pre', 'rubric']:
    count = DeliverableSubmission.objects.filter(deliverable_type=dtype).count()
    print(f'  {dtype}: {count}')
print()

print('='*80)
print('DETAILED SUBMISSION LIST')
print('='*80)
print()

for sub in all_subs:
    print(f'Submission ID: {sub.id}')
    print(f'  Type: {sub.deliverable_type}')
    print(f'  Team: {sub.team.name} (ID: {sub.team.id})')
    print(f'  Deliverable: {sub.deliverable_id} - {sub.label}')
    print(f'  Stage: {sub.stage_label}')
    print(f'  File name: {sub.file_name}')
    print(f'  File field: "{sub.file}"')
    print(f'  File URL: {sub.file_url}')
    
    # Check if file exists on disk
    if sub.file:
        file_path = sub.file.path
        exists = os.path.exists(file_path)
        print(f'  File path: {file_path}')
        print(f'  File exists on disk: {"✅ YES" if exists else "❌ NO"}')
        if exists:
            size = os.path.getsize(file_path)
            print(f'  File size: {size / 1024:.2f} KB')
    else:
        print(f'  ❌ No file attached (file field is empty)')
    
    print(f'  Uploaded by: {sub.uploaded_by}')
    print(f'  Uploaded at: {sub.uploaded_at}')
    print()

print('='*80)
print('SUMMARY BY TYPE')
print('='*80)
print()

for dtype in ['vault', 'deliverable', 'pre', 'rubric']:
    subs = DeliverableSubmission.objects.filter(deliverable_type=dtype)
    with_file = subs.filter(file__isnull=False).exclude(file='').count()
    without_file = subs.count() - with_file
    
    print(f'{dtype.upper()}:')
    print(f'  Total: {subs.count()}')
    print(f'  With file: {with_file}')
    print(f'  Without file: {without_file}')
    print()
