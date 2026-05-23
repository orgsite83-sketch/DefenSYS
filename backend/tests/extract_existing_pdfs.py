"""
Extract PDF content from existing files in the database
Run this script to populate extracted_text, topics, and summary fields
"""

import os
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from repository.deliverables.models import DeliverableSubmission
from repository.vault.models import VaultEntry
from student_teams.weekly_progress.models import WeeklyProgressReport
from repository.deliverables.pdf_processor import extract_pdf_content


def extract_deliverables():
    """Extract PDF content from deliverable submissions"""
    print('\n' + '='*80)
    print('EXTRACTING PDF CONTENT FROM DELIVERABLE SUBMISSIONS')
    print('='*80)
    
    submissions = DeliverableSubmission.objects.filter(file__isnull=False).exclude(file='')
    total = submissions.count()
    print(f'\n Found {total} deliverable submissions with files')
    
    extracted = 0
    skipped = 0
    failed = 0
    
    for i, submission in enumerate(submissions, 1):
        print(f'\n[{i}/{total}] Processing: {submission.file_name}')
        
        # Skip if already extracted
        if submission.extracted_text:
            print(f'Skipped: Already extracted ({len(submission.extracted_text)} chars)')
            skipped += 1
            continue
        
        # Check if file exists
        if not os.path.exists(submission.file.path):
            print(f'Warning: File not found: {submission.file.path}')
            failed += 1
            continue
        
        try:
            # Extract content
            result = extract_pdf_content(submission.file.path)
            
            if result['text']:
                submission.extracted_text = result['text']
                submission.topics = result['topics']
                submission.summary = result['summary']
                submission.save()
                
                print(f'Extracted: {len(result["text"])} chars, {len(result["topics"])} topics')
                print(f'Topics: {", ".join(result["topics"][:5])}...')
                extracted += 1
            else:
                print(f'Warning: No text extracted')
                failed += 1
                
        except Exception as e:
            print(f'Error: {e}')
            failed += 1
    
    print(f'\n Deliverables Summary:')
    print(f'Extracted: {extracted}')
    print(f'Skipped: Skipped: {skipped}')
    print(f'Failed: {failed}')


def extract_vault_entries():
    """Extract PDF content from vault entries"""
    print('\n' + '='*80)
    print('EXTRACTING PDF CONTENT FROM VAULT ENTRIES')
    print('='*80)
    
    entries = VaultEntry.objects.filter(file__isnull=False).exclude(file='')
    total = entries.count()
    print(f'\n Found {total} vault entries with files')
    
    extracted = 0
    skipped = 0
    failed = 0
    
    for i, entry in enumerate(entries, 1):
        print(f'\n[{i}/{total}] Processing: {entry.file_name}')
        
        # Skip if already extracted
        if entry.extracted_text:
            print(f'Skipped: Already extracted ({len(entry.extracted_text)} chars)')
            skipped += 1
            continue
        
        # Check if file exists
        if not os.path.exists(entry.file.path):
            print(f'Warning: File not found: {entry.file.path}')
            failed += 1
            continue
        
        try:
            # Extract content
            result = extract_pdf_content(entry.file.path)
            
            if result['text']:
                entry.extracted_text = result['text']
                entry.topics = result['topics']
                entry.summary = result['summary']
                entry.save()
                
                print(f'Extracted: {len(result["text"])} chars, {len(result["topics"])} topics')
                print(f'Topics: {", ".join(result["topics"][:5])}...')
                extracted += 1
            else:
                print(f'Warning: No text extracted')
                failed += 1
                
        except Exception as e:
            print(f'Error: {e}')
            failed += 1
    
    print(f'\n Vault Entries Summary:')
    print(f'Extracted: {extracted}')
    print(f'Skipped: Skipped: {skipped}')
    print(f'Failed: {failed}')


def extract_weekly_reports():
    """Extract PDF content from weekly progress reports"""
    print('\n' + '='*80)
    print('EXTRACTING PDF CONTENT FROM WEEKLY PROGRESS REPORTS')
    print('='*80)
    
    reports = WeeklyProgressReport.objects.filter(report_file__isnull=False).exclude(report_file='')
    total = reports.count()
    print(f'\n Found {total} weekly reports with files')
    
    extracted = 0
    skipped = 0
    failed = 0
    
    for i, report in enumerate(reports, 1):
        print(f'\n[{i}/{total}] Processing: Week {report.week_number} - {report.student.username}')
        
        # Skip if already extracted
        if report.extracted_text:
            print(f'Skipped: Already extracted ({len(report.extracted_text)} chars)')
            skipped += 1
            continue
        
        # Check if file exists
        if not os.path.exists(report.report_file.path):
            print(f'Warning: File not found: {report.report_file.path}')
            failed += 1
            continue
        
        try:
            # Extract content
            result = extract_pdf_content(report.report_file.path)
            
            if result['text']:
                report.extracted_text = result['text']
                report.topics = result['topics']
                report.summary = result['summary']
                report.save()
                
                print(f'Extracted: {len(result["text"])} chars, {len(result["topics"])} topics')
                print(f'Topics: {", ".join(result["topics"][:5])}...')
                extracted += 1
            else:
                print(f'Warning: No text extracted')
                failed += 1
                
        except Exception as e:
            print(f'Error: {e}')
            failed += 1
    
    print(f'\n Weekly Reports Summary:')
    print(f'Extracted: {extracted}')
    print(f'Skipped: Skipped: {skipped}')
    print(f'Failed: {failed}')


if __name__ == '__main__':
    print('\n Starting PDF Content Extraction...')
    
    extract_deliverables()
    extract_vault_entries()
    extract_weekly_reports()
    
    print('\n' + '='*80)
    print('PDF CONTENT EXTRACTION COMPLETE')
    print('='*80)
    print('\nAll existing PDF files have been processed.')
    print('New uploads will be automatically extracted on save.')
