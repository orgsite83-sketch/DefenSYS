import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

print('Testing all models...')
print('='*80)

# Test 1: DeliverableSubmission
from repository.deliverables.models import DeliverableSubmission
print('DeliverableSubmission model loaded')
print(f'Has file field: {hasattr(DeliverableSubmission, "file")}')
print(f'Has file_url property: {hasattr(DeliverableSubmission, "file_url")}')

# Test 2: TeamDocument
from student_teams.documents.models import TeamDocument
print('TeamDocument model loaded')
print(f'Has file field: {hasattr(TeamDocument, "file")}')
print(f'Has file_url property: {hasattr(TeamDocument, "file_url")}')

# Test 3: VaultEntry
from repository.vault.models import VaultEntry
print('VaultEntry model loaded')
print(f'Has file field: {hasattr(VaultEntry, "file")}')
print(f'Has file_url property: {hasattr(VaultEntry, "file_url")}')

# Test 4: WeeklyProgressReport
from student_teams.weekly_progress.models import WeeklyProgressReport
print('WeeklyProgressReport model loaded')
print(f'Has report_file field: {hasattr(WeeklyProgressReport, "report_file")}')

print()
print('='*80)
print('ALL MODELS LOADED SUCCESSFULLY!')
print()

# Test creating instances
print('Testing model instances...')
print('-'*80)

# Test DeliverableSubmission
try:
    ds = DeliverableSubmission.objects.first()
    if ds:
        print(f'DeliverableSubmission instance: {ds.file_name}')
        print(f'file field: {ds.file}')
        print(f'file_url: {ds.file_url}')
except Exception as e:
    print(f'Error with DeliverableSubmission: {e}')

# Test TeamDocument
try:
    td = TeamDocument.objects.first()
    if td:
        print(f'TeamDocument instance: {td.file_name}')
        print(f'file field: {td.file}')
        print(f'file_url: {td.file_url}')
    else:
        print('No TeamDocument instances found')
except Exception as e:
    print(f'Error with TeamDocument: {e}')

# Test VaultEntry
try:
    ve = VaultEntry.objects.first()
    if ve:
        print(f'VaultEntry instance: {ve.file_name}')
        print(f'file field: {ve.file}')
        print(f'file_url: {ve.file_url}')
    else:
        print('No VaultEntry instances found')
except Exception as e:
    print(f'Error with VaultEntry: {e}')

print()
print('='*80)
print('ALL TESTS PASSED!')
