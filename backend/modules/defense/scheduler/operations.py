"""Atomic operational changes. Every write rechecks scope, revision, and evidence."""
from datetime import datetime, timedelta

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from rest_framework import serializers
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.scopes import visible_schedules_for
from .models import DefenseSchedule, SchedulePanelist
from .services import deletion_blockers, delete_schedule, schedule_audit_values


class StaleOperation(APIException):
    status_code = 409
    default_detail = 'These records changed. Refresh and review the selection before saving.'


class OperationSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['preview_delete', 'preview_update', 'delete', 'update'])
    target = serializers.ChoiceField(choices=['schedule', 'session', 'stage', 'selected', 'stage_selected', 'semester', 'management_selected'], default='schedule')
    anchor_id = serializers.IntegerField(min_value=1)
    schedule_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), required=False, max_length=5000)
    expected_revisions = serializers.DictField(child=serializers.IntegerField(min_value=1), required=False)
    empty_only = serializers.BooleanField(default=False)
    reason = serializers.CharField(required=False, max_length=2000, min_length=5)
    changes = serializers.DictField(required=False)


def selection(actor, data):
    visible = visible_schedules_for(actor)
    anchor = visible.filter(pk=data['anchor_id']).first()
    if not anchor:
        raise PermissionDenied('This defense is outside your management scope.')
    # A visible record is not, by itself, permission to mutate it.
    if not (actor.role == 'admin' or actor.is_superuser or (actor.is_pit_lead and anchor.scope == 'pit')):
        raise PermissionDenied('Only administrators and scoped PIT leads can manage schedules.')
    items = visible.filter(semester_id=anchor.semester_id, scope=anchor.scope)
    if data['target'] in ('semester', 'management_selected'):
        from academic_period_management.services import active_semester
        active = active_semester()
        if not active or active.pk != anchor.semester_id:
            raise ValidationError('Schedule management is limited to the active semester.')
        if data['target'] == 'management_selected':
            ids = set(data.get('schedule_ids') or [])
            items = items.filter(pk__in=ids)
            if not ids or set(items.values_list('pk', flat=True)) != ids:
                raise PermissionDenied('Choose defenses from this defense type, the active semester, and your management scope.')
    elif data['target'] == 'session':
        items = items.filter(session_id=anchor.session_id)
    elif data['target'] in ('stage', 'stage_selected'):
        from academic_period_management.services import active_semester
        active = active_semester()
        if not active or active.pk != anchor.semester_id:
            raise ValidationError('Stage-wide operations are limited to the active semester.')
        if anchor.scope == 'capstone' and not anchor.defense_stage_id:
            raise ValidationError('Choose a schedule with a configured defense stage.')
        if anchor.scope == 'pit' and not anchor.event_name.strip():
            raise ValidationError('Choose a schedule with a named PIT event.')
        items = items.filter(defense_stage_id=anchor.defense_stage_id) if anchor.scope == 'capstone' else items.filter(event_name__iexact=anchor.event_name)
        if data['target'] == 'stage_selected':
            ids = set(data.get('schedule_ids') or [])
            items = items.filter(pk__in=ids)
            if not ids or set(items.values_list('pk', flat=True)) != ids:
                raise PermissionDenied('Choose schedules from this stage, the active semester, and your management scope.')
    elif data['target'] == 'selected':
        ids = set(data.get('schedule_ids') or [])
        items = items.filter(session_id=anchor.session_id, pk__in=ids)
        if not ids or set(items.values_list('pk', flat=True)) != ids:
            raise PermissionDenied('Choose schedules from this session and your management scope.')
    else:
        items = items.filter(pk=anchor.pk)
    ids = list(items.values_list('pk', flat=True))
    # Avoid SELECT FOR UPDATE on nullable outer joins from visibility helpers.
    return list(DefenseSchedule.objects.select_for_update().filter(pk__in=ids).order_by('pk'))


