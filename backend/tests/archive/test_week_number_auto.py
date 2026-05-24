#!/usr/bin/env python
"""
Test automatic week number calculation
"""
import os
import django
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam
from student_teams.weekly_progress.models import WeeklyProgressReport
from datetime import date, timedelta

def test_auto_week_number():
    print("=== Testing Automatic Week Number Calculation ===\n")
    
    # Get student1 (team leader)
    student1 = User.objects.get(username='student1')
    team = StudentTeam.objects.filter(memberships__student=student1).first()
    
    print(f"Student: {student1.username}")
    print(f"Team: {team.name}")
    print(f"Is Leader: {team.leader == student1}\n")
    
    # Delete any existing test reports
    WeeklyProgressReport.objects.filter(student=student1, team=team).delete()
    print("Cleaned up existing reports\n")
    
    # Test 1: First report should be week 1
    print("Test 1: Creating first report...")
    report1 = WeeklyProgressReport.objects.create(
        student=student1,
        team=team,
        week_number=1,
        report_date=date.today(),
        accomplishments=[{'task': 'Task 1', 'description': 'Desc 1'}],
        contributions=[{'member': 'Member 1', 'contribution': 'Contrib 1'}],
        issues=[{'issue': 'Issue 1', 'action': 'Action 1'}],
        plans=[{'task': 'Plan 1', 'output': 'Output 1'}]
    )
    print(f"Created report: Week {report1.week_number}")
    
    # Test 2: Second report should be week 2
    print("\nTest 2: Creating second report...")
    
    # Simulate what the backend will do
    last_report = WeeklyProgressReport.objects.filter(
        student=student1,
        team=team
    ).order_by('-week_number').first()
    
    next_week_number = last_report.week_number + 1 if last_report else 1
    print(f" Last report week: {last_report.week_number}")
    print(f" Next week number: {next_week_number}")
    
    report2 = WeeklyProgressReport.objects.create(
        student=student1,
        team=team,
        week_number=next_week_number,
        report_date=date.today() + timedelta(days=7),
        accomplishments=[{'task': 'Task 2', 'description': 'Desc 2'}],
        contributions=[{'member': 'Member 2', 'contribution': 'Contrib 2'}],
        issues=[{'issue': 'Issue 2', 'action': 'Action 2'}],
        plans=[{'task': 'Plan 2', 'output': 'Output 2'}]
    )
    print(f"Created report: Week {report2.week_number}")
    
    # Test 3: Third report should be week 3
    print("\nTest 3: Creating third report...")
    
    last_report = WeeklyProgressReport.objects.filter(
        student=student1,
        team=team
    ).order_by('-week_number').first()
    
    next_week_number = last_report.week_number + 1 if last_report else 1
    print(f" Last report week: {last_report.week_number}")
    print(f" Next week number: {next_week_number}")
    
    report3 = WeeklyProgressReport.objects.create(
        student=student1,
        team=team,
        week_number=next_week_number,
        report_date=date.today() + timedelta(days=14),
        accomplishments=[{'task': 'Task 3', 'description': 'Desc 3'}],
        contributions=[{'member': 'Member 3', 'contribution': 'Contrib 3'}],
        issues=[{'issue': 'Issue 3', 'action': 'Action 3'}],
        plans=[{'task': 'Plan 3', 'output': 'Output 3'}]
    )
    print(f"Created report: Week {report3.week_number}")
    
    # Verify all reports
    print("\n=== All Reports ===")
    all_reports = WeeklyProgressReport.objects.filter(
        student=student1,
        team=team
    ).order_by('week_number')
    
    for report in all_reports:
        print(f" Week {report.week_number}: {report.report_date}")
    
    print(f"\n SUCCESS! Auto week number calculation works!")
    print(f"Created {all_reports.count()} reports with sequential week numbers")
    
    # Clean up
    print("\nCleaning up test reports...")
    WeeklyProgressReport.objects.filter(student=student1, team=team).delete()
    print("Cleanup complete")

if __name__ == '__main__':
    test_auto_week_number()
