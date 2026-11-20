"""Reviewed, attempt-specific disclosure. Academic verdicts remain authoritative."""
import hashlib
import json
import uuid
from types import SimpleNamespace

from django.core import signing
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from authentication_access_control.scopes import is_admin_user, grade_records_for
from .dissemination_models import OutcomeRelease, OutcomeReleaseBatch, OutcomeReleaseControl
from .models import TeamGrade

SALT = 'grading.outcome-dissemination.v1'
STATUSES = {'awaiting_evaluation': 'Awaiting evaluation', 'awaiting_decision': 'Awaiting chair decision',
            'ready': 'Ready for release', 'held': 'On hold', 'released': 'Released',
            'updated': 'Updated - awaiting re-release', 'unavailable': 'No recorded outcome'}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str, separators=(',', ':')).encode()).hexdigest()


def require_admin(actor):
    if not is_admin_user(actor):
        raise PermissionDenied('Only an administrator can disseminate outcomes or manage holds.')


def context_for(grade):
    return dict(team_id=grade.team_id, semester_id=grade.semester_id, scope=grade.scope,
                project_version=grade.project_version, defense_stage_id=grade.defense_stage_id,
                pit_event_config_id=grade.pit_event_config_id, schedule_id=grade.schedule_id,
                attempt=grade.attempt_count, stage_label=grade.stage_label)


def context_key(grade):
    return digest(context_for(grade))


def hydrate(grades):
    """Load shared release state once per team attempt, never per student row."""
    from repository.deliverables.models import ConceptRound
    from .correction_models import GradeCorrection
    grades = list(grades)
    schedule_ids = {g.schedule_id for g in grades if g.schedule_id}
    rounds = {r.schedule_id: r for r in ConceptRound.objects.filter(schedule_id__in=schedule_ids)
              .select_related('section_round').prefetch_related('section_round__systems')}
    controls = {c.schedule_id: c for c in OutcomeReleaseControl.objects.filter(
        schedule_id__in=schedule_ids).prefetch_related('releases__batch')}
    pending = set(GradeCorrection.objects.filter(grade_id__in=[g.pk for g in grades], status='pending').values_list('grade_id', flat=True))
    for grade in grades:
        grade._release_round = rounds.get(grade.schedule_id)
        grade._release_control = controls.get(grade.schedule_id)
        grade._release_correction_pending = grade.pk in pending
    return grades


def snapshot(grade):
    if not hasattr(grade, '_release_round'):
        hydrate([grade])
    hearing = grade._release_round
    verdict = 'failed' if grade.closed_as_failed else grade.verdict or (hearing.verdict if hearing else '')
    # Only explicit public content is captured; evaluator evidence never enters this record.
    concept_fields = {'key', 'title', 'system_title', 'decision', 'remarks', 'next_action', 'requested_action', 'panel_feedback'}
    concepts = [{k: v for k, v in c.items() if k in concept_fields} for c in (hearing.concepts if hearing else [])]
    shared = None
    if hearing and hearing.section_round_id:
        section = hearing.section_round
        names = {system.key: system.title for system in section.systems.all()}
        concepts = [{**c, 'system_title': names.get(c['key'], '')} for c in concepts]
        shared = {'selected_key': section.selected_key, 'system_title': names.get(section.selected_key, ''),
                  'decision': section.verdict, 'revisions_pending': section.verdict == 'approved_with_revisions' and not section.revisions_cleared_at,
                  'module': next((c for c in concepts if c['key'] == section.selected_key), None)}
    approved = next((c for c in concepts if c.get('decision') in ('approved', 'approved_with_revisions')), None)
    notes = grade.verdict_remarks or (hearing.remarks if hearing else '')
    plan = {'source_round': hearing.number, 'concepts': [{'key': c['key'], 'action': c['next_action'],
            'feedback': c.get('remarks') or notes} for c in concepts if c.get('next_action') in ('revise','replace')]} if hearing and verdict == 'for_redefense' else None
    from .deliberation import source_for, decision_payload
    official = source_for(grade.schedule)
    return {**({'panel_decision': decision_payload(official, public=True)} if official else {}),
            **context_for(grade), 'grade_id': grade.pk, 'team_name': grade.team.name, 'verdict': verdict,
            'result': 'failed' if verdict in ('failed', 'project_rejected') else 'for_redefense' if verdict == 'for_redefense'
                else 'revisions_pending' if verdict == 'approved_with_revisions' and not grade.revisions_cleared_at else 'passed' if verdict else 'pending',
            'verdict_remarks': notes, 'shared_selection': shared, 'redefense_plan': plan,
            'approved_title': (approved or {}).get('title') or (grade.project_title_snapshot if verdict in TeamGrade.PASSING_VERDICTS else ''),
            'revision_deadline': grade.revision_deadline.isoformat() if grade.revision_deadline else None,
            'revisions_cleared_at': grade.revisions_cleared_at.isoformat() if grade.revisions_cleared_at else None,
            'concepts': concepts}


