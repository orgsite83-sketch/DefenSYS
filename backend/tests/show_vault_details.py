import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from capstone_deliverables.models import DeliverableSubmission

print('='*80)
print('VAULT ENTRIES IN YOUR DATABASE')
print('='*80)
print()

vault_submissions = DeliverableSubmission.objects.filter(deliverable_type='vault').order_by('created_at')

for i, sub in enumerate(vault_submissions, 1):
    print(f'VAULT ENTRY #{i}')
    print('-'*80)
    print(f'📄 File Name: {sub.file_name}')
    print(f'📋 Deliverable: {sub.deliverable_id} - {sub.label}')
    print(f'🏷️  Stage: {sub.stage_label}')
    print(f'👥 Team: {sub.team.name}')
    print(f'👤 Uploaded by: {sub.uploaded_by.username if sub.uploaded_by else "Unknown"} ({sub.uploaded_by.role if sub.uploaded_by else "N/A"})')
    print(f'📦 File Size: {sub.file_size}')
    print(f'📅 Uploaded: {sub.uploaded_at.strftime("%Y-%m-%d %H:%M:%S")}')
    print(f'🔢 Database ID: {sub.id}')
    print()

print('='*80)
print('WHERE THESE CAME FROM')
print('='*80)
print()
print('These are the files you uploaded in the web interface at:')
print('Capstone Deliverables > Team 666 > Post-Defense Vault Submissions')
print()
print('When you clicked "Replace" and uploaded files for:')
print('  1. D4.1 - Approved Concept Paper (in Concept Proposal stage)')
print('  2. D10 - Chapters 1-3 Complete (in Project Proposal stage)')
print()
print('These uploads were saved with deliverable_type="vault"')
print('which means they should appear in the Digital Vault for students.')
print()
