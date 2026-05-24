import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from repository.deliverables.models import DeliverableSubmission

print('='*80)
print('DELETING OLD VAULT RECORDS')
print('='*80)
print()

# Get vault submissions
vault_subs = DeliverableSubmission.objects.filter(deliverable_type='vault')
print(f'Found {vault_subs.count()} vault submissions to delete')
print()

if vault_subs.exists():
    for sub in vault_subs:
        print(f'Deleting Submission ID: {sub.id}')
        print(f'Team: {sub.team.name}')
        print(f'Deliverable: {sub.deliverable_id} - {sub.label}')
        print(f'File name: {sub.file_name}')
        print(f'Uploaded by: {sub.uploaded_by}')
        print(f'Uploaded at: {sub.uploaded_at}')
        
        # Delete the submission
        sub.delete()
        print(f'Deleted')
        print()
else:
    print('No vault submissions found to delete')
    print()

# Verify deletion
remaining = DeliverableSubmission.objects.filter(deliverable_type='vault').count()
print('='*80)
print('DELETION COMPLETE')
print('='*80)
print(f'Remaining vault submissions: {remaining}')
print()

if remaining == 0:
    print('All old vault records have been successfully deleted!')
    print()
    print('NEXT STEPS:')
    print('1. Log in to the web interface as the adviser (postgres)')
    print('2. Navigate to Capstone Deliverables Management')
    print('3. Select Team 666')
    print('4. Upload vault submissions with actual PDF files')
    print('5. The new uploads will properly save files to the FileField')
    print('6. Students will then be able to view the PDFs in their Digital Vault')
else:
    print(f'Warning: Warning: {remaining} vault submissions still remain')