def check_revisions(items, expected):
    actual = {str(s.pk): s.revision for s in items}
    if actual != expected:
        raise StaleOperation()


def deletion_preview(items):
    from grading.grades.corrections import protected_grade
    entries = []
    for schedule in items:
        blockers = deletion_blockers(schedule)
        minutes = getattr(schedule, 'minutes', None)
        submitted = schedule.panelist_grade_submissions.filter(is_void=False)
        guest_ids = set(submitted.exclude(guest_code_id=None).values_list('guest_code_id', flat=True))
        panels = list(schedule.panel_assignments.select_related('panelist').order_by('order', 'pk'))
        entries.append({'id': schedule.pk, 'team_name': schedule.team.name, 'date': str(schedule.scheduled_date),
                        'start_time': str(schedule.start_time), 'status': schedule.status,
                        'room': schedule.room, 'operation_state': schedule.operation_state, 'session_id': str(schedule.session_id),
                        'scope': schedule.scope, 'semester_id': schedule.semester_id,
                        'defense_stage_id': schedule.defense_stage_id, 'stage_label': schedule.stage_label,
                        'section': schedule.team.section, 'year_level': schedule.team.year_level,
                        'chair_panelist_id': next((p.panelist_id for p in panels if p.is_chair), None),
                        'revision': schedule.revision,
                        'can_edit': schedule.status not in ('done', 'archived') and not any(protected_grade(g) for g in schedule.grade_records.all()),
                        'can_reschedule': not schedule.panelist_grade_submissions.exists(),
                        'adviser_id': schedule.team.adviser_id,
                        'documenter_id': schedule.documenter_id,
                        'documenter_name': (schedule.documenter.get_full_name() or schedule.documenter.username) if schedule.documenter else 'Unassigned',
                        'panelist_ids': [p.panelist_id for p in panels],
                        'panelist_names': [p.panelist.get_full_name() or p.panelist.username for p in panels],
                        'chair_name': next((p.panelist.get_full_name() or p.panelist.username for p in panels if p.is_chair), 'Unassigned'),
                        'external_evaluator_ids': list(schedule.guest_invitations.filter(is_active=True, evaluator_id__isnull=False).values_list('evaluator_id', flat=True)),
                        'external_evaluator_names': list(schedule.guest_invitations.filter(is_active=True, evaluator_id__isnull=False).values_list('guest_name', flat=True)),
                        'submitted_panelist_ids': list(submitted.exclude(panelist_id=None).values_list('panelist_id', flat=True).distinct()),
                        'submitted_external_evaluator_ids': [i.evaluator_id for i in schedule.guest_invitations.all() if str(i.pk) in guest_ids and i.evaluator_id],
                        'minutes_status': getattr(minutes, 'status', None),
                        'minutes_requires_amendment': bool(minutes and (minutes.status != 'draft' or minutes.pdf_file)),
                        'blockers': blockers, 'can_delete': not blockers})
    return {'entries': entries, 'total': len(entries), 'empty': sum(e['can_delete'] for e in entries),
            'protected': sum(not e['can_delete'] for e in entries),
            'expected_revisions': {str(s.pk): s.revision for s in items}}


def join_matching_session(schedule):
    """Reuse the established session when separately importing matching slots."""
    panel_ids = set(schedule.panel_assignments.values_list('panelist_id', flat=True))
    external_ids = set(schedule.guest_invitations.values_list('evaluator_id', flat=True))
    candidates = DefenseSchedule.objects.filter(
        semester_id=schedule.semester_id, scope=schedule.scope, defense_stage_id=schedule.defense_stage_id,
        event_name=schedule.event_name, scheduled_date=schedule.scheduled_date, room=schedule.room,
        documenter_id=schedule.documenter_id,
    ).exclude(pk=schedule.pk).order_by('pk')
    for candidate in candidates:
        if (set(candidate.panel_assignments.values_list('panelist_id', flat=True)) == panel_ids
                and set(candidate.guest_invitations.values_list('evaluator_id', flat=True)) == external_ids):
            schedule.session_id = candidate.session_id
            DefenseSchedule.objects.filter(pk=schedule.pk).update(session_id=candidate.session_id)
            break


