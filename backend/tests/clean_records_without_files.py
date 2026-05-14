import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from student_weekly_progress.models import WeeklyProgressReport
from capstone_deliverables.models import DeliverableSubmission
from django.conf import settings

print('='*80)
print('CLEANING RECORDS WITHOUT ACTUAL FILES')
print('='*80)
print()

# Track deletions
deleted_reports = []
deleted_deliverables = []

# ============================================================================
# 1. CLEAN WEEKLY PROGRESS REPORTS
# ============================================================================
print('1. CHECKING WEEKLY PROGRESS REPORTS')
print('-'*80)

reports = WeeklyProgressReport.objects.all()
print(f'Total weekly reports: {reports.count()}')
print()

for report in reports:
    should_delete = False
    reason = ''
    
    if not report.report_file or report.report_file == '':
        # No file field at all
        should_delete = True
        reason = 'No file field'
    else:
        # Has file field, check if file exists on disk
        try:
            file_path = report.report_file.path
            if not os.path.exists(file_path):
                should_delete = True
                reason = f'File missing on disk: {file_path}'
        except Exception as e:
            should_delete = True
            reason = f'Error accessing file: {e}'
    
    if should_delete:
        print(f'❌ DELETING Report ID {report.id}:')
        print(f'   Student: {report.student.username}')
        print(f'   Team: {report.team.name}')
        print(f'   Week: {report.week_number}')
        print(f'   Date: {report.report_date}')
        print(f'   Reason: {reason}')
        
        deleted_reports.append({
            'id': report.id,
            'student': report.student.username,
            'team': report.team.name,
            'week': report.week_number,
            'reason': reason
        })
        
        report.delete()
        print(f'   ✅ Deleted')
        print()

print(f'Weekly reports deleted: {len(deleted_reports)}')
print()

# ============================================================================
# 2. CLEAN DELIVERABLE SUBMISSIONS
# ============================================================================
print('2. CHECKING DELIVERABLE SUBMISSIONS')
print('-'*80)

submissions = DeliverableSubmission.objects.all()
print(f'Total deliverable submissions: {submissions.count()}')
print()

for sub in submissions:
    should_delete = False
    reason = ''
    
    if not sub.file or sub.file == '':
        # No file field at all
        should_delete = True
        reason = 'No file field'
    else:
        # Has file field, check if file exists on disk
        try:
            file_path = sub.file.path
            if not os.path.exists(file_path):
                should_delete = True
                reason = f'File missing on disk: {file_path}'
        except Exception as e:
            should_delete = True
            reason = f'Error accessing file: {e}'
    
    if should_delete:
        print(f'❌ DELETING Submission ID {sub.id}:')
        print(f'   Type: {sub.deliverable_type}')
        print(f'   Team: {sub.team.name}')
        print(f'   Deliverable: {sub.deliverable_id} - {sub.label}')
        print(f'   Stage: {sub.stage_label}')
        print(f'   File name: {sub.file_name}')
        print(f'   Reason: {reason}')
        
        deleted_deliverables.append({
            'id': sub.id,
            'type': sub.deliverable_type,
            'team': sub.team.name,
            'deliverable': f'{sub.deliverable_id} - {sub.label}',
            'reason': reason
        })
        
        sub.delete()
        print(f'   ✅ Deleted')
        print()

print(f'Deliverable submissions deleted: {len(deleted_deliverables)}')
print()

# ============================================================================
# SUMMARY
# ============================================================================
print('='*80)
print('CLEANUP SUMMARY')
print('='*80)
print()

print(f'Weekly Progress Reports:')
print(f'  Deleted: {len(deleted_reports)}')
print(f'  Remaining: {WeeklyProgressReport.objects.count()}')
print()

print(f'Deliverable Submissions:')
print(f'  Deleted: {len(deleted_deliverables)}')
print(f'  Remaining: {DeliverableSubmission.objects.count()}')
print()

print(f'Total records deleted: {len(deleted_reports) + len(deleted_deliverables)}')
print()

# ============================================================================
# VERIFICATION
# ============================================================================
print('='*80)
print('VERIFICATION - REMAINING RECORDS')
print('='*80)
print()

print('Weekly Progress Reports with files:')
reports_with_files = WeeklyProgressReport.objects.exclude(report_file='').exclude(report_file__isnull=True)
for report in reports_with_files:
    file_exists = os.path.exists(report.report_file.path)
    status = '✅' if file_exists else '❌'
    print(f'  {status} Report ID {report.id}: Week {report.week_number}, {report.student.username}')
print(f'  Total: {reports_with_files.count()}')
print()

print('Deliverable Submissions with files:')
subs_with_files = DeliverableSubmission.objects.exclude(file='').exclude(file__isnull=True)
for sub in subs_with_files:
    file_exists = os.path.exists(sub.file.path)
    status = '✅' if file_exists else '❌'
    print(f'  {status} Submission ID {sub.id}: {sub.deliverable_id}, {sub.team.name}')
print(f'  Total: {subs_with_files.count()}')
print()

print('='*80)
print('CLEANUP COMPLETE!')
print('='*80)
