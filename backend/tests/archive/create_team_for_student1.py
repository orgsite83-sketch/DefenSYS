#!/usr/bin/env python
"""
Create a new team with student1 as the leader
"""
import os
import django
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam, TeamMembership
from academic_period_management.models import Semester

def create_team_for_student1():
    print("=== Creating Team for student1 ===\n")
    
    # Get student1
    try:
        student1 = User.objects.get(username='student1')
        print(f"Found student1: {student1.first_name} {student1.last_name}")
    except User.DoesNotExist:
        print("student1 not found!")
        return
    
    # Get a semester
    semester = Semester.objects.first()
    if not semester:
        print("No semester found! Please create a semester first.")
        return
    print(f"Using semester: {semester}")
    
    # Remove student1 from any existing teams
    existing_memberships = TeamMembership.objects.filter(student=student1)
    if existing_memberships.exists():
        print(f"\n  Removing student1 from existing teams...")
        for membership in existing_memberships:
            print(f"- Removed from {membership.team.name}")
            membership.delete()
    
    # Create new team
    try:
        team = StudentTeam.objects.create(
            name='Alpha Team',
            level=StudentTeam.LEVEL_4_CAPSTONE,  # Use valid choice
            year_level='4th Year',
            semester=semester,
            status=StudentTeam.STATUS_APPROVED,  # Use valid choice
            project_title='Student1 Capstone Project',
            leader=student1
        )
        print(f"\n Created new team: {team.name} (ID: {team.id})")
        print(f" Leader: {team.leader.username}")
        print(f" Project: {team.project_title}")
        
        # Add student1 as a member
        membership = TeamMembership.objects.create(
            team=team,
            student=student1
        )
        print(f"\n Added student1 as team member")
        
        # Optionally add other students without teams
        print(f"\n=== Adding other available students ===")
        available_students = User.objects.filter(
            role='student'
        ).exclude(
            id__in=TeamMembership.objects.values_list('student_id', flat=True)
        ).exclude(
            id=student1.id
        )[:3]  # Add up to 3 more students
        
        for student in available_students:
            TeamMembership.objects.create(team=team, student=student)
            print(f" + Added {student.username}")
        
        # Show final team roster
        print(f"\n=== Final Team Roster ===")
        print(f"Team: {team.name}")
        print(f"Leader: {team.leader.username} ⭐")
        print(f"Members:")
        for m in TeamMembership.objects.filter(team=team):
            is_leader = " ⭐ (Leader - Can Submit Reports)" if m.student == team.leader else ""
            print(f" - {m.student.username}{is_leader}")
        
        print(f"\n SUCCESS! student1 can now submit weekly progress reports!")
            
    except Exception as e:
        print(f"\n Error creating team: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    create_team_for_student1()
