#!/usr/bin/env python
"""
Quick test to verify WPR PDF API works
"""
import os
import sys
import django

# Setup Django
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_teams.models import StudentTeam
from student_weekly_progress.models import WeeklyProgressReport

def test_wpr_data():
    """Test if we have the data needed for WPR PDF"""
    print("🔍 Testing WPR PDF Generation Prerequisites\n")
    
    # Check teams
    teams = StudentTeam.objects.all()
    print(f"✅ Total teams: {teams.count()}")
    
    # Check teams with reports
    teams_with_reports = StudentTeam.objects.filter(
        student_progress_reports__isnull=False
    ).distinct()
    
    print(f"✅ Teams with weekly reports: {teams_with_reports.count()}")
    
    if teams_with_reports.exists():
        print("\n📋 Teams with reports:")
        for team in teams_with_reports:
            report_count = WeeklyProgressReport.objects.filter(team=team).count()
            print(f"   • {team.name}: {report_count} reports")
            
            # Show first report details
            first_report = WeeklyProgressReport.objects.filter(team=team).first()
            if first_report:
                student_name = first_report.student.get_full_name() if first_report.student else "Unknown"
                print(f"     - Week {first_report.week_number}, by {student_name}")
                print(f"     - Accomplishments: {len(first_report.accomplishments)} items")
                print(f"     - Contributions: {len(first_report.contributions)} items")
                print(f"     - Issues: {len(first_report.issues)} items")
                print(f"     - Plans: {len(first_report.plans)} items")
    else:
        print("\n⚠️  No teams with weekly reports found!")
        print("   Students need to submit weekly reports first.")
    
    print("\n" + "="*50)
    print("✅ Data check complete!")
    
    return teams_with_reports.exists()

if __name__ == '__main__':
    try:
        has_data = test_wpr_data()
        sys.exit(0 if has_data else 1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
