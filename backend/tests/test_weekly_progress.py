#!/usr/bin/env python
"""
Test script to verify weekly progress report submission
"""
import os
import django
import sys

# Setup Django
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from authentication_access_control.models import User
from student_teams.models import StudentTeam
from student_weekly_progress.models import WeeklyProgressReport
from datetime import date

def test_weekly_progress():
    print("=== Testing Weekly Progress Report System ===\n")
    
    # 1. Check if student1 exists
    try:
        student = User.objects.get(username='student1')
        print(f"✓ Found student: {student.username} (ID: {student.id})")
        print(f"  Role: {student.role}")
        print(f"  Name: {student.first_name} {student.last_name}")
    except User.DoesNotExist:
        print("✗ student1 not found!")
        return
    
    # 2. Check if student has a team
    team = StudentTeam.objects.filter(memberships__student=student).first()
    if team:
        print(f"\n✓ Student is in team: {team.name} (ID: {team.id})")
        print(f"  Leader: {team.leader.username}")
        print(f"  Is leader: {team.leader == student}")
    else:
        print("\n✗ Student is not in any team!")
        return
    
    # 3. Check existing reports
    existing_reports = WeeklyProgressReport.objects.filter(student=student)
    print(f"\n✓ Existing reports: {existing_reports.count()}")
    for report in existing_reports:
        print(f"  - Week {report.week_number}: {report.report_date}")
    
    # 4. Try to create a test report
    print("\n=== Creating Test Report ===")
    try:
        test_report = WeeklyProgressReport.objects.create(
            student=student,
            team=team,
            week_number=99,  # Use 99 to identify test report
            report_date=date.today(),
            accomplishments=[
                {'task': 'Test Task', 'description': 'Test Description'}
            ],
            contributions=[
                {'member': 'Test Member', 'contribution': 'Test Contribution'}
            ],
            issues=[
                {'issue': 'Test Issue', 'action': 'Test Action'}
            ],
            plans=[
                {'task': 'Test Plan', 'output': 'Test Output'}
            ]
        )
        print(f"✓ Test report created successfully!")
        print(f"  ID: {test_report.id}")
        print(f"  Week: {test_report.week_number}")
        print(f"  Date: {test_report.report_date}")
        print(f"  Submitted at: {test_report.submitted_at}")
        
        # Verify it's in the database
        verify = WeeklyProgressReport.objects.get(id=test_report.id)
        print(f"\n✓ Verified report exists in database!")
        print(f"  Student: {verify.student.username}")
        print(f"  Team: {verify.team.name}")
        
        # Clean up test report
        test_report.delete()
        print(f"\n✓ Test report deleted (cleanup)")
        
    except Exception as e:
        print(f"\n✗ Error creating test report: {e}")
        import traceback
        traceback.print_exc()
    
    # 5. Check all reports in database
    all_reports = WeeklyProgressReport.objects.all()
    print(f"\n=== All Reports in Database ===")
    print(f"Total: {all_reports.count()}")
    for report in all_reports:
        print(f"  - {report.student.username} | Team: {report.team.name} | Week {report.week_number} | {report.report_date}")

if __name__ == '__main__':
    test_weekly_progress()
