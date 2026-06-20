from academic_period_management.models import SchoolYear
from defense.stages.models import DefenseStage
from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import display_name
from repository.entry_payloads import ml_fields_from

from .ml_search import filter_and_rank_entries
from .models import VaultEntry


CAPSTONE_VISIBLE_IDS = ['D4.1', 'D10', 'D17', 'D18', 'D19']
DEFAULT_YEAR_LEVELS = ['1st Year', '2nd Year', '3rd Year', '4th Year']

TYPE_OPTIONS = [
    {'value': '', 'label': 'All Types'},
    {'value': VaultEntry.TYPE_CAPSTONE, 'label': 'Capstone'},
    {'value': VaultEntry.TYPE_PIT, 'label': 'PIT'},
]


def active_defense_stage_options():
    return list(
        DefenseStage.objects.filter(is_active=True)
        .order_by('display_order', 'label')
        .values_list('label', flat=True)
    )


def pit_visible_deliverables_queryset():
    from defense.scheduler.models import PitEventDeliverable
    restricted_ids = PitEventDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return (
        DeliverableSubmission.objects.select_related(
            'team',
            'team__semester',
            'team__semester__school_year',
            'uploaded_by',
        )
        .filter(
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            team__level__icontains='PIT',
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )
        .exclude(
            deliverable_id__in=restricted_ids,
        )
        .order_by('-uploaded_at', 'file_name')
    )


def capstone_visible_queryset():
    from defense.stages.models import StageDeliverable
    restricted_ids = StageDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
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
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )
        .exclude(
            deliverable_id__in=restricted_ids,
        )
        .order_by('-uploaded_at', 'file_name')
    )


def capstone_restricted_queryset():
    from defense.stages.models import StageDeliverable
    restricted_ids = StageDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return DeliverableSubmission.objects.filter(
        deliverable_type=DeliverableSubmission.TYPE_VAULT,
        deliverable_id__in=restricted_ids,
        team__level__icontains='Capstone',
        status=DeliverableSubmission.STATUS_ACCEPTED,
    )


def pit_restricted_queryset():
    from defense.scheduler.models import PitEventDeliverable
    restricted_ids = PitEventDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return DeliverableSubmission.objects.filter(
        deliverable_type=DeliverableSubmission.TYPE_VAULT,
        deliverable_id__in=restricted_ids,
        team__level__icontains='PIT',
        status=DeliverableSubmission.STATUS_ACCEPTED,
    )


def pit_queryset():
    return VaultEntry.objects.select_related('team', 'uploaded_by').filter(
        entry_type=VaultEntry.TYPE_PIT,
    )


def visible_vault_entries_count():
    return pit_queryset().count() + capstone_visible_queryset().count() + pit_visible_deliverables_queryset().count()


def capstone_visible_entries_count():
    return capstone_visible_queryset().count()


def pit_vault_entries_count():
    return pit_queryset().count() + pit_visible_deliverables_queryset().count()


def restricted_vault_entries_count():
    return capstone_restricted_queryset().count() + pit_restricted_queryset().count()


def capstone_entry_payload(submission):
    team = submission.team
    is_pit = team.is_pit if team else False
    entry_type = VaultEntry.TYPE_PIT if is_pit else VaultEntry.TYPE_CAPSTONE
    entry_id = f'pit-deliverable-{submission.id}' if is_pit else f'capstone-{submission.id}'
    viewer_notice = (
        'Read-only PIT archive preview. Audit actions are handled in the Repository Audit phase.'
        if is_pit
        else 'Read-only vault preview. Source downloads are disabled from this public archive.'
    )
    return {
        'id': entry_id,
        'source_id': submission.id,
        'type': entry_type,
        'file_name': submission.file_name,
        'file_size': submission.file_size,
        'file_url': submission.file_url,  # Add file URL
        'deliverable_id': submission.deliverable_id,
        'deliverable_label': submission.label,
        'team_id': team.id,
        'team_name': team.name,
        'project_title': team.project_title,
        'year_level': team.year_level,
        'academic_year': team.semester.school_year.label if team.semester else '',
        'semester': team.semester.label if team.semester else '',
        'stage': submission.stage_label,
        'status': 'Vault Submission' if not is_pit else submission.status,
        'uploaded_by': display_name(submission.uploaded_by) or 'System',
        'uploaded_at': submission.uploaded_at,
        'restricted': False,
        'viewer_notice': viewer_notice,
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
    submissions = list(capstone_visible_queryset()) + list(pit_visible_deliverables_queryset())
    submission_keys = {(s.team_id, s.stage_label) for s in submissions if s.team_id and s.stage_label}

    pit_entries = []
    for entry in pit_queryset():
        if entry.team_id and entry.stage_label and (entry.team_id, entry.stage_label) in submission_keys:
            continue
        pit_entries.append(entry)

    entries = [pit_entry_payload(entry) for entry in pit_entries]
    entries.extend(capstone_entry_payload(submission) for submission in submissions)
    return sorted(entries, key=lambda item: item.get('uploaded_at'), reverse=True)


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
        'stage_options': sorted(set(active_defense_stage_options() + stages)),
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
    
    from defense.stages.models import StageDeliverable
    from defense.scheduler.models import PitEventDeliverable
    restricted_ids = list(StageDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)) + \
                     list(PitEventDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True))
                     
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
        'restricted_deliverable_ids': restricted_ids,
        'notice': 'Digital Vault is read-only. Restricted deliverables are intentionally hidden.',
    }
