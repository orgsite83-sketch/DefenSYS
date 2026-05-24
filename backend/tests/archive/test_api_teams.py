"""
Test what the defense scheduler API returns for teams
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from defense.scheduler.serializers import schedule_options_payload

print("\n" + "="*60)
print("DEFENSE SCHEDULER API - TEAMS DATA")
print("="*60)

payload = schedule_options_payload()

print(f"\nTotal teams in API response: {len(payload['teams'])}")
print("\nTeams data:")
print("="*60)

for team in payload['teams']:
    print(f"\nTeam: {team['name']}")
    print(f" ID: {team['id']}")
    print(f" Level: {team['level']}")
    print(f" ready_for_stage: {team.get('ready_for_stage', 'NOT IN RESPONSE')}")
    print(f" current_defense_stage: {team.get('current_defense_stage', 'NOT IN RESPONSE')}")
    print(f" status: {team['status']}")

print("\n" + "="*60)
print("SUMMARY")
print("="*60)

capstone_teams = [t for t in payload['teams'] if 'Capstone' in t.get('level', '')]
endorsed_teams = [t for t in capstone_teams if t.get('ready_for_stage')]

print(f"\nCapstone teams: {len(capstone_teams)}")
print(f"Endorsed teams: {len(endorsed_teams)}")

if endorsed_teams:
    print("\nEndorsed teams:")
    for team in endorsed_teams:
        print(f" - {team['name']}: {team['ready_for_stage']}")
else:
    print("\nWarning: No endorsed teams in API response!")

print("\n" + "="*60)
