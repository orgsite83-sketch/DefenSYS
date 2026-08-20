"""
Simulate exactly what the Flutter app does
"""
import os
import sys
from pathlib import Path
import django

# Add backend and modules directory to sys.path
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(BASE_DIR))
sys.path.insert(0, str(BASE_DIR / 'modules'))

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from rest_framework_simplejwt.tokens import RefreshToken
import requests

# Get student or fallback user
student = (
    User.objects.filter(username='student').first()
    or User.objects.filter(role='student').first()
    or User.objects.filter(username='admin').first()
    or User.objects.first()
)

if not student:
    print('ERROR: No users found in database.')
    sys.exit(1)

print(f'User: {student.username} (Role: {student.role})')
print()

# Generate JWT token (like login does)
refresh = RefreshToken.for_user(student)
access_token = str(refresh.access_token)

print(f'JWT Access Token: {access_token[:50]}...')
print(f'Token length: {len(access_token)} chars')
print()

# Target URL (defaults to localhost:8000)
base_url = os.environ.get('DEFENSYS_BACKEND_URL', 'http://127.0.0.1:8000')
url = f'{base_url}/api/repository/archive/'
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
        entries = data.get('entries', []) if isinstance(data, dict) else data
        
        print('SUCCESS!')
        print(f'Entries returned: {len(entries)}')
        print()
        
        if entries:
            print('Entries:')
            for entry in entries:
                if isinstance(entry, dict):
                    print(f'- {entry.get("file_name", entry.get("title", "Unnamed"))}')
                    print(f'  Type: {entry.get("type", "N/A")}')
                    print(f'  Team: {entry.get("team_name", "N/A")}')
                    print(f'  Deliverable: {entry.get("deliverable_id", "N/A")}')
                    print()
                else:
                    print(f'- {entry}')
        else:
            print('No entries in response')
    else:
        print(f'ERROR: {response.status_code}')
        print(f'Response: {response.text[:500]}')
        
except requests.exceptions.ConnectionError:
    print('CONNECTION ERROR: Cannot connect to server')
    print(f'Make sure Django server is running on {base_url}')
except Exception as e:
    print(f'ERROR: {e}')
