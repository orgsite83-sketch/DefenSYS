"""Configuration guards include archived project versions and submission history.

Scheduling protects the stage's structure. Authored scores freeze configuration;
before then each requirement is protected independently once it has been used.
"""
from django.db.models import Q
from defensys_backend.read_projection import read_memoize


REQUIREMENT_FIELDS = (
    'deliverable_id', 'label', 'deliverable_type', 'required', 'requirement_timing',
    'deadline_hours_before', 'archive_note', 'archive_file_template', 'is_restricted',
    'is_defense_material', 'verdict_condition', 'file_format', 'file_policy',
)
DATA_REASON = 'This deliverable has submissions or recorded history and cannot be edited or deleted.'


def context_filter(context):
    return {'pit_event_config': context} if hasattr(context, 'event_name') else {'defense_stage': context}


def context_submissions(context):
    from repository.deliverables.models import DeliverableSubmission
    rows = DeliverableSubmission.all_objects.all()
    if hasattr(context, 'event_name'):
        # Older records may predate the explicit event link. Use captured archive
        # identity before the team's current enrollment when matching those rows.
        legacy = Q(pit_event_config__isnull=True, stage_label__iexact=context.event_name)
        legacy &= (Q(archive_semester=context.semester, archive_year_level=context.year_level)
                   | Q(archive_semester__isnull=True, team__semester=context.semester,
                       team__year_level=context.year_level, team__level__icontains='PIT'))
        legacy &= (Q(archive_team_level__icontains='PIT')
                   | Q(archive_team_level='', team__level__icontains='PIT'))
        return rows.filter(Q(pit_event_config=context) | legacy)
    return rows.filter(stage_label__iexact=context.label, pit_event_config__isnull=True).filter(
        Q(archive_team_level__icontains='Capstone')
        | Q(archive_team_level='', team__level__icontains='Capstone'))


@read_memoize
def grade_configuration_lock(context, semester=None):
    from defense.scheduler.models import DefenseSchedule, PanelistEvaluationDraft
    from grading.grades.models import TeamGrade
    if hasattr(context, 'event_name'):
        if context.is_officially_complete:
            return True, 'This PIT event is officially complete.'
        grades = TeamGrade.all_objects.filter(
            Q(pit_event_config=context) | Q(pit_event_config__isnull=True,
                semester=context.semester, scope='pit', team__year_level=context.year_level,
                stage_label__iexact=context.event_name))
        schedules = DefenseSchedule.objects.filter(semester=context.semester, scope='pit',
            team__year_level=context.year_level, event_name__iexact=context.event_name)
    else:
        configs = context.grading_configs.all()
        if semester is not None:
            configs = configs.filter(semester=semester)
        # No semester means structural protection across all historical uses.
        # Explicit semester means only that term's grading weights and rubrics.
        if configs.filter(is_officially_complete=True).exists():
            return True, 'This stage is officially complete.'
        grades = TeamGrade.all_objects.filter(
            Q(defense_stage=context) | Q(defense_stage__isnull=True, scope='capstone',
                                        stage_label__iexact=context.label))
        schedules = DefenseSchedule.objects.filter(defense_stage=context)
        if semester is not None:
            grades = grades.filter(semester=semester)
            schedules = schedules.filter(semester=semester)
    scored = Q(verdict__gt='') | Q(published_at__isnull=False) | ~Q(status=TeamGrade.STATUS_PENDING)
    for prefix in ('', 'student_grades__', 'attempt_history__'):
        for field in ('panel_score', 'adviser_score', 'peer_score', 'final_grade'):
            scored |= Q(**{f'{prefix}{field}__isnull': False})
    for relation in ('breakdowns', 'peer_evaluation_submissions', 'attempt_history'):
        scored |= Q(**{f'{relation}__isnull': False})
    scored |= Q(panelist_submissions__criterion_scores__isnull=False)
    if grades.filter(scored).exists():
        return True, 'Configuration is locked because this stage has saved evaluation scores or grade history.'
    drafts = PanelistEvaluationDraft.objects.filter(schedule__in=schedules).values_list('submissions', flat=True)
    for submissions in drafts:
        if any(score.get('score') not in (None, '')
               for item in submissions if isinstance(item, dict)
               for score in item.get('criteria_scores', []) if isinstance(score, dict)):
            return True, 'Configuration is locked because an evaluator has saved draft scores.'
    return False, None


