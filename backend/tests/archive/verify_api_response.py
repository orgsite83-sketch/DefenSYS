"""
Verify API response format for Defense Scheduler
This script simulates what the frontend receives from the API
"""
import os
import django
import json

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_teams.models import StudentTeam
from defense.stages.models import DefenseStage

def verify_api_response():
    print("\n" + "="*60)
    print("API RESPONSE FORMAT VERIFICATION")
    print("="*60)
    
    # Simulate the API call
    print("\n Simulating GET /api/defense-schedules/")
    
    # Get data like the view does
    teams = StudentTeam.objects.filter(level__icontains='Capstone')
    stages = DefenseStage.objects.filter(is_active=True)
    
    # Serialize teams (simplified)
    teams_data = []
    for team in teams:
        teams_data.append({
            'id': team.id,
            'name': team.name,
            'level': team.level,
            'project_title': team.project_title,
            'ready_for_stage': team.ready_for_stage,
            'current_defense_stage': team.current_defense_stage,
        })
    
    print("\n Response payload:")
    print(json.dumps({
        'teams': teams_data,
        'team_count': len(teams_data),
    }, indent=2))
    
    print("\n" + "="*60)
    print("FRONTEND SHOULD RECEIVE")
    print("="*60)
    
    print("\n Teams array with 'ready_for_stage' field:")
    for team_data in teams_data:
        print(f"\n   Team: {team_data['name']}")
        print(f"- id: {team_data['id']}")
        print(f"- level: {team_data['level']}")
        print(f"- ready_for_stage: '{team_data['ready_for_stage']}'")
        print(f"- current_defense_stage: '{team_data['current_defense_stage']}'")
    
    print("\n" + "="*60)
    print("MATCHING LOGIC TEST")
    print("="*60)
    
    for stage in stages:
        print(f"\n Stage: {stage.label}")
        matching_teams = [
            t for t in teams_data 
            if t['ready_for_stage'] == stage.label
        ]
        print(f"Matching teams: {len(matching_teams)}")
        for team in matching_teams:
            print(f"{team['name']}")
    
    print("\n" + "="*60)
    print("FRONTEND DEBUG OUTPUT SHOULD SHOW")
    print("="*60)
    
    print("\nWhen 'Concept Proposal' is selected:")
    print("Team: 111 | Level: Capstone | Ready for: Concept Proposal | Match: true")
    print("Team: 666 | Level: Capstone | Ready for: Concept Proposal | Match: true")
    print("Team: Alpha Team | Level: Capstone | Ready for:  | Match: false")
    print("Stage: Concept Proposal | Ready Teams: 2/3")
    
    print("\nWhen 'Project Proposal' is selected:")
    print("Team: 111 | Level: Capstone | Ready for: Concept Proposal | Match: false")
    print("Team: 666 | Level: Capstone | Ready for: Concept Proposal | Match: false")
    print("Team: Alpha Team | Level: Capstone | Ready for:  | Match: false")
    print("Stage: Project Proposal | Ready Teams: 0/3")
    
    print("\n" + "="*60)
    print("VERIFICATION COMPLETE")
    print("="*60)
    print("\nIf frontend still shows 0:")
    print("1. Check browser console for debug messages")
    print("2. Verify teams are loaded in state (state.teams.length)")
    print("3. Check Network tab for API response")
    print("4. Hard refresh browser (Ctrl+Shift+R)")
    print("5. Restart Flutter frontend completely\n")

if __name__ == '__main__':
    verify_api_response()
