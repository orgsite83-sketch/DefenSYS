"""
Test the digital vault API with authentication
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.test import RequestFactory
from rest_framework.test import force_authenticate
from authentication_access_control.models import User
from digital_vault.views import DigitalVaultListView

# Create a request factory
factory = RequestFactory()

# Get student user
student = User.objects.filter(username='student').first()
print(f'Testing with student: {student.username} ({student.first_name} {student.last_name})')
print(f'Student role: {student.role}')
print()

# Create a GET request
request = factory.get('/api/digital-vault/')

# Authenticate the request
force_authenticate(request, user=student)

# Call the view
view = DigitalVaultListView.as_view()
response = view(request)

print(f'Response status: {response.status_code}')
print(f'Response data keys: {response.data.keys()}')
print()

entries = response.data.get('entries', [])
print(f'Entries returned: {len(entries)}')
print(f'Counts: {response.data.get("counts")}')
print()

if entries:
    print('Vault entries visible to student:')
    for entry in entries:
        print(f'  - {entry["file_name"]}')
        print(f'    Team: {entry["team_name"]} (ID: {entry.get("team_id")})')
        print(f'    Deliverable: {entry.get("deliverable_id")} - {entry.get("deliverable_label")}')
        print(f'    Stage: {entry.get("stage")}')
        print(f'    Type: {entry.get("type")}')
        print()
else:
    print('❌ No entries returned!')
    print()
    print('Debugging:')
    print(f'  - Student teams: {list(student.student_teams.values_list("name", flat=True))}')
    print(f'  - Response data: {response.data}')
