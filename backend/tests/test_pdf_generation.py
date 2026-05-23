#!/usr/bin/env python
"""
Test script to verify PDF generation for Weekly Progress Reports
"""
import os
import sys
import django

# Setup Django
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_teams.models import StudentTeam
from student_teams.weekly_progress.models import WeeklyProgressReport
from repository.deliverables.pdf_generator import generate_weekly_reports_pdf

def test_pdf_generation():
    """Test PDF generation with actual data"""
    print("Testing PDF Generation for Weekly Progress Reports\n")
    
    # Get a team with weekly reports
    teams_with_reports = StudentTeam.objects.filter(
        weekly_reports__isnull=False
    ).distinct()
    
    if not teams_with_reports.exists():
        print("No teams with weekly progress reports found.")
        print("Please ensure students have submitted weekly reports first.")
        return False
    
    team = teams_with_reports.first()
    print(f"Found team: {team.name}")
    
    # Get reports for this team
    reports = WeeklyProgressReport.objects.filter(team=team).order_by('week_number')
    print(f"Found {reports.count()} weekly reports")
    
    # Generate PDF
    try:
        print("\n Generating PDF...")
        pdf_content = generate_weekly_reports_pdf(team, reports)
        print(f"PDF generated successfully! Size: {len(pdf_content)} bytes ({len(pdf_content)/1024:.2f} KB)")
        
        # Optionally save to file for inspection
        output_file = f"test_output_{team.name.replace(' ', '_')}_WPR.pdf"
        with open(output_file, 'wb') as f:
            f.write(pdf_content)
        print(f"PDF saved to: {output_file}")
        
        return True
    except Exception as e:
        print(f"Error generating PDF: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    try:
        success = test_pdf_generation()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
