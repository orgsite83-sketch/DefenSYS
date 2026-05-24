"""
Test ML search functionality
"""

import os
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from repository.deliverables.models import DeliverableSubmission
from repository.vault.models import VaultEntry
from student_teams.weekly_progress.models import WeeklyProgressReport


def test_deliverables():
    """Test deliverable submissions"""
    print('\n' + '='*80)
    print('TESTING DELIVERABLE SUBMISSIONS')
    print('='*80)
    
    submissions = DeliverableSubmission.objects.filter(file__isnull=False).exclude(file='')
    
    for submission in submissions:
        print(f'\n File: {submission.file_name}')
        print(f'Text Length: {len(submission.extracted_text)} chars')
        print(f'Topics: {submission.topics}')
        print(f'Summary: {submission.summary[:100]}...' if len(submission.summary) > 100 else f'   Summary: {submission.summary}')


def test_weekly_reports():
    """Test weekly progress reports"""
    print('\n' + '='*80)
    print('TESTING WEEKLY PROGRESS REPORTS')
    print('='*80)
    
    reports = WeeklyProgressReport.objects.filter(report_file__isnull=False).exclude(report_file='')
    
    for report in reports:
        print(f'\n Week {report.week_number} - {report.student.username}')
        print(f'Text Length: {len(report.extracted_text)} chars')
        print(f'Topics: {report.topics}')
        print(f'Summary: {report.summary[:100]}...' if len(report.summary) > 100 else f'   Summary: {report.summary}')


def test_vault_entries():
    """Test vault entries"""
    print('\n' + '='*80)
    print('TESTING VAULT ENTRIES')
    print('='*80)
    
    entries = VaultEntry.objects.filter(file__isnull=False).exclude(file='')
    
    if entries.count() == 0:
        print('\nWarning: No vault entries with files yet')
        return
    
    for entry in entries:
        print(f'\n File: {entry.file_name}')
        print(f'Text Length: {len(entry.extracted_text)} chars')
        print(f'Topics: {entry.topics}')
        print(f'Summary: {entry.summary[:100]}...' if len(entry.summary) > 100 else f'   Summary: {entry.summary}')


def test_search_simulation():
    """Simulate search queries"""
    print('\n' + '='*80)
    print('SIMULATING SEARCH QUERIES')
    print('='*80)
    
    # Get all documents
    deliverables = list(DeliverableSubmission.objects.filter(file__isnull=False).exclude(file=''))
    reports = list(WeeklyProgressReport.objects.filter(report_file__isnull=False).exclude(report_file=''))
    
    all_docs = []
    
    # Add deliverables
    for d in deliverables:
        all_docs.append({
            'type': 'deliverable',
            'name': d.file_name,
            'text': d.extracted_text,
            'topics': d.topics,
        })
    
    # Add reports
    for r in reports:
        all_docs.append({
            'type': 'report',
            'name': f'Week {r.week_number}',
            'text': r.extracted_text,
            'topics': r.topics,
        })
    
    # Test queries
    queries = [
        'machine learning',
        'project',
        'marketlink',
        'team',
        'msmes',
    ]
    
    for query in queries:
        print(f'\n Query: "{query}"')
        matches = []
        
        for doc in all_docs:
            # Simple search in text and topics
            text_match = query.lower() in doc['text'].lower()
            topic_match = any(query.lower() in topic.lower() for topic in doc['topics'])
            
            if text_match or topic_match:
                matches.append({
                    'name': doc['name'],
                    'type': doc['type'],
                    'text_match': text_match,
                    'topic_match': topic_match,
                })
        
        if matches:
            print(f'Found {len(matches)} matches:')
            for match in matches:
                match_type = []
                if match['text_match']:
                    match_type.append('content')
                if match['topic_match']:
                    match_type.append('topic')
                print(f'- {match["name"]} ({match["type"]}) - matched in: {", ".join(match_type)}')
        else:
            print(f'No matches found')


if __name__ == '__main__':
    print('\n Testing ML Search Functionality...')
    
    test_deliverables()
    test_weekly_reports()
    test_vault_entries()
    test_search_simulation()
    
    print('\n' + '='*80)
    print('ML SEARCH TEST COMPLETE')
    print('='*80)