def operation_values(schedule):
    return schedule_audit_values(schedule, status=schedule.status, revision=schedule.revision, slot_duration=schedule.slot_duration,
        operation_state=schedule.operation_state, operation_reason=schedule.operation_reason,
        panelist_ids=list(schedule.panel_assignments.order_by('order').values_list('panelist_id', flat=True)),
        chair_panelist_id=schedule.panel_assignments.filter(is_chair=True).values_list('panelist_id', flat=True).first(),
        documenter_id=schedule.documenter_id,
        external_evaluator_ids=list(schedule.guest_invitations.filter(is_active=True, evaluator_id__isnull=False).values_list('evaluator_id', flat=True)))


CHANGE_LABELS = {'panelist_ids': 'Faculty panel', 'chair_panelist_id': 'Panel chair',
    'external_evaluator_ids': 'External evaluators', 'documenter_id': 'Documenter',
    'scheduled_date': 'Date', 'start_time': 'Start time', 'slot_duration': 'Duration',
    'room': 'Room', 'status': 'Status', 'operation_state': 'Defense activity'}


def change_details(before, after):
    """Readable review and history use the same persisted before/after fields."""
    users = get_user_model()
    from user_management.models import ExternalEvaluator
    def display(field, value):
        if field in ('panelist_ids', 'chair_panelist_id', 'documenter_id', 'external_evaluator_ids'):
            ids = value if isinstance(value, list) else [value] if value else []
            model = ExternalEvaluator if field == 'external_evaluator_ids' else users
            people = {p.pk: p for p in model.objects.filter(pk__in=ids)}
            names = []
            for pk in ids:
                person = people.get(pk)
                if person is None:
                    names.append(f'Previously assigned person ({pk})')
                elif field == 'external_evaluator_ids':
                    names.append(person.name)
                else:
                    names.append(person.get_full_name() or person.username)
            return ', '.join(names) or 'Unassigned'
        return str(value or '').replace('_', ' ').capitalize() if field in ('status', 'operation_state') else str(value or '')
    return [{'field': field, 'label': label, 'before': display(field, before.get(field)),
             'after': display(field, after.get(field)),
             'added_ids': sorted(set(after.get(field) or []) - set(before.get(field) or [])) if field.endswith('_ids') else [],
             'removed_ids': sorted(set(before.get(field) or []) - set(after.get(field) or [])) if field.endswith('_ids') else []}
            for field, label in CHANGE_LABELS.items() if before.get(field) != after.get(field)]


def normalize_intent(raw, *, external=False):
    if not isinstance(raw, dict):
        raise ValidationError('Choose a supported panel change.')
    allowed = {'action', 'panelist_ids', 'panelist_id', 'replacement_id', 'chair_panelist_id'}
    if set(raw) - allowed:
        raise ValidationError('Unsupported panel change fields.')
    action = serializers.ChoiceField(choices=['add', 'remove', 'replace'] if external else ['add', 'remove', 'replace', 'chair']).run_validation(raw.get('action'))
    result = {'action': action}
    if action == 'add':
        result['panelist_ids'] = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=30).run_validation(raw.get('panelist_ids'))
        if len(result['panelist_ids']) != len(set(result['panelist_ids'])):
            raise ValidationError('Duplicate evaluators are not allowed.')
    if action in ('remove', 'replace'):
        result['panelist_id'] = serializers.IntegerField(min_value=1).run_validation(raw.get('panelist_id'))
    if action == 'replace':
        result['replacement_id'] = serializers.IntegerField(min_value=1).run_validation(raw.get('replacement_id'))
        if result['replacement_id'] == result['panelist_id']:
            raise ValidationError('Choose a different replacement panelist.')
    if action == 'chair' or 'chair_panelist_id' in raw:
        result['chair_panelist_id'] = serializers.IntegerField(min_value=1).run_validation(raw.get('chair_panelist_id'))
    return result


