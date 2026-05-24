"""
Fix mismatched team_id values for students
This ensures User.team_id matches their actual team membership
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.contrib.auth import get_user_model
from student_teams.models import StudentTeam, TeamMembership

User = get_user_model()

def fix_team_ids():
    print("\n=== Fixing Team ID Mismatches ===\n")
    
    fixed_count = 0
    cleared_count = 0
    
    # Fix students who are in teams
    teams = StudentTeam.objects.all().prefetch_related('memberships', 'memberships__student')
    
    for team in teams:
        memberships = team.memberships.all()
        member_ids = [m.student_id for m in memberships]
        
        # Update all members to have correct team_id
        updated = User.objects.filter(pk__in=member_ids).exclude(team_id=str(team.id)).update(team_id=str(team.id))
        
        if updated > 0:
            print(f"Fixed {updated} members in Team {team.id} ({team.name})")
            fixed_count += updated
    
    # Clear team_id for students not in any team
    students_no_membership = User.objects.filter(role='student').exclude(team_memberships__isnull=False).exclude(team_id__isnull=True)
    
    for student in students_no_membership:
        if student.team_id:
            print(f" Clearing team_id for {student.username} (was: {student.team_id})")
            student.team_id = None
            student.save()
            cleared_count += 1
    
    print(f"\n=== Summary ===")
    print(f"Fixed: {fixed_count} students")
    print(f"Cleared: {cleared_count} students")
    print(f"\nAll team_id values are now synchronized!\n")

if __name__ == '__main__':
    fix_team_ids()