def metadata(grade, *, panel_complete=None):
    if not hasattr(grade, '_release_control'):
        hydrate([grade])
    public = snapshot(grade)
    control = grade._release_control
    releases = list(control.releases.all()) if control else []
    latest = max(releases, key=lambda r: r.pk) if releases else None
    content_hash = digest(public)
    version = digest([grade.updated_at, grade.schedule_id, grade.attempt_count, control.revision if control else 0, content_hash])
    reason = ''
    if not grade.schedule_id or grade.schedule.status == 'cancelled':
        state, reason = 'unavailable', 'A recorded, non-cancelled hearing is required.'
    elif grade._release_correction_pending:
        state, reason = 'awaiting_decision', 'An academic correction is awaiting review.'
    elif panel_complete is False:
        state, reason = 'awaiting_evaluation', 'Every required panel evaluation must be submitted.'
    elif not public['verdict']:
        state, reason = 'awaiting_decision', 'The official defense decision or concept selection is pending.'
    elif latest and latest.content_hash == content_hash:
        state = 'released'
    elif control and control.held:
        state, reason = 'held', control.hold_reason or 'This outcome is on hold.'
    else:
        state = 'updated' if latest else 'ready'
    return {'status': state, 'label': STATUSES[state], 'can_release': state in ('ready', 'updated'),
            'reason': reason, 'schedule_id': grade.schedule_id, 'attempt': grade.attempt_count,
            'version': version, 'released_at': latest.created_at.isoformat() if latest else None,
            'release_id': latest.pk if latest else None}


def recipients(grade):
    from .masterlist import _member_ids
    from django.contrib.auth import get_user_model
    ids = _member_ids(grade.team, grade.semester)
    # Retain the actual assessment roster when the mutable current team differs.
    ids |= set(grade.student_grades.values_list('student_id', flat=True))
    return sorted(get_user_model().objects.filter(pk__in=ids, role='student', is_active=True).values_list('pk', flat=True))


def reviewed_entry(grade):
    from .outcome_rules import outcome_payload
    from .services import team_grading_readiness
    rule = outcome_payload(grade)
    complete = rule['panel_complete'] if rule else team_grading_readiness(grade, grade.semester, grade.scope)['panel_complete']
    info = metadata(grade, panel_complete=complete)
    public = snapshot(grade)
    ids = recipients(grade)
    if public['revision_deadline'] and not public['revisions_cleared_at'] and grade.revision_deadline < timezone.localdate():
        info.update(can_release=False, reason='Correct the expired student deadline before dissemination.')
    return {'grade_id': grade.pk, 'context': context_for(grade), 'metadata': info, 'snapshot': public,
            'recipient_ids': ids, 'fingerprint': digest([info['version'], ids, rule.get('review_token') if rule else None,
                                                       grade.schedule.revision, grade._release_correction_pending])}


def query_request(request, params):
    if not isinstance(params, dict) or any(isinstance(v, (dict, list)) for v in params.values()):
        raise ValidationError('Choose a valid masterlist scope.')
    return SimpleNamespace(user=request.user, query_params={str(k): str(v) for k, v in params.items() if v is not None})


def scope_data(request, params):
    from .masterlist import build_masterlist
    scoped = query_request(request, params)
    data = build_masterlist(scoped, paginate=False)
    if data['context']['coverage'] != 'assessment':
        raise ValidationError('Open a specific assessment before disseminating outcomes.')
    return data


