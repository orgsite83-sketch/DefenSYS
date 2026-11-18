"""Student assessment values come only from an explicitly released snapshot."""
from defensys_backend.read_projection import read_memoize

PRIVATE = {'score', 'scores', 'final_grade', 'student_scores', 'student_grades', 'peerScore',
           'students', 'peer_per_student', 'breakdowns', 'criterion_scores', 'qualifies', 'ranking',
           'rank', 'outcome_rule', 'peer_rating_evidence', 'assessment_policy'}
PUBLIC_RESULT = {'verdict', 'hearing_outcome', 'result', 'outcome', 'published_result', 'approved_title',
                 'selected_title', 'decision_remarks', 'verdict_remarks', 'revision_deadline', 'revisions_cleared_at'}
DECISION_KEYS = {'decision', 'selected_key', 'section_selected_key', 'section_selected', 'next_action',
                 'requested_action', 'panel_feedback', 'redefense_plan', 'next_attempt_direction', 'shared_selection'}
DEPENDENT_FLAGS = {'passed_and_cleared', 'revisions_pending', 'redefense_ready', 'defense_approved',
                   'repeat_preparation', 'post_defense_ready', 'post_unlocked', 'archive_unlocked', 'vault_unlocked',
                   'is_officially_complete', 'is_completed', 'is_defense_done', 'concept_revisions_cleared',
                   'section_revisions_pending', 'shared_revisions_pending', 'post_defense_complete'}
RESULT_STATUSES = {'approved', 'approved_with_revisions', 'for_redefense', 'redefense_required', 'failed',
                   'project_rejected', 'passed', 'completed', 'revisions_pending', 'pending_post_defense',
                   'awaiting_completion', 'ready_to_schedule_redefense', 'replacement_concepts_needed'}


@read_memoize
def _releases(actor_id):
    from .dissemination_models import OutcomeRelease
    result = {}
    for release in OutcomeRelease.objects.filter(recipient_ids__contains=[actor_id]).select_related('batch').order_by('-pk'):
        sid = release.snapshot['schedule_id']
        result.setdefault(sid, {**release.snapshot, 'released_at': release.created_at.isoformat(), 'release_id': release.pk})
    return result


@read_memoize
def _grade_for(team, stage):
    from .models import TeamGrade
    query = TeamGrade.all_objects.filter(team_id=team.pk, semester_id=team.semester_id,
        project_version=team.project_version, schedule__isnull=False)
    if stage is not None:
        query = query.filter(pit_event_config=stage) if team.is_pit else query.filter(defense_stage=stage)
    return query.order_by('-pk').first()


@read_memoize
def _schedule_for_grade(grade_id):
    from .models import TeamGrade
    return TeamGrade.all_objects.filter(pk=grade_id).values_list('schedule_id', flat=True).first()


@read_memoize
def _schedule_for_minutes(minutes_id):
    from defense.minutes.models import DefenseMinutes
    return DefenseMinutes.objects.filter(pk=minutes_id).values_list('schedule_id', flat=True).first()


