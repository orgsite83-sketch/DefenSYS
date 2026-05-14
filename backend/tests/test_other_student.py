import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.test import RequestFactory
from rest_framework.test import force_authenticate
from authentication_access_control.models import User
from digital_vault.views import DigitalVaultListView

# Get a student NOT in team 666
student = User.objects.filter(role='student').exclude(student_teams__id=7).first()
if not student:
    print('No student found outside team 666')
    exit()

print(f'Testing with student: {student.username} ({student.first_name} {student.last_name})')
print(f'Student teams: {list(student.student_teams.values_list("name", flat=True))}')
print()

# Create request
factory = RequestFactory()
request = factory.get('/api/digital-vault/')
force_authenticate(request, user=student)

# Call view
view = DigitalVaultListView.as_view()
response = view(request)

print(f'Response status: {response.status_code}')
entries = response.data.get('entries', [])
print(f'Entries returned: {len(entries)}')
print()

if entries:
    print('Vault entries visible to this student (NOT in team 666):')
    for entry in entries:
        print(f'  - {entry["file_name"]}')
        print(f'    Team: {entry["team_name"]} (ID: {entry.get("team_id")})')
        print()
    print('✅ SUCCESS: Student from different team can see vault entries!')
else:
    print('❌ FAIL: No entries visible to student from different team')