@read_memoize
def requirement_has_data(context, number, *, policy=None, shared=False):
    from defense.shared_deliverables import shared_definitions
    from repository.deliverables.models import ConceptRound
    from repository.section_concepts.models import (
        SectionConceptProject, SectionConceptPaper, SharedDeliverableFile,
    )
    filters = context_filter(context)
    if not shared and context_submissions(context).filter(deliverable_id=number).exists():
        return True
    definitions = shared_definitions(context)
    linked = [row for row in definitions if row.get('team_deliverable_id') == number] if not shared else [
        row for row in definitions if row.get('deliverable_id') == number]
    shared_numbers = [row['deliverable_id'] for row in linked]
    if shared:
        shared_numbers.append(number)
    if shared_numbers:
        if SharedDeliverableFile.objects.filter(
                **{f'submission_set__{key}': value for key, value in filters.items()},
                deliverable_id__in=shared_numbers).exists():
            return True
        for row in linked:
            purpose = row.get('legacy_purpose')
            if purpose and SectionConceptPaper.objects.filter(
                    **{f'concept__round__project__{key}': value for key, value in filters.items()},
                    purpose=purpose).exists():
                return True
    policy = policy or {}
    if policy.get('mode') == 'concepts' or policy.get('purpose') == 'approved_concept':
        if (ConceptRound.objects.filter(**filters).exists()
                or SectionConceptProject.objects.filter(**filters).exists()):
            return True
    return False


def requirement_lock(context, row, *, shared=False):
    data = requirement_has_data(context, row['deliverable_id'], policy=row.get('file_policy'), shared=shared)
    locked, reason = grade_configuration_lock(context)
    return {'has_data': data, 'is_locked': data or locked, 'lock_reason': DATA_REASON if data else reason}


def shared_definitions_with_locks(context):
    from defense.shared_deliverables import shared_definitions
    return [{**row, **requirement_lock(context, row, shared=True)} for row in shared_definitions(context)]


def validate_shared_changes(context, proposed):
    from django.core.exceptions import ValidationError
    from defense.shared_deliverables import shared_definitions, validate_shared_deliverables
    original = shared_definitions(context)
    normalized = validate_shared_deliverables(original, context.concept_config) or []
    proposed_by_number = {row['deliverable_id']: row for row in proposed or []}
    for row in normalized:
        if not requirement_has_data(context, row['deliverable_id'], policy=row.get('file_policy'), shared=True):
            continue
        target = proposed_by_number.get(row['deliverable_id'])
        # Display position can change when an unused requirement is removed;
        # the captured submission contract itself must stay unchanged.
        keys = set(row) | set(target or {})
        keys -= {'display_order', 'has_data', 'is_locked', 'lock_reason'}
        if target is None or any(row.get(key) != target.get(key) for key in keys):
            raise ValidationError(f'"{row["label"]}": {DATA_REASON}')


def sync_shared_requirements(context, definitions):
    """Reflect late checklist changes without rewriting any used definition/file.

    Shared upload sets capture the checklist when the first file is submitted.
    An unused sibling may still change and newly required files must reach those
    existing sets, rather than appearing only for sections that start later.
    Call only after validate_shared_changes and the grade lock have passed.
    """
    from copy import deepcopy
    from repository.section_concepts.models import SharedDeliverableSet, SectionConceptRound
    filters = context_filter(context)

    def merged(snapshot):
        used = {row['deliverable_id']: row for row in snapshot or []
                if requirement_has_data(context, row['deliverable_id'], policy=row.get('file_policy'), shared=True)}
        return [deepcopy(used.get(row['deliverable_id'], row)) for row in definitions]

    for captured in SharedDeliverableSet.objects.select_for_update().filter(**filters):
        updated = merged(captured.requirements)
        if updated != captured.requirements:
            captured.requirements = updated
            captured.save(update_fields=['requirements'])
    for hearing in SectionConceptRound.objects.select_for_update().filter(
            **{f'project__{key}': value for key, value in filters.items()}):
        updated = merged(hearing.shared_requirements_snapshot)
        if updated != hearing.shared_requirements_snapshot:
            hearing.shared_requirements_snapshot = updated
            hearing.save(update_fields=['shared_requirements_snapshot'])


@read_memoize
def context_deletion_lock(context):
    from repository.deliverables.models import ConceptRound
    from repository.section_concepts.models import SectionConceptProject, SharedDeliverableSet
    locked, reason = grade_configuration_lock(context)
    if locked:
        return locked, reason
    filters = context_filter(context)
    if (context_submissions(context).exists() or ConceptRound.objects.filter(**filters).exists()
            or SectionConceptProject.objects.filter(**filters).exists()
            or SharedDeliverableSet.objects.filter(**filters).exists()):
        return True, 'This stage has submissions or linked history and cannot be deleted.'
    return False, None