def apply_intent(ids, chair, intent):
    """Apply a relative roster change independently to each defense."""
    result = list(ids)
    action = intent['action']
    if action == 'add':
        result.extend(pk for pk in intent['panelist_ids'] if pk not in result)
        if chair is None and result:
            chair = result[0]
    elif action in ('remove', 'replace'):
        departing = intent['panelist_id']
        if departing in result:
            index = result.index(departing)
            result.remove(departing)
            if action == 'replace':
                replacement = intent['replacement_id']
                if replacement not in result:
                    result.insert(index, replacement)
                if chair == departing:
                    chair = replacement
    if 'chair_panelist_id' in intent:
        chair = intent['chair_panelist_id']
    if not result:
        chair = None
    return result, chair


def _interval(schedule):
    start = datetime.combine(schedule.scheduled_date, schedule.start_time)
    return start, start + timedelta(minutes=schedule.slot_duration)


def _overlap(a, b):
    start, end = _interval(a)
    other_start, other_end = _interval(b)
    return start < other_end and other_start < end


def _validate_conflicts(items, new_panels, externals):
    selected = {s.pk for s in items}
    dates = {s.scheduled_date + timedelta(days=offset) for s in items for offset in (-1, 0, 1)}
    others = list(DefenseSchedule.objects.filter(scheduled_date__in=dates, status='scheduled').exclude(pk__in=selected))
    for schedule in items:
        pids = set(new_panels.get(schedule.pk, schedule.panel_assignments.values_list('panelist_id', flat=True)))
        eids = set(externals.get(schedule.pk, schedule.guest_invitations.filter(is_active=True).values_list('evaluator_id', flat=True)))
        for other in others + [s for s in items if s.pk != schedule.pk]:
            if schedule.status != 'scheduled' or other.status != 'scheduled' or not _overlap(schedule, other):
                continue
            if schedule.room.casefold() == other.room.casefold():
                raise ValidationError(f'{schedule.team.name}: room overlaps another defense.')
            opids = set(new_panels.get(other.pk, other.panel_assignments.values_list('panelist_id', flat=True)))
            oeids = set(externals.get(other.pk, other.guest_invitations.filter(is_active=True).values_list('evaluator_id', flat=True)))
            other_people = opids | ({other.documenter_id} if other.documenter_id else set())
            people = pids | ({schedule.documenter_id} if schedule.documenter_id else set())
            if people & other_people or eids & oeids:
                raise ValidationError(f'{schedule.team.name}: an assigned evaluator or documenter has another defense at this time.')


