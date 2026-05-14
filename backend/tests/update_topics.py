"""
Update topics for files that have extracted_text but no topics
"""

import os
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from capstone_deliverables.models import DeliverableSubmission
from digital_vault.models import VaultEntry
from student_weekly_progress.models import WeeklyProgressReport
from capstone_deliverables.pdf_processor import extract_topics_tfidf


def update_deliverables():
    """Update topics for deliverable submissions"""
    print('\n' + '='*80)
    print('UPDATING TOPICS FOR DELIVERABLE SUBMISSIONS')
    print('='*80)
    
    submissions = DeliverableSubmission.objects.filter(extracted_text__isnull=False).exclude(extracted_text='')
    total = submissions.count()
    print(f'\n📊 Found {total} deliverable submissions with extracted text')
    
    updated = 0
    
    for i, submission in enumerate(submissions, 1):
        print(f'\n[{i}/{total}] Processing: {submission.file_name}')
        
        if submission.topics:
            print(f'   ⏭️  Already has topics: {submission.topics}')
            continue
        
        try:
            # Extract topics from existing text
            topics = extract_topics_tfidf(submission.extracted_text)
            
            if topics:
                submission.topics = topics
                submission.save()
                print(f'   ✅ Updated topics: {", ".join(topics[:5])}...')
                updated += 1
            else:
                print(f'   ⚠️  No topics extracted')
                
        except Exception as e:
            print(f'   ❌ Error: {e}')
    
    print(f'\n📈 Updated {updated} deliverable submissions')


def update_vault_entries():
    """Update topics for vault entries"""
    print('\n' + '='*80)
    print('UPDATING TOPICS FOR VAULT ENTRIES')
    print('='*80)
    
    entries = VaultEntry.objects.filter(extracted_text__isnull=False).exclude(extracted_text='')
    total = entries.count()
    print(f'\n📊 Found {total} vault entries with extracted text')
    
    updated = 0
    
    for i, entry in enumerate(entries, 1):
        print(f'\n[{i}/{total}] Processing: {entry.file_name}')
        
        if entry.topics:
            print(f'   ⏭️  Already has topics: {entry.topics}')
            continue
        
        try:
            # Extract topics from existing text
            topics = extract_topics_tfidf(entry.extracted_text)
            
            if topics:
                entry.topics = topics
                entry.save()
                print(f'   ✅ Updated topics: {", ".join(topics[:5])}...')
                updated += 1
            else:
                print(f'   ⚠️  No topics extracted')
                
        except Exception as e:
            print(f'   ❌ Error: {e}')
    
    print(f'\n📈 Updated {updated} vault entries')


def update_weekly_reports():
    """Update topics for weekly progress reports"""
    print('\n' + '='*80)
    print('UPDATING TOPICS FOR WEEKLY PROGRESS REPORTS')
    print('='*80)
    
    reports = WeeklyProgressReport.objects.filter(extracted_text__isnull=False).exclude(extracted_text='')
    total = reports.count()
    print(f'\n📊 Found {total} weekly reports with extracted text')
    
    updated = 0
    
    for i, report in enumerate(reports, 1):
        print(f'\n[{i}/{total}] Processing: Week {report.week_number} - {report.student.username}')
        
        if report.topics:
            print(f'   ⏭️  Already has topics: {report.topics}')
            continue
        
        try:
            # Extract topics from existing text
            topics = extract_topics_tfidf(report.extracted_text)
            
            if topics:
                report.topics = topics
                report.save()
                print(f'   ✅ Updated topics: {", ".join(topics[:5])}...')
                updated += 1
            else:
                print(f'   ⚠️  No topics extracted')
                
        except Exception as e:
            print(f'   ❌ Error: {e}')
    
    print(f'\n📈 Updated {updated} weekly reports')


if __name__ == '__main__':
    print('\n🚀 Starting Topic Extraction...')
    
    update_deliverables()
    update_vault_entries()
    update_weekly_reports()
    
    print('\n' + '='*80)
    print('✅ TOPIC EXTRACTION COMPLETE')
    print('='*80)
