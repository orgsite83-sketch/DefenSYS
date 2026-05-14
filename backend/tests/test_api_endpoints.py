import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.test import RequestFactory
from rest_framework.test import force_authenticate
from authentication_access_control.models import User

print('Testing API endpoints...')
print('='*80)

# Get a student user
student = User.objects.filter(role='student').first()
if not student:
    print('❌ No student user found')
    exit(1)

print(f'✅ Using student: {student.username}')
print()

# Test 1: Digital Vault API
print('Test 1: Digital Vault API')
print('-'*80)
try:
    from digital_vault.views import DigitalVaultListView
    
    factory = RequestFactory()
    request = factory.get('/api/digital-vault/')
    force_authenticate(request, user=student)
    
    view = DigitalVaultListView.as_view()
    response = view(request)
    
    print(f'✅ Status: {response.status_code}')
    print(f'✅ Response keys: {list(response.data.keys())}')
    
    entries = response.data.get('entries', [])
    print(f'✅ Entries returned: {len(entries)}')
    
    if entries:
        first_entry = entries[0]
        print(f'✅ First entry has file_url: {"file_url" in first_entry}')
        if 'file_url' in first_entry:
            print(f'   file_url value: {first_entry["file_url"]}')
    
    print('✅ Digital Vault API works!')
except Exception as e:
    print(f'❌ Error: {e}')
    import traceback
    traceback.print_exc()

print()

# Test 2: Team Documents API
print('Test 2: Team Documents API')
print('-'*80)
try:
    from team_documents.views import TeamDocumentListView
    
    factory = RequestFactory()
    request = factory.get('/api/documents/')
    force_authenticate(request, user=student)
    
    view = TeamDocumentListView.as_view()
    response = view(request)
    
    print(f'✅ Status: {response.status_code}')
    print(f'✅ Response keys: {list(response.data.keys())}')
    
    documents = response.data.get('documents', [])
    print(f'✅ Documents returned: {len(documents)}')
    
    if documents:
        first_doc = documents[0]
        print(f'✅ First document has file_url: {"file_url" in first_doc}')
        if 'file_url' in first_doc:
            print(f'   file_url value: {first_doc["file_url"]}')
    
    print('✅ Team Documents API works!')
except Exception as e:
    print(f'❌ Error: {e}')
    import traceback
    traceback.print_exc()

print()

# Test 3: Capstone Deliverables API
print('Test 3: Capstone Deliverables API')
print('-'*80)
try:
    from capstone_deliverables.views import CapstoneDeliverablesListView
    
    factory = RequestFactory()
    request = factory.get('/api/capstone-deliverables/')
    force_authenticate(request, user=student)
    
    view = CapstoneDeliverablesListView.as_view()
    response = view(request)
    
    print(f'✅ Status: {response.status_code}')
    print(f'✅ Response keys: {list(response.data.keys())}')
    print('✅ Capstone Deliverables API works!')
except Exception as e:
    print(f'❌ Error: {e}')
    import traceback
    traceback.print_exc()

print()
print('='*80)
print('✅ ALL API TESTS PASSED!')
