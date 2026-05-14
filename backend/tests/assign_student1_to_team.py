#!/usr/bin/env python
"""
Assign student1 to team 666 as a member
"""
import os
import django
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam, TeamMembership

def assign_student1():
    print("=== Assigning student1 to Team ===\n")
    
    # Get student1
    try:
        student1 = User.objects.get(username='student1')
        print(f"✓ Found student1: {student1.first_name} {student1.last_name}")
    except User.DoesNotExist:
        print("✗ student1 not found!")
        return
    
    # Get team 666
    try:
        team = StudentTeam.objects.get(name='666')
        print(f"✓ Found team: {team.name}")
        print(f"  Current leader: {team.leader.username}")
    except StudentTeam.DoesNotExist:
        print("✗ Team 666 not found!")
        return
    
    # Check if already a member
    existing = TeamMembership.objects.filter(team=team, student=student1).first()
    if existing:
        print(f"\n✓ student1 is already a member of {team.name}")
        return
    
    # Add student1 as a member
    try:
        membership = TeamMembership.objects.create(
            team=team,
            student=student1
        )
        print(f"\n✓ Successfully added student1 to team {team.name}")
        print(f"  Membership ID: {membership.id}")
        
        # Show updated team roster
        print(f"\n=== Updated Team Roster ===")
        print(f"Team: {team.name}")
        print(f"Leader: {team.leader.username}")
        print(f"Members:")
        for m in TeamMembership.objects.filter(team=team):
            is_leader = " (Leader)" if m.student == team.leader else ""
            print(f"  - {m.student.username}{is_leader}")
            
    except Exception as e:
        print(f"\n✗ Error adding student1 to team: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    assign_student1()
