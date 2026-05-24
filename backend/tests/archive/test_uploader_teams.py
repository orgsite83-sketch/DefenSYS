#!/usr/bin/env python
"""
Test uploader access to teams endpoint
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.test import RequestFactory
from rest_framework.test import force_authenticate
from authentication_access_control.models import User
from student_teams.views import StudentTeamListCreateView
from student_teams.models import StudentTeam

print("=" * 60)
print("UPLOADER TEAMS ACCESS TEST")
print("=" * 60)

# Get uploader user
try:
    uploader = User.objects.get(username='1017')
    print(f"\n Found uploader: {uploader.username}")
    print(f"Name: {uploader.first_name} {uploader.last_name}")
    print(f"Is Uploader: {uploader.is_uploader}")
    print(f"Is Authenticated: {uploader.is_authenticated}")
except User.DoesNotExist:
    print("\n Uploader user '1017' not found!")
    exit(1)

# Check teams in database
teams = StudentTeam.objects.all()
print(f"\n Teams in database: {teams.count()}")
for team in teams:
    print(f"- {team.id}: {team.name} ({team.level})")

# Test API access
print("\n Testing API access...")
factory = RequestFactory()
request = factory.get('/api/teams/')
force_authenticate(request, user=uploader)

view = StudentTeamListCreateView.as_view()
try:
    response = view(request)
    print(f"GET /api/teams/ - Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.data
        teams_data = data.get('teams', [])
        print(f"Response contains {len(teams_data)} teams")
        for team in teams_data[:5]:
            print(f"- {team['id']}: {team['name']} ({team['level']})")
    else:
        print(f"Unexpected status code: {response.status_code}")
        print(f"Response: {response.data}")
        
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

# Test POST (should fail)
print("\n Testing POST access (should be forbidden)...")
request = factory.post('/api/teams/', {})
force_authenticate(request, user=uploader)

try:
    response = view(request)
    if response.status_code == 403:
        print(f"POST /api/teams/ - Status: 403 (correctly forbidden)")
    else:
        print(f"Warning: POST /api/teams/ - Status: {response.status_code} (expected 403)")
except Exception as e:
    print(f"Error: {e}")

print("\n" + "=" * 60)
