import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_teams.models import StudentTeam
from repository.deliverables.models import DeliverableSubmission

# Check team 666
team = StudentTeam.objects.get(id=7)
print(f'Team: {team.name}')
print(f'Level: {team.level}')
print(f'Leader: {team.leader.username} ({team.leader.first_name})')
print(f'Adviser: {team.adviser.username if team.adviser else "None"}')
print()

# Check vault submissions for this team
vault_subs = DeliverableSubmission.objects.filter(
    team=team,
    deliverable_type='vault'
)

print(f'Vault submissions for team {team.name}: {vault_subs.count()}')
for sub in vault_subs:
    print(f'- {sub.deliverable_id}: {sub.label}')
    print(f'File: {sub.file_name}')
    print(f'Stage: {sub.stage_label}')
    print(f'Uploaded by: {sub.uploaded_by.username if sub.uploaded_by else "None"}')
    print(f'Type: {sub.deliverable_type}')
    print()

# Check what the API would return
from repository.vault.services import capstone_visible_queryset, CAPSTONE_VISIBLE_IDS

print(f'Visible deliverable IDs: {CAPSTONE_VISIBLE_IDS}')
print()

visible_subs = capstone_visible_queryset().filter(team=team)
print(f'Visible vault submissions for team {team.name}: {visible_subs.count()}')
for sub in visible_subs:
    print(f'- {sub.deliverable_id}: {sub.label}')
    print(f'In visible list: {sub.deliverable_id in CAPSTONE_VISIBLE_IDS}')
