#!/usr/bin/env python
"""
Direct test of PDF generation to see exact error
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
from capstone_deliverables.pdf_generator import generate_weekly_reports_pdf

def test_direct_pdf():
    """Test PDF generation directly"""
    print("🔍 Testing Direct PDF Generation\n")
    
    # Get team 666 (has 3 reports)
    try:
        team = StudentTeam.objects.get(name="666")
        print(f"✅ Found team: {team.name}")
    except StudentTeam.DoesNotExist:
        print("❌ Team 666 not found, trying team 111...")
        try:
            team = StudentTeam.objects.get(name="111")
            print(f"✅ Found team: {team.name}")
        except StudentTeam.DoesNotExist:
            print("❌ No test teams found!")
            return False
    
    # Get reports
    reports = WeeklyProgressReport.objects.filter(team=team).order_by('week_number')
    print(f"✅ Found {reports.count()} reports")
    
    # Show report details
    for report in reports:
        student_name = report.student.get_full_name() if report.student else "Unknown"
        print(f"   • Week {report.week_number} by {student_name}")
    
    # Try to generate PDF
    print("\n📄 Generating PDF...")
    try:
        pdf_content = generate_weekly_reports_pdf(team, reports)
        print(f"✅ PDF generated successfully!")
        print(f"   Size: {len(pdf_content)} bytes ({len(pdf_content)/1024:.2f} KB)")
        
        # Save to file
        filename = f"test_direct_{team.name}_WPR.pdf"
        with open(filename, 'wb') as f:
            f.write(pdf_content)
        print(f"✅ PDF saved to: {filename}")
        
        return True
    except Exception as e:
        print(f"❌ PDF generation failed!")
        print(f"   Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    try:
        success = test_direct_pdf()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