def student_assessment_payload(value, actor, *, grade=None, team=None, stage=None, schedule=None):
    """Detach public content; missing context always withholds panel decisions.

    Histories resolve their own schedule instead of inheriting the current
    hearing's release. Document/title review is independent of panel decisions.
    """
    if getattr(actor, 'role', None) != 'student':
        return value
    releases = _releases(actor.pk) if getattr(actor, 'pk', None) else {}
    if grade is None and team is not None:
        grade = _grade_for(team, stage)
    initial_sid = getattr(schedule, 'pk', None) or getattr(grade, 'schedule_id', None)

    def public(item, sid=None, kind='', assessment=False, instruction_sid=None):
        if isinstance(item, (list, tuple)):
            return [public(child, sid, kind, assessment, instruction_sid) for child in item]
        if not isinstance(item, dict):
            return item
        sid = item.get('schedule_id', sid)
        instruction_sid = item.get('instruction_schedule_id', instruction_sid)
        minutes_document = item.get('source') == 'defense_minutes'
        if minutes_document and item.get('source_id'):
            sid = _schedule_for_minutes(item['source_id'])
        if isinstance(item.get('dissemination'), dict):
            sid = item['dissemination'].get('schedule_id', sid)
        if kind == 'schedule':
            sid = item.get('id', sid)
        if isinstance(item.get('schedule'), dict):
            sid = item['schedule'].get('id', sid)
        if isinstance(item.get('grade'), dict):
            sid = item['grade'].get('schedule_id', sid)
        if item.get('grade_id') and 'schedule_id' not in item:
            sid = _schedule_for_grade(item['grade_id'])
        if kind == 'assessments' and not sid and item.get('id'):
            sid = _schedule_for_grade(item['id'])
        assessment = assessment or bool(PUBLIC_RESULT.intersection(item)) or 'outcome_metadata' in item or kind in ('grade', 'assessment_progress', 'concept_workflow')
        released = releases.get(sid)
        instructions = releases.get(instruction_sid) or released or {}
        instruction = next((c for c in (instructions.get('redefense_plan') or {}).get('concepts', [])
                            if c.get('key') == item.get('key')), {})
        concept = next((c for c in released.get('concepts', []) if c.get('key') == item.get('key')), {}) if released else {}
        approved = next((c for c in released.get('concepts', []) if c.get('decision') in ('approved','approved_with_revisions')), {}) if released else {}
        result = {}
        for key, child in item.items():
            if key in ('peer_criteria', 'my_peer_submissions'):
                from copy import deepcopy
                result[key] = deepcopy(child)
                continue
            if key in PRIVATE or key.endswith(('_score', '_scores', '_grade')):
                continue
            if key == 'outcome_metadata':
                result[key] = {}
            elif minutes_document and key in ('file_url', 'pdf_url', 'download_url'):
                result[key] = None  # Signed minutes retain their staff-only download permission.
            elif minutes_document and key == 'project_title':
                result[key] = (released or {}).get('approved_title', '')
            elif key in ('final_paper','final_file','approved_concept_paper') and not released:
                result[key] = None
            elif key in PUBLIC_RESULT:
                source = {'hearing_outcome': 'verdict', 'outcome': 'verdict', 'published_result': 'result',
                          'selected_title': 'approved_title', 'decision_remarks': 'verdict_remarks'}.get(key, key)
                result[key] = released.get(source) if released else ('pending' if key in ('result','published_result') else '')
            elif key in DECISION_KEYS:
                if key in ('selected_key','section_selected_key'):
                    result[key] = approved.get('key', '')
                elif key == 'section_selected':
                    result[key] = bool(released and approved.get('key') == item.get('key'))
                elif key == 'shared_selection':
                    result[key] = (released or {}).get(key)
                elif key == 'redefense_plan':
                    result[key] = instructions.get(key)
                elif key == 'next_attempt_direction':
                    result[key] = None
                elif key in ('requested_action','next_action') and instruction:
                    result[key] = instruction.get('action', '')
                elif key == 'panel_feedback' and instruction:
                    result[key] = instruction.get('feedback', '')
                else:
                    result[key] = (released or {}).get('verdict', '') if key == 'decision' and not item.get('key') else concept.get(key, '')
            elif key == 'remarks' and (assessment or 'decision' in item):
                result[key] = concept.get('remarks', '') if item.get('key') else (released or {}).get('verdict_remarks', '')
            elif key in ('title', 'system_title') and concept:
                result[key] = concept.get(key, '')
            elif key in DEPENDENT_FLAGS and not released:
                result[key] = False
            elif key in ('status','state','display_status','stage_progress_status','stage_status_detail','teamStatus','team_status') and str(child).lower() in RESULT_STATUSES and not released:
                result[key] = 'awaiting_release'
            elif key in ('verdict_by_name','verdict_at','decided_at','decided_by_name','decision_at','clearance_remarks') and assessment:
                result[key] = None
            elif key == 'next_step' and not released and assessment:
                result[key] = 'Awaiting official release.'
            else:
                result[key] = public(child, sid, key, assessment and key not in ('documents','files','papers','submissions'), instruction_sid)
        if assessment:
            result['dissemination'] = {'status': 'released' if released else 'awaiting_release', 'schedule_id': sid,
                'label': 'Released' if released else 'Awaiting official release',
                'released_at': released.get('released_at') if released else None}
        return result

    return public(value, initial_sid)


def student_team_payload(value, actor, team):
    if getattr(actor, 'role', None) != 'student':
        return value
    from .dissemination import pending_for
    pending = pending_for(team)
    result = student_assessment_payload(value, actor, team=team)
    current = _grade_for(team, None)
    if current:
        result['dissemination'] = {'schedule_id': current.schedule_id,
            'status': 'released' if current.schedule_id in _releases(actor.pk) else 'awaiting_release'}
    if pending:
        evidence = pending.outcome_metadata or {}
        result['project_title'] = evidence.get('pre_release_project_title', '')
        result['status'] = evidence.get('pre_release_team_status', 'Pending')
        result['current_defense_stage'] = pending.stage_label
        result['ready_for_stage'] = None
        if isinstance(result.get('defense_context'), dict):
            result['defense_context'].update(current_stage=pending.stage_label, ready_for_stage=None)
    return result


def require_student_release(actor, team, stage=None):
    if getattr(actor, 'role', None) == 'student':
        from .dissemination import pending_for
        from django.core.exceptions import ValidationError
        if pending_for(team, stage):
            raise ValidationError('Await the official outcome release before changing defense submissions.')