def preview(request, data):
    require_admin(request.user)
    if not isinstance(data, dict):
        raise ValidationError('Submit a release selection object.')
    params = data.get('filters', {})
    listing = scope_data(request, params)
    cells = {c['grade_id']: c for r in listing['rows'] for c in r['assessments'] if c['grade_id']}
    selected = data.get('grade_ids')
    if selected is not None and (not isinstance(selected, list) or not selected or any(type(v) is not int for v in selected)):
        raise ValidationError('Select one or more team assessments.')
    ids = set(selected) if selected is not None else set(cells)
    if not ids <= cells.keys():
        raise PermissionDenied('The selection is outside the current authorized masterlist.')
    grades = hydrate(TeamGrade.all_objects.filter(pk__in=ids).select_related('team', 'semester', 'schedule'))
    entries, excluded = [], []
    for grade in sorted(grades, key=lambda g: (g.team.name, g.pk)):
        entry = reviewed_entry(grade)
        if entry['metadata']['can_release']:
            entries.append(entry)
        else:
            excluded.append({'team_name': grade.team.name, **entry['metadata']})
    if selected is not None and excluded:
        raise ValidationError('An included outcome is not eligible. Refresh and review the selection.')
    if not entries:
        raise ValidationError('No eligible outcomes match this selection.')
    context = {k: listing['context'].get(k) for k in ('scope', 'semester_id', 'assessment_id', 'assessment_label', 'academic_period', 'year_level')}
    token_data = {'actor': request.user.pk, 'entries': [{'grade_id': e['grade_id'], 'fingerprint': e['fingerprint']} for e in entries],
                  'filters': params, 'context': context}
    return {'review_token': signing.dumps(token_data, salt=SALT, compress=True), 'context': context,
            'entries': entries, 'team_count': len(entries), 'student_count': len(set().union(*(set(e['recipient_ids']) for e in entries))),
            'excluded': excluded, 'excluded_count': len(excluded), 'selection_mode': 'selected' if selected is not None else 'matching_ready'}


def batch_payload(batch):
    releases = list(batch.releases.all())
    return {'batch_id': str(batch.pk), 'released_at': batch.created_at.isoformat(), 'actor_name': batch.actor_name,
            'context': batch.context, 'team_count': len(releases),
            'student_count': len(set().union(*(set(r.recipient_ids) for r in releases))) if releases else 0,
            'entries': [{'release_id': r.pk, 'snapshot': r.snapshot} for r in releases]}


@transaction.atomic
def confirm(request, data):
    require_admin(request.user)
    if not isinstance(data, dict) or not isinstance(data.get('review_token'), str):
        raise ValidationError('Submit the reviewed release token.')
    try:
        batch_id = uuid.UUID(str(data.get('batch_id', '')))
        token = signing.loads(data.get('review_token', ''), salt=SALT)
    except (ValueError, TypeError, signing.BadSignature):
        raise ValidationError('This review expired or is invalid. Review the outcomes again.')
    if token['actor'] != request.user.pk:
        raise PermissionDenied('This review belongs to a different administrator.')
    request_hash = digest(token)
    existing = OutcomeReleaseBatch.objects.filter(pk=batch_id).first()
    if existing:
        if existing.actor_id != request.user.pk or existing.request_hash != request_hash:
            raise ValidationError('This request identity belongs to a different release.')
        return batch_payload(existing)
    try:
        signing.loads(data['review_token'], salt=SALT, max_age=600)
    except signing.BadSignature:
        raise ValidationError('This review expired. Review the outcomes again.')
    ids = [entry['grade_id'] for entry in token['entries']]
    visible = grade_records_for(request.user, include_previous_projects=True).filter(pk__in=ids)
    if set(visible.values_list('pk', flat=True)) != set(ids):
        raise PermissionDenied('An included assessment is no longer authorized.')
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    targets = list(visible.values('team_id', 'schedule_id'))
    list(StudentTeam.objects.select_for_update().filter(pk__in=[r['team_id'] for r in targets]).order_by('pk'))
    list(DefenseSchedule.objects.select_for_update().filter(pk__in=[r['schedule_id'] for r in targets]).order_by('pk'))
    grades = hydrate(TeamGrade.all_objects.select_for_update(of=('self',)).filter(pk__in=ids).select_related('team', 'semester', 'schedule').order_by('pk'))
    # A retry waiting on the same academic locks observes the committed first request.
    existing = OutcomeReleaseBatch.objects.filter(pk=batch_id).first()
    if existing:
        if existing.actor_id != request.user.pk or existing.request_hash != request_hash:
            raise ValidationError('This request identity belongs to a different release.')
        return batch_payload(existing)
    expected = {entry['grade_id']: entry['fingerprint'] for entry in token['entries']}
    current = [reviewed_entry(g) for g in grades]
    if len(current) != len(ids) or any(not e['metadata']['can_release'] or e['fingerprint'] != expected[e['grade_id']] for e in current):
        raise ValidationError('An included outcome changed. Refresh and review the current selection.')
    batch = OutcomeReleaseBatch.objects.create(id=batch_id, actor=request.user,
        actor_name=request.user.get_full_name() or request.user.username, request_hash=request_hash, context=token['context'])
    from .defense_workflow import audit
    from notifications.services import notify_team_students
    for grade, entry in zip(grades, current):
        control, _ = OutcomeReleaseControl.objects.get_or_create(context_key=context_key(grade),
            defaults={'schedule_id': grade.schedule_id, 'context': context_for(grade)})
        release = OutcomeRelease.objects.create(control=control, batch=batch, content_hash=digest(entry['snapshot']),
            snapshot=entry['snapshot'], recipient_ids=entry['recipient_ids'],
            version=(control.releases.order_by('-version').values_list('version', flat=True).first() or 0) + 1)
        activate_student_work(grade, control, entry['snapshot']['verdict'])
        audit(grade, request.user, 'defense.outcome_disseminated', batch_id=str(batch.pk), release_id=release.pk,
              schedule_id=grade.schedule_id, attempt=grade.attempt_count, recipient_ids=entry['recipient_ids'])
        notify_team_students(grade.team, title='Defense outcome released',
            message='Your defense outcome and panel feedback are now available.', category='DEFENSE', sender=request.user,
            stage_label=grade.stage_label, action_payload={'schedule_id': grade.schedule_id, 'release_id': release.pk},
            event_key=f'defense.outcome_released:{release.pk}', recipient_ids=entry['recipient_ids'])
    from .automatic_outcomes import notify_assessment
    for grade in grades:
        transaction.on_commit(lambda grade=grade: notify_assessment(grade))
    return batch_payload(batch)


