#!/usr/bin/env python
"""
Check team assignments
"""
import os
import django
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam, TeamMembership

def check_teams():
    print("=== All Teams ===\n")
    teams = StudentTeam.objects.all()
    
    for team in teams:
        print(f"Team: {team.name} (ID: {team.id})")
        print(f" Leader: {team.leader.username if team.leader else 'None'}")
        print(f" Members:")
        memberships = TeamMembership.objects.filter(team=team)
        for membership in memberships:
            is_leader = "(Leader)" if membership.student == team.leader else ""
            print(f"- {membership.student.username} {is_leader}")
        print()
    
    print("\n=== All Students ===\n")
    students = User.objects.filter(role='student')
    for student in students:
        team = StudentTeam.objects.filter(memberships__student=student).first()
        if team:
            print(f"{student.username}: {team.name}")
        else:
            print(f"{student.username}: NO TEAM")

if __name__ == '__main__':
    check_teams()
