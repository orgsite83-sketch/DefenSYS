"""
Test PDF file access and CORS configuration
"""

import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.conf import settings
from repository.vault.models import VaultEntry
from repository.deliverables.models import DeliverableSubmission
from student_teams.weekly_progress.models import WeeklyProgressReport

def test_pdf_access():
    """Test if PDF files are accessible"""
    
    print('Testing PDF File Access\n')
    print('=' * 80)
    
    # Check media root
    print(f'\n Media Root: {settings.MEDIA_ROOT}')
    print(f'Media URL: {settings.MEDIA_URL}')
    print(f'Media root exists: {os.path.exists(settings.MEDIA_ROOT)}')
    
    # Check vault entries
    print('\n' + '=' * 80)
    print('Digital Vault Entries:')
    print('=' * 80)
    
    vault_entries = VaultEntry.objects.all()[:5]
    for entry in vault_entries:
        file_path = os.path.join(settings.MEDIA_ROOT, entry.file.name) if entry.file else None
        file_exists = os.path.exists(file_path) if file_path else False
        
        print(f'\n   ID: {entry.id}')
        print(f'File: {entry.file.name if entry.file else "No file"}')
        print(f'URL: {entry.file.url if entry.file else "No URL"}')
        print(f'Path: {file_path}')
        print(f'Exists: {"" if file_exists else ""}')
        
        if file_exists:
            file_size = os.path.getsize(file_path)
            print(f'Size: {file_size:,} bytes ({file_size / 1024:.1f} KB)')
    
    # Check deliverable submissions
    print('\n' + '=' * 80)
    print('Deliverable Submissions:')
    print('=' * 80)
    
    deliverables = DeliverableSubmission.objects.all()[:5]
    for entry in deliverables:
        file_path = os.path.join(settings.MEDIA_ROOT, entry.file.name) if entry.file else None
        file_exists = os.path.exists(file_path) if file_path else False
        
        print(f'\n   ID: {entry.id}')
        print(f'File: {entry.file.name if entry.file else "No file"}')
        print(f'URL: {entry.file.url if entry.file else "No URL"}')
        print(f'Path: {file_path}')
        print(f'Exists: {"" if file_exists else ""}')
        
        if file_exists:
            file_size = os.path.getsize(file_path)
            print(f'Size: {file_size:,} bytes ({file_size / 1024:.1f} KB)')
    
    # Check weekly reports
    print('\n' + '=' * 80)
    print('Weekly Progress Reports:')
    print('=' * 80)
    
    reports = WeeklyProgressReport.objects.all()[:5]
    for entry in reports:
        file_path = os.path.join(settings.MEDIA_ROOT, entry.report_file.name) if entry.report_file else None
        file_exists = os.path.exists(file_path) if file_path else False
        
        print(f'\n   ID: {entry.id}')
        print(f'File: {entry.report_file.name if entry.report_file else "No file"}')
        print(f'URL: {entry.report_file.url if entry.report_file else "No URL"}')
        print(f'Path: {file_path}')
        print(f'Exists: {"" if file_exists else ""}')
        
        if file_exists:
            file_size = os.path.getsize(file_path)
            print(f'Size: {file_size:,} bytes ({file_size / 1024:.1f} KB)')
    
    # Test CORS configuration
    print('\n' + '=' * 80)
    print('CORS Configuration:')
    print('=' * 80)
    
    print(f'\n   DEBUG: {settings.DEBUG}')
    print(f'ALLOWED_HOSTS: {settings.ALLOWED_HOSTS}')
    
    # Test origins
    test_origins = [
        'http://localhost:8080',
        'http://127.0.0.1:8080',
        'http://192.168.1.100:8080',
        'http://10.60.121.199:8080',
        'http://10.0.0.1:8080',
    ]
    
    from defensys_backend.cors import _is_local_origin
    
    print('\n   Testing origins:')
    for origin in test_origins:
        allowed = _is_local_origin(origin)
        print(f'{origin}: {" Allowed" if allowed else " Blocked"}')
    
    print('\n' + '=' * 80)
    print('Test Complete')
    print('=' * 80)


if __name__ == '__main__':
    test_pdf_access()
