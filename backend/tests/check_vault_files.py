import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from capstone_deliverables.models import DeliverableSubmission
from digital_vault.models import VaultEntry
from django.conf import settings

print('='*80)
print('CHECKING VAULT FILES')
print('='*80)
print()

# Check 1: Capstone Vault Submissions
print('1. CAPSTONE VAULT SUBMISSIONS (DeliverableSubmission)')
print('-'*80)

vault_subs = DeliverableSubmission.objects.filter(deliverable_type='vault')
print(f'Total vault submissions in database: {vault_subs.count()}')
print()

if vault_subs.exists():
    for sub in vault_subs:
        print(f'Submission ID: {sub.id}')
        print(f'  Team: {sub.team.name}')
        print(f'  Deliverable: {sub.deliverable_id} - {sub.label}')
        print(f'  Stage: {sub.stage_label}')
        print(f'  File name: {sub.file_name}')
        print(f'  File field: {sub.file}')
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
        print()
else:
    print('❌ No vault submissions found')
    print()

# Check 2: PIT Vault Entries
print('2. PIT VAULT ENTRIES (VaultEntry)')
print('-'*80)

vault_entries = VaultEntry.objects.all()
print(f'Total vault entries in database: {vault_entries.count()}')
print()

if vault_entries.exists():
    for entry in vault_entries:
        print(f'Entry ID: {entry.id}')
        print(f'  Type: {entry.entry_type}')
        print(f'  File name: {entry.file_name}')
        print(f'  File field: {entry.file}')
        print(f'  File URL: {entry.file_url}')
        
        # Check if file exists on disk
        if entry.file:
            file_path = entry.file.path
            exists = os.path.exists(file_path)
            print(f'  File path: {file_path}')
            print(f'  File exists on disk: {"✅ YES" if exists else "❌ NO"}')
            if exists:
                size = os.path.getsize(file_path)
                print(f'  File size: {size / 1024:.2f} KB')
        else:
            print(f'  ❌ No file attached (file field is empty)')
        print()
else:
    print('ℹ️  No PIT vault entries found')
    print()

# Check 3: Media folder structure
print('3. MEDIA FOLDER STRUCTURE')
print('-'*80)

media_root = settings.MEDIA_ROOT
print(f'Media root: {media_root}')
print()

# Check deliverables folder
deliverables_path = os.path.join(media_root, 'deliverables')
if os.path.exists(deliverables_path):
    print(f'✅ Deliverables folder exists: {deliverables_path}')
    # List files
    for root, dirs, files in os.walk(deliverables_path):
        level = root.replace(deliverables_path, '').count(os.sep)
        indent = ' ' * 2 * level
        print(f'{indent}{os.path.basename(root)}/')
        subindent = ' ' * 2 * (level + 1)
        for file in files:
            file_path = os.path.join(root, file)
            size = os.path.getsize(file_path)
            print(f'{subindent}{file} ({size / 1024:.2f} KB)')
else:
    print(f'❌ Deliverables folder does not exist: {deliverables_path}')

print()

# Check vault_entries folder
vault_path = os.path.join(media_root, 'vault_entries')
if os.path.exists(vault_path):
    print(f'✅ Vault entries folder exists: {vault_path}')
    # List files
    for root, dirs, files in os.walk(vault_path):
        level = root.replace(vault_path, '').count(os.sep)
        indent = ' ' * 2 * level
        print(f'{indent}{os.path.basename(root)}/')
        subindent = ' ' * 2 * (level + 1)
        for file in files:
            file_path = os.path.join(root, file)
            size = os.path.getsize(file_path)
            print(f'{subindent}{file} ({size / 1024:.2f} KB)')
else:
    print(f'ℹ️  Vault entries folder does not exist: {vault_path}')

print()

# Check sample PDF
sample_pdf = os.path.join(media_root, 'Poster_CodeLearners_MaketLink.pdf')
if os.path.exists(sample_pdf):
    size = os.path.getsize(sample_pdf)
    print(f'✅ Sample PDF exists: {sample_pdf}')
    print(f'   Size: {size / 1024:.2f} KB')
else:
    print(f'ℹ️  Sample PDF not found: {sample_pdf}')

print()
print('='*80)
print('SUMMARY')
print('='*80)
print(f'Capstone vault submissions: {vault_subs.count()}')
print(f'PIT vault entries: {vault_entries.count()}')
print(f'Total vault records: {vault_subs.count() + vault_entries.count()}')
print()

# Count files with actual file field populated
files_with_file = vault_subs.filter(file__isnull=False).count()
entries_with_file = vault_entries.filter(file__isnull=False).count()
print(f'Records with file field populated: {files_with_file + entries_with_file}')
print(f'Records without file field: {(vault_subs.count() + vault_entries.count()) - (files_with_file + entries_with_file)}')
