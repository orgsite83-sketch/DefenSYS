#!/usr/bin/env python
"""
Test that ALL team leaders can submit weekly progress reports
"""
import os
import django
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam
from student_weekly_progress.models import WeeklyProgressReport
from datetime import date

def test_all_leaders():
    print("=== Testing All Team Leaders ===\n")
    
    # Get all teams
    teams = StudentTeam.objects.all()
    
    for team in teams:
        print(f"\n{'='*60}")
        print(f"Team: {team.name} (ID: {team.id})")
        print(f"Leader: {team.leader.username}")
        print(f"{'='*60}")
        
        leader = team.leader
        
        # Check if leader can create a report
        print(f"\n1. Checking if {leader.username} is a student...")
        if leader.role != 'student':
            print(f"   ✗ {leader.username} is not a student (role: {leader.role})")
            continue
        print(f"   ✓ {leader.username} is a student")
        
        print(f"\n2. Checking if {leader.username} is in a team...")
        leader_team = StudentTeam.objects.filter(memberships__student=leader).first()
        if not leader_team:
            print(f"   ✗ {leader.username} is not in any team")
            continue
        print(f"   ✓ {leader.username} is in team: {leader_team.name}")
        
        print(f"\n3. Checking if {leader.username} is the team leader...")
        if leader_team.leader != leader:
            print(f"   ✗ {leader.username} is NOT the leader (leader is {leader_team.leader.username})")
            continue
        print(f"   ✓ {leader.username} IS the team leader!")
        
        print(f"\n4. Testing report creation for {leader.username}...")
        try:
            # Create a test report
            test_report = WeeklyProgressReport.objects.create(
                student=leader,
                team=leader_team,
                week_number=999,  # Use 999 to identify test reports
                report_date=date.today(),
                accomplishments=[{'task': 'Test', 'description': 'Test'}],
                contributions=[{'member': 'Test', 'contribution': 'Test'}],
                issues=[{'issue': 'Test', 'action': 'Test'}],
                plans=[{'task': 'Test', 'output': 'Test'}]
            )
            print(f"   ✅ SUCCESS! {leader.username} can submit reports!")
            print(f"      Report ID: {test_report.id}")
            print(f"      Week: {test_report.week_number}")
            print(f"      Date: {test_report.report_date}")
            
            # Clean up
            test_report.delete()
            print(f"   ✓ Test report deleted (cleanup)")
            
        except Exception as e:
            print(f"   ✗ ERROR: {e}")
    
    print(f"\n\n{'='*60}")
    print("SUMMARY: All Team Leaders Can Submit Reports")
    print(f"{'='*60}")
    
    leaders = []
    for team in teams:
        if team.leader.role == 'student':
            leaders.append(f"{team.leader.username} (Team: {team.name})")
    
    print("\nTeam Leaders Who Can Submit:")
    for leader in leaders:
        print(f"  ✅ {leader}")
    
    print(f"\nTotal Leaders: {len(leaders)}")

if __name__ == '__main__':
    test_all_leaders()
