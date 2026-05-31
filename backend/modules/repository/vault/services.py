from academic_period_management.models import SchoolYear
from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import STAGE_OPTIONS, display_name
from repository.entry_payloads import ml_fields_from

from .ml_search import filter_and_rank_entries
from .models import VaultEntry


CAPSTONE_VISIBLE_IDS = ['D4.1', 'D10', 'D17', 'D18', 'D19']
CAPSTONE_RESTRICTED_IDS = ['D15', 'D16']
DEFAULT_YEAR_LEVELS = ['1st Year', '2nd Year', '3rd Year', '4th Year']

TYPE_OPTIONS = [
    {'value': '', 'label': 'All Types'},
    {'value': VaultEntry.TYPE_CAPSTONE, 'label': 'Capstone'},
    {'value': VaultEntry.TYPE_PIT, 'label': 'PIT'},
]


def capstone_visible_queryset():
    return (
        DeliverableSubmission.objects.select_related(
            'team',
            'team__semester',
            'team__semester__school_year',
            'uploaded_by',
        )
        .filter(
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            team__level__icontains='Capstone',
        )
        .exclude(
            deliverable_id__in=CAPSTONE_RESTRICTED_IDS,
        )
        .order_by('-uploaded_at', 'file_name')
    )



def capstone_restricted_queryset():
    return DeliverableSubmission.objects.filter(
        deliverable_type=DeliverableSubmission.TYPE_VAULT,
        deliverable_id__in=CAPSTONE_RESTRICTED_IDS,
        team__level__icontains='Capstone',
    )


def pit_queryset():
    return VaultEntry.objects.select_related('team', 'uploaded_by').filter(
        entry_type=VaultEntry.TYPE_PIT,
    )


def visible_vault_entries_count():
    return pit_queryset().count() + capstone_visible_queryset().count()


def capstone_visible_entries_count():
    return capstone_visible_queryset().count()


def pit_vault_entries_count():
    return pit_queryset().count()


def restricted_vault_entries_count():
    return capstone_restricted_queryset().count()


def capstone_entry_payload(submission):
    team = submission.team
    return {
        'id': f'capstone-{submission.id}',
        'source_id': submission.id,
        'type': VaultEntry.TYPE_CAPSTONE,
        'file_name': submission.file_name,
        'file_size': submission.file_size,
        'file_url': submission.file_url,  # Add file URL
        'deliverable_id': submission.deliverable_id,
        'deliverable_label': submission.label,
        'team_id': team.id,
        'team_name': team.name,
        'project_title': team.project_title,
        'year_level': team.year_level,
        'academic_year': team.semester.school_year.label,
        'semester': team.semester.label,
        'stage': submission.stage_label,
        'status': 'Vault Submission',
        'uploaded_by': display_name(submission.uploaded_by) or 'System',
        'uploaded_at': submission.uploaded_at,
        'restricted': False,
        'viewer_notice': 'Read-only vault preview. Source downloads are disabled from this public archive.',
        # ML search fields
        'extracted_text': submission.extracted_text or '',
        'topics': submission.topics or [],
        'summary': submission.summary or '',
        'category': submission.category or '',
        'category_confidence': submission.category_confidence,
    }


def pit_entry_payload(entry):
    return {
        'id': f'pit-{entry.id}',
        'source_id': entry.id,
        'type': VaultEntry.TYPE_PIT,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': entry.file_url,  # Add file URL for PIT entries
        'deliverable_id': '',
        'deliverable_label': entry.file_name,
        'team_id': entry.team_id,
        'team_name': entry.team_name or (entry.team.name if entry.team else 'Unmatched'),
        'project_title': entry.metadata.get('project_title', '') if isinstance(entry.metadata, dict) else '',
        'year_level': entry.year_level,
        'academic_year': entry.academic_year,
        'semester': entry.semester_label,
        'stage': entry.stage_label or entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'PIT Lead',
        'uploaded_at': entry.uploaded_at,
        'restricted': False,
        'viewer_notice': 'Read-only PIT archive preview. Audit actions are handled in the Repository Audit phase.',
        **ml_fields_from(entry),
    }


def all_visible_entries():
    entries = [pit_entry_payload(entry) for entry in pit_queryset()]
    entries.extend(capstone_entry_payload(submission) for submission in capstone_visible_queryset())
    return sorted(entries, key=lambda item: item.get('uploaded_at'), reverse=True)


def filter_entries(entries, query_params):
    filtered, _suggestions = filter_and_rank_entries(entries, query_params)
    return filtered


def search_vault_payload(request):
    entries = all_visible_entries()
    filtered, suggestions = filter_and_rank_entries(entries, request.query_params)
    return {
        'entries': filtered,
        'suggestions': suggestions,
        'counts': counts_payload(entries, filtered),
        'filters': {
            'search': request.query_params.get('search', ''),
            'type': request.query_params.get('type', ''),
            'year_level': request.query_params.get('year_level', ''),
            'stage': request.query_params.get('stage', ''),
            'academic_year': request.query_params.get('academic_year', ''),
        },
    }


def options_payload(entries):
    year_levels = sorted({entry['year_level'] for entry in entries if entry.get('year_level')})
    stages = sorted({entry['stage'] for entry in entries if entry.get('stage')})
    academic_years = {entry['academic_year'] for entry in entries if entry.get('academic_year')}
    academic_years.update(SchoolYear.objects.values_list('label', flat=True))
    return {
        'type_options': TYPE_OPTIONS,
        'year_levels': sorted(set(DEFAULT_YEAR_LEVELS + year_levels)),
        'stage_options': sorted(set(STAGE_OPTIONS + stages)),
        'academic_years': sorted(academic_years, reverse=True),
    }


def counts_payload(entries, filtered_entries):
    return {
        'total': len(entries),
        'filtered': len(filtered_entries),
        'capstone': sum(1 for entry in entries if entry['type'] == VaultEntry.TYPE_CAPSTONE),
        'pit': sum(1 for entry in entries if entry['type'] == VaultEntry.TYPE_PIT),
        'restricted': restricted_vault_entries_count(),
    }


def digital_vault_payload(request):
    entries = all_visible_entries()
    
    # Note: Vault is public - all authenticated users can see all visible entries
    # No team filtering applied - students can see vault submissions from all teams
    
    filtered_entries, suggestions = filter_and_rank_entries(entries, request.query_params)
    return {
        'entries': filtered_entries,
        'suggestions': suggestions,
        'counts': counts_payload(entries, filtered_entries),
        'options': options_payload(entries),
        'filters': {
            'search': request.query_params.get('search', ''),
            'type': request.query_params.get('type', ''),
            'year_level': request.query_params.get('year_level', ''),
            'stage': request.query_params.get('stage', ''),
            'academic_year': request.query_params.get('academic_year', ''),
        },
        'restricted_deliverable_ids': CAPSTONE_RESTRICTED_IDS,
        'notice': 'Digital Vault is read-only. D15 source code and D16 full manuscripts are intentionally hidden.',
    }
