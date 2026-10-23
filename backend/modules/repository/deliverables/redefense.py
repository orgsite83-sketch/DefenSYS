"""Prepare new evidence while preserving the files presented at earlier hearings."""
from django.core.exceptions import ValidationError
from defensys_backend.read_projection import read_memoize


def requested_set(current, decisions, outcome, replacement_required=False):
    """Rejection alone never determines the next hearing's requirements."""
    if outcome != 'for_redefense':
        return None
    if not any('next_action' in d for d in decisions):
        # Existing explicit revise/replacement requests convey the same action.
        selected_key = current.section_round.selected_key if current.section_round_id else ''
        decisions = [{**d, 'next_action': ('omit' if selected_key and d['key'] != selected_key else
            'replace' if replacement_required else 'revise' if d['decision'] == 'revise' else 'omit')}
            for d in decisions]
    actions = {d['key']: d for d in decisions}
    requested = []
    for concept in current.concepts:
        item = actions[concept['key']]
        action = item.get('next_action')
        if action not in ('revise', 'replace', 'omit'):
            raise ValidationError('Specify revise, replace, or not requested for every concept in the next hearing.')
        if action != 'omit':
            if not item.get('remarks', '').strip():
                raise ValidationError('Record the panel instructions for every requested concept.')
            requested.append({'key': concept['key'], 'action': action, 'feedback': item['remarks'].strip()})
    if not requested:
        raise ValidationError('Request at least one concept for the next hearing.')
    if current.section_round_id and current.section_round.selected_key:
        if {r['key'] for r in requested} != {current.section_round.selected_key}:
            raise ValidationError('Request only the module linked to the selected shared system for this team.')
    return requested


def snapshot_hearing(schedule, team, stage):
    if schedule and not schedule.documents_snapshot:
        from .concepts import documents_snapshot
        schedule.documents_snapshot = documents_snapshot(team, stage)
        schedule.save(update_fields=['documents_snapshot'])


def refresh_files(team, stage):
    """Only concept documents and panel materials need fresh versions.

    General accepted files retain their status; old bytes and reviews are never
    overwritten. The new round's concept keys determine the next required slots.
    """
    from .models import DeliverableSubmission, DeliverableSubmissionFile
    from .services import get_deliverable_definitions_for_team
    from .documents import sync_submission
    definitions = {d['id']: d for d in get_deliverable_definitions_for_team(team, stage.label)
                   if d['type'] == 'pre' and (d.get('is_defense_material') or
                       (d.get('file_policy') or {}).get('mode') == 'concepts')}
    for submission in DeliverableSubmission.objects.select_for_update().filter(
            team=team, stage_label=stage.label, deliverable_id__in=definitions):
        if (submission.file and not submission.files.filter(is_current=True).exists()
                and not submission.files.filter(file=submission.file.name).exists()):
            archived = DeliverableSubmissionFile.objects.create(submission=submission,
                file=submission.file.name, file_name=submission.file_name, file_size=submission.file_size,
                revision=(submission.files.order_by('-revision').values_list('revision', flat=True).first() or 0) + 1,
                status=submission.status, feedback=submission.feedback, reviewed_by=submission.reviewed_by,
                reviewed_at=submission.reviewed_at, extracted_text=submission.extracted_text,
                topics=submission.topics, summary=submission.summary, category=submission.category,
                category_confidence=submission.category_confidence, classification=submission.classification)
            DeliverableSubmissionFile.objects.filter(pk=archived.pk).update(uploaded_at=submission.uploaded_at)
        submission.files.filter(is_current=True).update(is_current=False)
        submission._prefetched_objects_cache = {}
        submission.status, submission.feedback = 'pending', ''
        submission.reviewed_by, submission.reviewed_at = None, None
        submission.file_replacement_unlocked = False
        submission.file_replacement_reason = ''
        submission.revision_review_unlocked = False
        submission.is_late = False
        sync_submission(submission, definitions[submission.deliverable_id], stage)


@read_memoize
def preparing(team, stage):
    """A previous re-defense verdict is not permission after fresh endorsement."""
    from .concepts import latest_round
    from .services import latest_stage_grade
    from student_teams.services import was_stage_endorsed
    if stage is None:
        return False
    current = latest_round(team, stage)
    if current:
        return bool(current.number > 1 and not current.schedule_id and not was_stage_endorsed(team, stage))
    grade = latest_stage_grade(team, stage.label)
    if not grade or grade.verdict != 'for_redefense':
        return False
    from student_teams.models import TeamStageProgress
    from student_teams.services import get_stage_progress
    progress = get_stage_progress(team, stage) if team.is_capstone else None
    if progress:
        return progress.status != TeamStageProgress.STATUS_READY
    return not was_stage_endorsed(team, stage)


def hearing_history(team, stage):
    """Use the same history presentation for non-concept hearings."""
    from defense.scheduler.models import DefenseSchedule
    schedules = DefenseSchedule.objects.filter(team=team, semester_id=team.semester_id,
        project_version=team.project_version, scope='capstone' if team.is_capstone else 'pit').exclude(
            documents_snapshot=[]).exclude(status='cancelled')
    schedules = schedules.filter(defense_stage=stage) if team.is_capstone else schedules.filter(event_name__iexact=stage.label)
    result = []
    for schedule in schedules.order_by('pk').prefetch_related('grade_records', 'attempt_grade_snapshots'):
        assessment = next(iter(schedule.attempt_grade_snapshots.all()), None) or next(iter(schedule.grade_records.all()), None)
        result.append({'round': getattr(assessment, 'attempt_number', getattr(assessment, 'attempt_count', len(result) + 1)),
            'schedule_id': schedule.pk, 'verdict': assessment.verdict if assessment else '',
            'remarks': assessment.verdict_remarks if assessment else '', 'concepts': [],
            'documents': schedule.documents_snapshot})
    return list(reversed(result))
