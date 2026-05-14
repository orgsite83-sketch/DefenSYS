"""
Debug script to see exactly what the API returns
"""
import os, django, json
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.test import RequestFactory
from rest_framework.test import force_authenticate
from authentication_access_control.models import User
from digital_vault.views import DigitalVaultListView

# Get student user
student = User.objects.filter(username='student').first()
print(f'Testing API response for student: {student.username}')
print()

# Create request
factory = RequestFactory()
request = factory.get('/api/digital-vault/')
force_authenticate(request, user=student)

# Call view
view = DigitalVaultListView.as_view()
response = view(request)

print('='*80)
print('API RESPONSE')
print('='*80)
print(f'Status: {response.status_code}')
print()

if response.status_code == 200:
    data = response.data
    
    print(f'Response keys: {list(data.keys())}')
    print()
    
    entries = data.get('entries', [])
    print(f'Number of entries: {len(entries)}')
    print()
    
    if entries:
        print('ENTRIES DETAILS:')
        print('-'*80)
        for i, entry in enumerate(entries, 1):
            print(f'\nEntry #{i}:')
            print(f'  id: {entry.get("id")}')
            print(f'  file_name: {entry.get("file_name")}')
            print(f'  team_name: {entry.get("team_name")}')
            print(f'  team_id: {entry.get("team_id")}')
            print(f'  type: {entry.get("type")}')
            print(f'  deliverable_id: {entry.get("deliverable_id")}')
            print(f'  deliverable_label: {entry.get("deliverable_label")}')
            print(f'  stage: {entry.get("stage")}')
            print(f'  uploaded_by: {entry.get("uploaded_by")}')
            print(f'  status: {entry.get("status")}')
            print(f'  academic_year: {entry.get("academic_year")}')
        
        print()
        print('='*80)
        print('JSON FORMAT (what Flutter receives):')
        print('='*80)
        print(json.dumps(entries[0], indent=2))
    else:
        print('❌ NO ENTRIES RETURNED!')
        print()
        print('Checking why...')
        print(f'Counts: {data.get("counts")}')
        print(f'Filters: {data.get("filters")}')
else:
    print(f'❌ API ERROR: {response.status_code}')
    print(f'Response: {response.data}')
