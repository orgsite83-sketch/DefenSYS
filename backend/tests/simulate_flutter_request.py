"""
Simulate exactly what the Flutter app does
"""
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from rest_framework.authtoken.models import Token
from rest_framework_simplejwt.tokens import RefreshToken

# Get student
student = User.objects.filter(username='student').first()
print(f'Student: {student.username}')
print()

# Generate JWT token (like login does)
refresh = RefreshToken.for_user(student)
access_token = str(refresh.access_token)

print(f'JWT Access Token: {access_token[:50]}...')
print(f'Token length: {len(access_token)} chars')
print()

# Now simulate the HTTP request
import requests

url = 'http://10.60.121.199:8000/api/digital-vault/'
headers = {
    'Content-Type': 'application/json',
    'Authorization': f'Bearer {access_token}'
}

print(f'Making request to: {url}')
print(f'Headers: {headers}')
print()

try:
    response = requests.get(url, headers=headers, timeout=8)
    print(f'Response status: {response.status_code}')
    print()
    
    if response.status_code == 200:
        data = response.json()
        entries = data.get('entries', [])
        
        print(f'✅ SUCCESS!')
        print(f'Entries returned: {len(entries)}')
        print()
        
        if entries:
            print('Entries:')
            for entry in entries:
                print(f'  - {entry["file_name"]}')
                print(f'    Type: {entry["type"]}')
                print(f'    Team: {entry["team_name"]}')
                print(f'    Deliverable: {entry.get("deliverable_id")}')
                print()
        else:
            print('❌ No entries in response')
    else:
        print(f'❌ ERROR: {response.status_code}')
        print(f'Response: {response.text[:500]}')
        
except requests.exceptions.ConnectionError:
    print('❌ CONNECTION ERROR: Cannot connect to server')
    print('Make sure Django server is running on http://10.60.121.199:8000')
except Exception as e:
    print(f'❌ ERROR: {e}')