@transaction.atomic
def execute_operation(actor, data, request=None):
    items = selection(actor, data)
    if data['action'] == 'preview_delete':
        return deletion_preview(items)
    if not data.get('reason'):
        raise ValidationError({'reason': 'Enter a meaningful reason for this change.'})
    check_revisions(items, data.get('expected_revisions'))
    if data['action'] == 'delete':
        preview = deletion_preview(items)
        if preview['protected'] and not data['empty_only']:
            raise StaleOperation('Some schedules contain recorded defense activity. Review the protected entries or explicitly choose eligible schedules only.')
        eligible = {e['id'] for e in preview['entries'] if e['can_delete']}
        if not eligible:
            raise ValidationError('No schedules without recorded defense activity are eligible for deletion.')
        for schedule in items:
            if schedule.pk in eligible:
                delete_schedule(schedule, actor=actor, request=request, reason=data['reason'])
        return {'deleted': len(eligible), 'protected': preview['protected']}
    changes = data.get('changes') or {}
    allowed = {'panelist_ids', 'chair_panelist_id', 'panel_change', 'external_change', 'documenter_id', 'external_evaluator_ids', 'scheduled_date', 'start_time', 'shift_minutes', 'slot_duration', 'room', 'operation_state', 'status', 'acknowledge_minutes_amendment'}
    if not (set(changes) - {'acknowledge_minutes_amendment'}) or set(changes) - allowed:
        raise ValidationError('Select supported assignment, timetable, or operation changes.')
    for name in ('panelist_ids', 'external_evaluator_ids'):
        if name in changes:
            changes[name] = serializers.ListField(child=serializers.IntegerField(min_value=1), max_length=30).run_validation(changes[name])
            if len(set(changes[name])) != len(changes[name]):
                raise ValidationError('Duplicate evaluators are not allowed.')
    for name in ('chair_panelist_id', 'documenter_id'):
        if name in changes:
            changes[name] = serializers.IntegerField(min_value=1, allow_null=True).run_validation(changes[name])
    from .serializers import ScheduleBaseSerializer
    helper = ScheduleBaseSerializer(context={'request': request})
    from user_management.external_evaluators import resolve_evaluators, create_invitations
    old_values = {s.pk: operation_values(s) for s in items}
    panel_intent = normalize_intent(changes['panel_change']) if 'panel_change' in changes else None
    external_intent = normalize_intent(changes['external_change'], external=True) if 'external_change' in changes else None
    if panel_intent and set(changes) & {'panelist_ids', 'chair_panelist_id'} or external_intent and 'external_evaluator_ids' in changes:
        raise ValidationError('Choose either a relative roster change or a complete roster, not both.')
    for intent, external_pool in ((panel_intent, False), (external_intent, True)):
        if intent:
            incoming = intent.get('panelist_ids', []) if intent['action'] == 'add' else [intent['replacement_id']] if intent['action'] == 'replace' else []
            if incoming:
                resolve_evaluators(incoming, actor) if external_pool else helper._resolve_panelists(incoming)
    global_panels = helper._resolve_panelists(changes['panelist_ids']) if 'panelist_ids' in changes else None
    global_external = resolve_evaluators(changes['external_evaluator_ids'], actor) if 'external_evaluator_ids' in changes else None
    panel_map, external_map, chairs, after_values, diffs = {}, {}, {}, {}, {}
    panel_objects, external_objects = {}, {}
    for schedule in items:
        old = old_values[schedule.pk]
        pids = [p.pk for p in global_panels] if global_panels is not None else old['panelist_ids']
        chair = changes.get('chair_panelist_id', old['chair_panelist_id'])
        if panel_intent:
            pids, chair = apply_intent(pids, chair, panel_intent)
        eids = [p.pk for p in global_external] if global_external is not None else old['external_evaluator_ids']
        if external_intent:
            eids, _ = apply_intent(eids, None, external_intent)
        panel_map[schedule.pk], external_map[schedule.pk], chairs[schedule.pk] = pids, eids, chair
        if len(pids) > 30 or len(eids) > 30:
            raise ValidationError('A defense cannot have more than 30 faculty or external evaluators.')
        if panel_intent or global_panels is not None:
            people = {p.pk: p for p in get_user_model().objects.filter(pk__in=pids)}
            panel_objects[schedule.pk] = [people[pk] for pk in pids]
        if external_intent or global_external is not None:
            from user_management.models import ExternalEvaluator
            people = {p.pk: p for p in ExternalEvaluator.objects.filter(pk__in=eids)}
            external_objects[schedule.pk] = [people[pk] for pk in eids]
    for schedule in items:
        panels = panel_objects.get(schedule.pk)
        external = external_objects.get(schedule.pk)
        pids, eids, chair = panel_map[schedule.pk], external_map[schedule.pk], chairs[schedule.pk]
        if schedule.status in ('done', 'archived'):
            raise ValidationError('Completed or archived defenses require an amendment; operational edits are closed.')
        from grading.grades.corrections import protected_grade
        if any(protected_grade(grade) for grade in schedule.grade_records.all()):
            raise ValidationError('Published or officially completed defenses require a grade amendment; operational edits are closed.')
        doc_id = changes.get('documenter_id', schedule.documenter_id)
        if doc_id is not None:
            doc = get_user_model().objects.filter(pk=doc_id, is_active=True, role__in=['faculty', 'admin']).first()
            if not doc or schedule.scope == 'pit' or doc_id == schedule.team.adviser_id or doc_id in pids:
                raise ValidationError('Choose an eligible documenter distinct from the adviser and panelists.')
        if schedule.team.adviser_id in pids:
            raise ValidationError('A team adviser cannot serve on its defense panel.')
        legacy_remaining = 'external_evaluator_ids' not in changes and schedule.guest_invitations.filter(is_active=True, evaluator_id__isnull=True).exists()
        if (panels is not None or external is not None) and not pids and not eids and not legacy_remaining:
            raise ValidationError('At least one evaluator must remain assigned.')
        removed = set(schedule.panel_assignments.values_list('panelist_id', flat=True)) - set(pids)
        if schedule.panelist_grade_submissions.filter(panelist_id__in=removed, is_void=False).exists():
            raise ValidationError('A departing panelist has submitted an evaluation. Keep their assignment, or void the evaluation with a separate recorded reason first.')
        if eids is not None:
            invitations = schedule.guest_invitations.exclude(evaluator_id__in=eids)
            if external_intent:
                invitations = invitations.filter(evaluator_id__isnull=False)
            if schedule.panelist_grade_submissions.filter(guest_code_id__in=[str(i.pk) for i in invitations], is_void=False).exists():
                raise ValidationError('A departing external evaluator has submitted. Preserve their assignment or void their evaluation first.')
        if (panels is not None or 'chair_panelist_id' in changes) and pids and chair not in pids:
            raise ValidationError('Choose a chair from the resulting faculty panel.')
        from defense.minutes.models import DefenseMinutes
        minutes = DefenseMinutes.objects.filter(schedule=schedule).first()
        roster_changed = (set(pids) != set(old_values[schedule.pk]['panelist_ids']) or chair != old_values[schedule.pk]['chair_panelist_id'] or doc_id != schedule.documenter_id
                          or (eids is not None and set(eids) != set(old_values[schedule.pk]['external_evaluator_ids'])))
        for name in ('scheduled_date', 'start_time', 'slot_duration', 'room'):
            if name in changes:
                setattr(schedule, name, changes[name])
        if isinstance(schedule.scheduled_date, str):
            schedule.scheduled_date = serializers.DateField().run_validation(schedule.scheduled_date)
        if isinstance(schedule.start_time, str):
            schedule.start_time = serializers.TimeField().run_validation(schedule.start_time)
        if 'shift_minutes' in changes:
            offset = serializers.IntegerField(min_value=-1440, max_value=1440).run_validation(changes['shift_minutes'])
            shifted = datetime.combine(schedule.scheduled_date, schedule.start_time) + timedelta(minutes=offset)
            schedule.scheduled_date, schedule.start_time = shifted.date(), shifted.time()
        schedule.slot_duration = serializers.IntegerField(min_value=15, max_value=480).run_validation(schedule.slot_duration)
        schedule.room = serializers.CharField(max_length=120).run_validation(schedule.room)
        if 'operation_state' in changes:
            schedule.operation_state = serializers.ChoiceField(choices=['normal', 'paused', 'postponed', 'no_show']).run_validation(changes['operation_state'])
            schedule.operation_reason = data['reason']
        if 'status' in changes:
            from .services import VALID_TRANSITIONS
            new_status = changes['status']
            if new_status != schedule.status and new_status not in VALID_TRANSITIONS.get(schedule.status, []):
                raise ValidationError('This status transition is not allowed.')
            if new_status == 'done':
                from grading.grades.services import team_grading_readiness
                grade = schedule.grade_records.first()
                if not grade or not team_grading_readiness(grade, grade.semester, grade.scope)['ready']:
                    raise ValidationError('Complete all required evaluations before marking this defense done.')
            schedule.status = new_status
        schedule.documenter_id = doc_id
        after_values[schedule.pk] = {**operation_values(schedule), 'panelist_ids': pids,
            'chair_panelist_id': chair, 'external_evaluator_ids': eids}
        diffs[schedule.pk] = change_details(old_values[schedule.pk], after_values[schedule.pk])
        timetable_changed = any(d['field'] in ('scheduled_date', 'start_time', 'slot_duration', 'room') for d in diffs[schedule.pk])
        if minutes and (roster_changed or timetable_changed) and (minutes.status != 'draft' or minutes.pdf_file):
            if changes.get('acknowledge_minutes_amendment') is not True or not (actor.role == 'admin' or actor.is_superuser):
                raise ValidationError('Acknowledge a document amendment to preserve the signed version and restart its signatures.')
        if timetable_changed and schedule.panelist_grade_submissions.exists():
            raise ValidationError('This defense has recorded evaluations. Pause/resume it without rewriting its original timetable.')
    _validate_conflicts(items, panel_map, external_map)
    review = {'entries': [{'id': s.pk, 'team_name': s.team.name, 'changes': diffs[s.pk],
        'will_change': bool(diffs[s.pk])} for s in items],
        'updated': sum(bool(diffs[s.pk]) for s in items),
        'unchanged': sum(not diffs[s.pk] for s in items)}
    if data['action'] == 'preview_update':
        return review
    changed_items = [s for s in items if diffs[s.pk]]
    if not changed_items:
        return review
    for schedule in changed_items:
        panels = panel_objects.get(schedule.pk)
        external = external_objects.get(schedule.pk)
        eids = external_map[schedule.pk]
        chair = chairs[schedule.pk]
        if schedule.documenter_id:
            helper._ensure_documenter_role(get_user_model().objects.get(pk=schedule.documenter_id), changed_by=actor)
        from defense.minutes.models import DefenseMinutes, DefenseMinutesRevision, MinutesPanelistComment
        minutes = DefenseMinutes.objects.select_for_update().filter(schedule=schedule).first()
        if minutes and (minutes.status != 'draft' or minutes.pdf_file) and changes.get('acknowledge_minutes_amendment') is True and any(d['field'] not in ('status', 'operation_state') for d in diffs[schedule.pk]):
            signed_snapshot = {name: str(getattr(minutes, name)) if getattr(minutes, name) is not None else None
                for name in ('status', 'team_name', 'project_title', 'adviser_name', 'defense_stage_label', 'defense_date', 'defense_time', 'room', 'documenter_name',
                             'documenter_signed_at', 'documenter_signed_by_id', 'adviser_signed_at', 'adviser_signed_by_id', 'chairman_signed_at', 'chairman_signed_by_id')}
            signed_snapshot['comments'] = list(minutes.panelist_comments.values('panelist_id', 'panelist_name_snapshot', 'panelist_role_snapshot', 'comments'))
            signed_snapshot['panelist_ids'] = old_values[schedule.pk]['panelist_ids']
            signed_snapshot['external_evaluator_ids'] = old_values[schedule.pk]['external_evaluator_ids']
            revision = DefenseMinutesRevision.objects.create(minutes=minutes, snapshot=signed_snapshot,
                pdf_file=minutes.pdf_file.name if minutes.pdf_file else None, reason=data['reason'], actor=actor)
            minutes.status = 'draft'
            for role in ('documenter', 'adviser', 'chairman'):
                setattr(minutes, f'{role}_signed_at', None)
                setattr(minutes, f'{role}_signed_by', None)
            minutes.pdf_file = None
            minutes.save()
            log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING, action='minutes.amendment_started', target=minutes,
                old_values=signed_snapshot, new_values={'retained_revision_id': revision.pk, 'status': 'draft'},
                reason=data['reason'], actor=actor, request=request, strict=True)
        if panels is not None:
            helper._ensure_panelist_roles(panels, changed_by=actor)
            schedule.panel_assignments.all().delete()
            SchedulePanelist.objects.bulk_create([SchedulePanelist(schedule=schedule, panelist=p, order=n, is_chair=p.pk == chair) for n, p in enumerate(panels)])
        elif 'chair_panelist_id' in changes:
            schedule.panel_assignments.update(is_chair=False)
            schedule.panel_assignments.filter(panelist_id=changes['chair_panelist_id']).update(is_chair=True)
        # New documenter cannot destroy earlier signatures or PDFs.
        schedule.revision += 1
        schedule.save()
        minutes = DefenseMinutes.objects.filter(schedule=schedule, status='draft').first()
        if minutes:
            minutes.documenter_name = schedule.documenter.get_full_name() if schedule.documenter else ''
            minutes.defense_date, minutes.defense_time, minutes.room = schedule.scheduled_date, schedule.start_time, schedule.room
            minutes.save()
            # Historical comments stay attributed to their original author.
            for assignment in schedule.panel_assignments.select_related('panelist'):
                MinutesPanelistComment.objects.get_or_create(minutes=minutes, panelist=assignment.panelist,
                    defaults={'panelist_name_snapshot': assignment.panelist.get_full_name() or assignment.panelist.username,
                              'panelist_role_snapshot': 'Chair' if assignment.is_chair else 'Panel Member', 'display_order': assignment.order})
        if external is not None:
            departing_invitations = schedule.guest_invitations.exclude(evaluator_id__in=eids)
            if external_intent:
                departing_invitations = departing_invitations.filter(evaluator_id__isnull=False)
            for invitation in list(departing_invitations):
                invitation.schedules.remove(schedule)
                if invitation.defense_schedule_id == schedule.pk:
                    invitation.defense_schedule = invitation.schedules.first()
                invitation.access_version += 1
                if not invitation.schedules.exists() and not invitation.defense_schedule_id:
                    invitation.is_active = False
                invitation.save()
    evaluator_pool = {e.pk: e for people in external_objects.values() for e in people}
    if evaluator_pool:
        for evaluator in evaluator_pool.values():
            missing = [schedule for schedule in changed_items if evaluator.pk in external_map[schedule.pk] and not schedule.guest_invitations.filter(is_active=True, evaluator=evaluator).exists()]
            if missing:
                create_invitations([evaluator], missing, actor)
    for schedule in changed_items:
        from notifications.models import Notification, NotificationCategory
        recipients = set(schedule.panel_assignments.values_list('panelist_id', flat=True)) | set(old_values[schedule.pk]['panelist_ids'])
        recipients |= {x for x in (schedule.documenter_id, schedule.team.adviser_id, schedule.team.leader_id) if x}
        for recipient in recipients:
            recipient_role = get_user_model().objects.filter(pk=recipient).values_list('role', flat=True).first()
            Notification.objects.create(recipient_id=recipient, sender=actor, title='Defense schedule updated',
                message=f'{schedule.team.name}: {schedule.stage_label}, {schedule.scheduled_date} {schedule.start_time}, {schedule.room}. Reason: {data["reason"]}',
                category=NotificationCategory.DEFENSE, action_route='/student' if recipient_role == 'student' else '/admin/defense-board' if recipient_role == 'admin' else '/faculty/defense_board')
        log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING, action='schedule.operational_change', target=schedule,
            old_values=old_values[schedule.pk], new_values={**operation_values(schedule), 'change_details': diffs[schedule.pk]}, reason=data['reason'], actor=actor, request=request, strict=True)
    return review
