import os, django, json
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from digital_vault.services import digital_vault_payload

class MockRequest:
    def __init__(self, user):
        self.user = user
        self.query_params = {}

# Get student user
student = User.objects.filter(username='student').first()
print(f'Testing with student: {student.username}')
print()

# Get payload
request = MockRequest(student)
payload = digital_vault_payload(request)

print(f'Entries returned: {len(payload["entries"])}')
print(f'Counts: {payload["counts"]}')
print()

if payload['entries']:
    print('Entries:')
    for entry in payload['entries']:
        print(f'  - {entry["file_name"]}')
        print(f'    ID: {entry["id"]}')
        print(f'    Team: {entry["team_name"]} (ID: {entry.get("team_id")})')
        print(f'    Type: {entry["type"]}')
        print(f'    Deliverable: {entry.get("deliverable_id")}')
        print()
else:
    print('No entries returned!')
    print()
    print('Debugging info:')
    print(f'Student role: {student.role}')
    print(f'Student authenticated: {student.is_authenticated}')
