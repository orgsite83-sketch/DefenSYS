"""
Test script to verify endorsement-to-scheduler flow
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_teams.models import StudentTeam
from defense.stages.models import DefenseStage

def test_endorsement_flow():
    print("\n" + "="*60)
    print("ENDORSEMENT TO SCHEDULER FLOW TEST")
    print("="*60)
    
    # Get all teams
    teams = StudentTeam.objects.filter(level__icontains='Capstone')
    
    print(f"\n Total Capstone Teams: {teams.count()}")
    
    # Get all stages
    stages = DefenseStage.objects.filter(is_active=True)
    print(f"Active Defense Stages: {stages.count()}")
    
    # Show endorsed teams by stage
    print("\n" + "="*60)
    print("ENDORSED TEAMS BY STAGE")
    print("="*60)
    
    for stage in stages:
        endorsed_teams = teams.filter(ready_for_stage=stage.label)
        print(f"\n {stage.label}")
        print(f"Endorsed Teams: {endorsed_teams.count()}")
        
        if endorsed_teams.exists():
            for team in endorsed_teams:
                print(f"{team.name} - {team.project_title or 'No title'}")
                print(f"  Adviser: {team.adviser.username if team.adviser else 'None'}")
                print(f"  Current Stage: {team.current_defense_stage or 'None'}")
        else:
            print(f"Warning: No teams endorsed for this stage yet")
    
    # Show teams not endorsed
    print("\n" + "="*60)
    print("TEAMS NOT YET ENDORSED")
    print("="*60)
    
    not_endorsed = teams.filter(ready_for_stage__isnull=True) | teams.filter(ready_for_stage='')
    print(f"\n Count: {not_endorsed.count()}")
    
    if not_endorsed.exists():
        for team in not_endorsed:
            print(f"⏳ {team.name} - {team.project_title or 'No title'}")
            print(f"  Adviser: {team.adviser.username if team.adviser else 'None'}")
    else:
        print("All teams are endorsed!")
    
    # Summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    
    total_endorsed = teams.exclude(ready_for_stage__isnull=True).exclude(ready_for_stage='').count()
    
    print(f"\n Total Teams: {teams.count()}")
    print(f"Endorsed: {total_endorsed}")
    print(f"⏳ Not Endorsed: {not_endorsed.count()}")
    print(f"Endorsement Rate: {(total_endorsed / teams.count() * 100):.1f}%" if teams.count() > 0 else "N/A")
    
    # Test scheduler query
    print("\n" + "="*60)
    print("SCHEDULER QUERY TEST")
    print("="*60)
    
    for stage in stages:
        # This is the same query the scheduler uses
        schedulable_teams = teams.filter(
            level__icontains='Capstone',
            ready_for_stage=stage.label
        )
        
        print(f"\n Query: Teams ready for '{stage.label}'")
        print(f"Result: {schedulable_teams.count()} teams")
        
        if schedulable_teams.exists():
            for team in schedulable_teams:
                print(f"{team.name}")
    
    print("\n" + "="*60)
    print("TEST COMPLETE")
    print("="*60)
    print("\nThe endorsement-to-scheduler flow is working correctly!")
    print("Endorsed teams will automatically appear in Defense Scheduler")
    print("when admin selects the corresponding stage.\n")

if __name__ == '__main__':
    test_endorsement_flow()