@transaction.atomic
def hold(request, grade_id, data):
    require_admin(request.user)
    if not isinstance(data, dict):
        raise ValidationError('Submit a hold action object.')
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    visible = grade_records_for(request.user, include_previous_projects=True)
    first = visible.filter(pk=grade_id).first()
    if not first:
        raise PermissionDenied('This assessment is outside your workspace.')
    StudentTeam.objects.select_for_update().get(pk=first.team_id)
    if first.schedule_id:
        DefenseSchedule.objects.select_for_update().get(pk=first.schedule_id)
    grade = hydrate([TeamGrade.all_objects.select_for_update(of=('self',)).select_related('schedule', 'team', 'semester').get(pk=grade_id)])[0]
    info = metadata(grade)
    if data.get('version') != info['version'] or data.get('schedule_id') != grade.schedule_id or not grade.schedule_id:
        raise ValidationError('The defense attempt changed. Refresh before changing its hold.')
    if type(data.get('held')) is not bool:
        raise ValidationError('Choose whether to place or remove the hold.')
    if info['status'] == 'released' or (data['held'] and not info['can_release']):
        raise ValidationError('Only an eligible unreleased outcome can be placed on hold.')
    reason = data.get('reason', '')
    if not isinstance(reason, str) or len(reason) > 1000:
        raise ValidationError('Enter a hold reason of at most 1000 characters.')
    control, _ = OutcomeReleaseControl.objects.get_or_create(context_key=context_key(grade),
        defaults={'schedule_id': grade.schedule_id, 'context': context_for(grade)})
    control.held, control.hold_reason = data['held'], reason.strip() if data['held'] else ''
    control.changed_by, control.revision = request.user, control.revision + 1
    control.save()
    from .defense_workflow import audit
    audit(grade, request.user, 'defense.outcome_hold_changed', held=control.held, reason=control.hold_reason, schedule_id=grade.schedule_id)
    hydrate([grade])
    return metadata(grade)


def activate_student_work(grade, control, verdict):
    """Activate the already prepared round; never rebuild grading or file history."""
    if verdict != 'for_redefense' or control.context.get('student_work_activated'):
        return
    from repository.deliverables.redefense import refresh_files
    from repository.deliverables.concepts import context_for_grade
    refresh_files(grade.team, context_for_grade(grade), activate=True)
    control.context = {**control.context, 'student_work_activated': True}
    control.save(update_fields=['context'])


def latest_release(schedule_id, actor=None):
    if not schedule_id:
        return None
    query = OutcomeRelease.objects.filter(control__context__schedule_id=schedule_id).select_related('batch')
    if actor is not None:
        query = query.filter(recipient_ids__contains=[actor.pk])
    return query.order_by('-pk').first()


def pending_for(team, stage=None):
    """Return a recorded, unreleased current result; used by student action gates."""
    from django.db.models import Q
    from repository.deliverables.models import ConceptRound
    concept_results = ConceptRound.objects.filter(team_id=team.pk, project_version=team.project_version).filter(
        ~Q(verdict='') | (Q(section_round__isnull=False) & ~Q(section_round__verdict=''))).values('schedule_id')
    query = TeamGrade.all_objects.filter(team_id=team.pk, semester_id=team.semester_id,
        project_version=team.project_version, schedule__isnull=False).filter(~Q(verdict='') | Q(schedule_id__in=concept_results))
    if stage is not None:
        query = query.filter(pit_event_config=stage) if team.is_pit else query.filter(defense_stage=stage)
    grades = hydrate(query.select_related('team', 'semester', 'schedule').order_by('-pk'))
    return next((g for g in grades if not latest_release(g.schedule_id)), None)
