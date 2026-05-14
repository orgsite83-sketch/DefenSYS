import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_weekly_progress.models import WeeklyProgressReport
from django.conf import settings

print('='*80)
print('CHECKING WEEKLY PROGRESS REPORTS')
print('='*80)
print()

# Check all weekly reports
reports = WeeklyProgressReport.objects.all().order_by('-submitted_at')
print(f'Total weekly progress reports: {reports.count()}')
print()

if reports.count() == 0:
    print('❌ No weekly progress reports found in database')
    print()
else:
    print('='*80)
    print('DETAILED REPORT LIST')
    print('='*80)
    print()
    
    for report in reports:
        print(f'Report ID: {report.id}')
        print(f'  Team: {report.team.name} (ID: {report.team.id})')
        print(f'  Student: {report.student.username} ({report.student.first_name} {report.student.last_name})')
        print(f'  Week: {report.week_number}')
        print(f'  Report date: {report.report_date}')
        print(f'  Report file field: "{report.report_file}"')
        
        # Check if file exists on disk
        if report.report_file:
            file_path = report.report_file.path
            exists = os.path.exists(file_path)
            print(f'  File path: {file_path}')
            print(f'  File exists on disk: {"✅ YES" if exists else "❌ NO"}')
            if exists:
                size = os.path.getsize(file_path)
                print(f'  File size: {size / 1024:.2f} KB')
            print(f'  File URL: {report.report_file.url}')
        else:
            print(f'  ❌ No file attached (report_file field is empty)')
        
        print(f'  Submitted at: {report.submitted_at}')
        print()

    print('='*80)
    print('SUMMARY')
    print('='*80)
    print()
    
    with_file = reports.filter(report_file__isnull=False).exclude(report_file='').count()
    without_file = reports.count() - with_file
    
    print(f'Total reports: {reports.count()}')
    print(f'With file: {with_file}')
    print(f'Without file: {without_file}')
    print()
    
    # Check media folder
    media_root = settings.MEDIA_ROOT
    reports_path = os.path.join(media_root, 'weekly_reports')
    
    print('MEDIA FOLDER CHECK:')
    print(f'Media root: {media_root}')
    print()
    
    if os.path.exists(reports_path):
        print(f'✅ Weekly reports folder exists: {reports_path}')
        print()
        # List files
        for root, dirs, files in os.walk(reports_path):
            level = root.replace(reports_path, '').count(os.sep)
            indent = ' ' * 2 * level
            print(f'{indent}{os.path.basename(root)}/')
            subindent = ' ' * 2 * (level + 1)
            for file in files:
                file_path = os.path.join(root, file)
                size = os.path.getsize(file_path)
                print(f'{subindent}{file} ({size / 1024:.2f} KB)')
    else:
        print(f'❌ Weekly reports folder does not exist: {reports_path}')
