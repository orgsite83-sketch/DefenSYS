import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from capstone_deliverables.models import DeliverableSubmission
from digital_vault.models import VaultEntry

print('='*80)
print('VAULT DATABASE DETAILS')
print('='*80)
print()

# Check vault submissions
vault_subs = DeliverableSubmission.objects.filter(deliverable_type='vault')
print(f'Total vault submissions: {vault_subs.count()}')
print()

for sub in vault_subs:
    print(f'Submission ID: {sub.id}')
    print(f'  Team: {sub.team.name} (ID: {sub.team.id})')
    print(f'  Deliverable: {sub.deliverable_id} - {sub.label}')
    print(f'  File name: {sub.file_name}')
    print(f'  File field: "{sub.file}"')
    print(f'  File field bool: {bool(sub.file)}')
    print(f'  Uploaded by: {sub.uploaded_by}')
    print(f'  Uploaded at: {sub.uploaded_at}')
    print()

# Check if there are any other deliverable submissions
all_subs = DeliverableSubmission.objects.all()
print(f'Total deliverable submissions (all types): {all_subs.count()}')
print()

# Show breakdown by type
for dtype in ['vault', 'deliverable', 'rubric']:
    count = DeliverableSubmission.objects.filter(deliverable_type=dtype).count()
    print(f'  {dtype}: {count}')
print()

# Check PIT vault entries
pit_entries = VaultEntry.objects.all()
print(f'Total PIT vault entries: {pit_entries.count()}')
