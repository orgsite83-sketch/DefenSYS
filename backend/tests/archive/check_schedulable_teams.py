import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_teams.models import StudentTeam
from defense.scheduler.models import DefenseSchedule

print("=" * 70)
print("CHECKING TEAMS ELIGIBLE FOR CONCEPT PROPOSAL SCHEDULING")
print("=" * 70)

stage = "Concept Proposal"
all_teams = StudentTeam.objects.filter(is_capstone=True)

print(f"\n Total Capstone Teams: {all_teams.count()}")

eligible_teams = []
for team in all_teams:
    print(f"\n{'='*70}")
    print(f"Team: {team.name} (ID: {team.id})")
    print(f" Current Stage: {team.current_defense_stage or 'None'}")
    print(f" Ready for Stage: {team.ready_for_stage or 'None'}")
    print(f" Type: {'Capstone' if team.is_capstone else 'PIT'}")
    
    # Check if already scheduled
    existing = DefenseSchedule.objects.filter(
        team=team,
        defense_stage__name=stage
    ).first()
    
    if existing:
        print(f"Already Scheduled: Yes (Schedule ID: {existing.id})")
    else:
        print(f"Already Scheduled: No")
    
    # Check eligibility
    is_eligible = (
        team.current_defense_stage == stage and
        not existing
    )
    
    if is_eligible:
        print(f"ELIGIBLE FOR SCHEDULING")
        eligible_teams.append(team)
    else:
        print(f"NOT ELIGIBLE")
        if team.current_defense_stage != stage:
            print(f" Reason: Wrong stage (need '{stage}', have '{team.current_defense_stage}')")
        if existing:
            print(f" Reason: Already scheduled")

print(f"\n{'='*70}")
print(f"\n SUMMARY:")
print(f"Total Teams: {all_teams.count()}")
print(f"Eligible for '{stage}': {len(eligible_teams)}")

if eligible_teams:
    print(f"\n Eligible Teams:")
    for team in eligible_teams:
        print(f"- {team.name} (ID: {team.id})")
else:
    print(f"\n No teams eligible for scheduling!")
    print(f"\nTo make teams eligible:")
    print(f"1. Set team's current_defense_stage to '{stage}'")
    print(f"2. Ensure team is not already scheduled for this stage")
    print(f"3. Team should be a Capstone team")

print(f"\n{'='*70}")
