"""Project-owned people and deterministic, calendar-bounded Capstone planning.

Preview is a read projection. Confirmation replays its signed inputs under the
same semester/resource locks as operational changes; no client slots are trusted.
"""
from datetime import date, datetime, time, timedelta
from hashlib import sha256
import json
import uuid

from django.contrib.auth import get_user_model
from django.core import signing
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied, ValidationError
from defensys_backend.read_projection import read_projection, read_memoize

from academic_period_management.models import Semester
from academic_period_management.calendar import validate_defense_date
from academic_period_management.services import active_semester
from defense.stages.models import DefenseStage, StageGradingConfig
from student_teams.models import StudentTeam
from student_teams.capstone_lifecycle import requirements_for
from user_management.external_evaluators import resolve_evaluators, create_invitations
from .models import (CapstonePeopleAssignment, CapstoneAssignmentMember,
    CapstoneAssignmentRevision, CapstonePlanningBatch, DefenseSchedule, SchedulePanelist)
from .operations import StaleOperation
from .serializers import DefenseScheduleWriteSerializer


def digest(value):
    return sha256(json.dumps(value, sort_keys=True, default=str, separators=(',', ':')).encode()).hexdigest()


def lock_calendar_resources():
    # Cross-term room/person overlaps require a common lock, not just team locks.
    list(Semester.objects.select_for_update().order_by('pk'))


def require_admin(actor):
    if not actor.is_authenticated or not (actor.role == 'admin' or actor.is_superuser):
        raise PermissionDenied('Only administrators can configure Capstone scheduling.')


def current_term(actor, term_id=None):
    require_admin(actor)
    term = active_semester()
    if term_id is not None:
        term_id = serializers.IntegerField(min_value=1).run_validation(term_id)
    if not term or (term_id is not None and term_id != term.pk):
        raise ValidationError({'semester_id': 'Choose the active academic period.'})
    return term


def current_assignment(team):
    if not team.intake_semester_id:
        return None
    return CapstonePeopleAssignment.objects.filter(team=team, project_version=team.project_version,
        intake_semester_id=team.intake_semester_id).prefetch_related('members').first()


def roster_payload(assignment):
    if assignment is None:
        return None
    members = list(assignment.members.all())
    return {'chair_panelist_id': next((m.user_id for m in members if m.is_chair), None),
        'panelist_ids': [m.user_id for m in members if m.user_id],
        'external_evaluator_ids': [m.external_id for m in members if m.external_id],
        'documenter_id': assignment.documenter_id}


class RosterSerializer(serializers.Serializer):
    chair_panelist_id = serializers.IntegerField(min_value=1)
    panelist_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=500)
    external_evaluator_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), default=list, max_length=30)
    documenter_id = serializers.IntegerField(min_value=1, allow_null=True)


def validate_roster(team, roster, actor):
    from student_teams.participation import require_open
    from django.core.exceptions import ValidationError as ModelValidationError
    try:
        require_open(team)
    except ModelValidationError as exc:
        raise ValidationError({'team_ids': exc.messages})
    parsed = RosterSerializer(data=roster)
    parsed.is_valid(raise_exception=True)
    roster = parsed.validated_data
    ids, external_ids = roster['panelist_ids'], roster['external_evaluator_ids']
    if len(ids) != len(set(ids)) or len(external_ids) != len(set(external_ids)):
        raise ValidationError({'panelist_ids': 'Choose each evaluator once.'})
    if roster['chair_panelist_id'] not in ids:
        raise ValidationError({'chair_panelist_id': 'Choose one institutional chair from the panel.'})
    if not team.adviser_id:
        raise ValidationError({'adviser_id': f'Assign an adviser to {team.name} first.'})
    if team.adviser_id in ids or team.adviser_id == roster['documenter_id']:
        raise ValidationError({'panelist_ids': 'An adviser cannot evaluate or document their own team.'})
    if roster['documenter_id'] in ids:
        raise ValidationError({'documenter_id': 'The documenter must be separate from the panel.'})
    people, externals, doc = roster_people(roster, actor)
    return roster, people, externals, doc


@read_memoize()
def roster_people(roster, actor):
    resolver = DefenseScheduleWriteSerializer(context={'request': type('Actor', (), {'user': actor})()})
    return (resolver._resolve_panelists(roster['panelist_ids']), resolve_evaluators(roster['external_evaluator_ids'], actor),
        resolver._resolve_documenter({'scope': 'capstone', 'documenter_id': roster['documenter_id']}))


@read_memoize()
def config_for(stage, term):
    from defense.stages.grading_config import project_stage_config
    return project_stage_config(stage, term)


def adoption_candidate(team, requirements, actor):
    """Offer only a reviewed same-intake first-stage source; never auto-adopt."""
    if not team.intake_semester_id or not requirements:
        return None
    schedules = list(DefenseSchedule.objects.filter(team=team, project_version=team.project_version,
        semester_id=team.intake_semester_id, defense_stage_id=requirements[0]['id'],
        status__in=['scheduled', 'done', 'archived']).prefetch_related('panel_assignments', 'guest_invitations').order_by('pk'))
    candidates = []
    for schedule in schedules:
        panels = list(schedule.panel_assignments.all())
        chairs = [p.panelist_id for p in panels if p.is_chair]
        invitations = list(schedule.guest_invitations.all())
        if len(chairs) != 1 or any(i.evaluator_id is None for i in invitations):
            return {'requires_review': True, 'reason': 'Historical chair or external identity is ambiguous.'}
        roster = {'chair_panelist_id': chairs[0], 'panelist_ids': [p.panelist_id for p in panels],
            'external_evaluator_ids': sorted({i.evaluator_id for i in invitations}), 'documenter_id': schedule.documenter_id}
        try:
            validate_roster(team, roster, actor)
        except ValidationError:
            return {'requires_review': True, 'reason': 'Historical people require an eligibility or conflict review.'}
        candidates.append(roster)
    if not candidates:
        return None
    signatures = {digest({**r, 'panelist_ids': sorted(r['panelist_ids'])}) for r in candidates}
    if len(signatures) != 1:
        return {'requires_review': True, 'reason': 'The first-stage hearings have different people. Choose the continuing roster explicitly.'}
    return {'requires_review': False, 'roster': candidates[0], 'source_schedule_ids': [s.pk for s in schedules]}


def team_stage_readiness(team, stage):
    """Project scheduler-only labels without changing academic workflow records."""
    from student_teams.services import is_stage_ready, was_stage_endorsed, get_stage_progress
    from student_teams.models import TeamStageProgress
    from student_teams.capstone_lifecycle import latest_stage_assessment
    from grading.grades.models import TeamGrade
    from grading.grades.defense_workflow import legacy_finalized_pass

    endorsed = was_stage_endorsed(team, stage)
    grade = latest_stage_assessment(team, stage.pk)
    progress = get_stage_progress(team, stage)
    approved = bool(grade and not grade.closed_as_failed and (
        grade.verdict in TeamGrade.PASSING_VERDICTS or legacy_finalized_pass(grade)))
    redefense = bool(grade and not grade.closed_as_failed and (
        grade.verdict == TeamGrade.VERDICT_FOR_REDEFENSE or grade.attempt_count > 1))
    # An old assessed attempt can retain its scheduled flag. Do not let it mask
    # the new attempt's preparation, and never repair records from this GET.
    scheduled = (DefenseSchedule.objects.filter(team=team, project_version=team.project_version,
        semester=team.semester, scope='capstone', defense_stage=stage, status='scheduled')
        .exclude(grade_records__verdict__in=[value for value, _ in TeamGrade.VERDICT_CHOICES if value])
        .filter(attempt_grade_snapshots__isnull=True).exists())
    if approved:
        state, label = 'approved', 'Approved'
    elif scheduled:
        state, label = 'scheduled', 'Scheduled'
    elif is_stage_ready(team, stage):
        state, label = ('ready_for_redefense', 'Ready for re-defense') if redefense else ('ready', 'Ready to schedule')
    elif grade and grade.verdict == TeamGrade.VERDICT_FOR_REDEFENSE and not grade.closed_as_failed:
        state, label = 'preparing_redefense', 'Preparing re-defense'
    elif progress and progress.status in (TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_ARCHIVED):
        state, label = 'completed', 'Completed'
    elif grade and (grade.closed_as_failed or grade.verdict in ('failed', 'project_rejected')):
        state = 'failed' if grade.closed_as_failed else grade.verdict
        label = 'Failed' if state == 'failed' else 'Project rejected'
    elif endorsed:
        state, label = 'blocked', 'Not ready to schedule'
    else:
        state, label = 'awaiting_endorsement', 'Awaiting endorsement'
    return {'status': state, 'label': label, 'endorsed': endorsed,
        'can_schedule': state in ('ready', 'ready_for_redefense'),
        'include_in_scheduler': state not in ('approved', 'completed', 'scheduled')}


@read_projection()
def workspace(actor, term_id=None):
    from defense.stages.context import stages_for_semester
    from academic_period_management.capstone_mode import capstone_mode_payload
    term = current_term(actor, term_id)
    teams = list(StudentTeam.objects.filter(semester=term, level__contains='Capstone')
        .select_related('adviser', 'intake_semester').order_by('adviser_id', 'pk'))
    stage_map = {s.pk: s for s in stages_for_semester(term).filter(is_active=True)}
    requirements = {t.pk: requirements_for(t) for t in teams}
    captured_ids = {item['id'] for items in requirements.values() for item in items}
    stage_map.update({s.pk: s for s in DefenseStage.objects.filter(pk__in=captured_ids)})
    stages = []
    for stage in sorted(stage_map.values(), key=lambda s: (s.display_order, s.pk)):
        config = config_for(stage, term)
        stages.append({'id': stage.pk, 'label': stage.label, 'order': stage.display_order,
            'minutes_required': stage.minutes_required,
            'default_slot_duration_minutes': config.default_slot_duration_minutes if config else None,
            'configuration_revision': str(config.updated_at) if config else None})
    rows = []
    for team in teams:
        assignment = current_assignment(team)
        readiness = {str(item['id']): team_stage_readiness(team, stage_map[item['id']])
            for item in requirements[team.pk] if item['id'] in stage_map}
        rows.append({'id': team.pk, 'name': team.name, 'project_version': team.project_version,
            'intake_semester_id': team.intake_semester_id,
            'intake_label': team.intake_semester.display_name if team.intake_semester_id else 'Roster confirmation required',
            'adviser_id': team.adviser_id,
            'adviser_name': (team.adviser.get_full_name() or team.adviser.username) if team.adviser_id else 'Unassigned adviser',
            'applicable_stage_ids': [item['id'] for item in requirements[team.pk]],
            'initial_stage_id': assignment.initial_stage_id if assignment else next(iter(
                [item['id'] for item in requirements[team.pk]]), None),
            'ready_stage_ids': [int(pk) for pk, state in readiness.items() if state['can_schedule']],
            'stage_readiness': readiness,
            'assignment_revision': assignment.revision if assignment else 0,
            'assignment': roster_payload(assignment),
            'adoption_candidate': adoption_candidate(team, requirements[team.pk], actor) if assignment is None else None})
    from .serializers import PanelistOptionSerializer
    from user_management.models import ExternalEvaluator
    from user_management.external_evaluators import evaluator_payload
    faculty = get_user_model().objects.filter(role__in=['faculty', 'admin'], is_active=True).order_by('last_name', 'first_name', 'pk')
    from defense.minutes.models import DefenseMinutes
    workloads = []
    for doc_id in {row['assignment']['documenter_id'] for row in rows if row['assignment'] and row['assignment']['documenter_id']}:
        assigned = [r['id'] for r in rows if r['assignment'] and r['assignment']['documenter_id'] == doc_id]
        actual = DefenseSchedule.objects.filter(scope='capstone', semester=term, documenter_id=doc_id,
            status__in=['scheduled', 'done'], minutes_required=True)
        completed = DefenseMinutes.objects.filter(schedule__in=actual, status='completed').count()
        workloads.append({'documenter_id': doc_id, 'teams': len(assigned),
            'expected_minutes': actual.count(), 'outstanding_minutes': actual.count() - completed})
    return {'semester_id': term.pk, 'semester_label': term.display_name,
        'starts_on': term.starts_on, 'ends_on': term.ends_on,
        'mode': capstone_mode_payload(term), 'stages': stages, 'teams': rows,
        'pipeline_revision': digest(stages),
        'documenter_workloads': workloads,
        'faculty': PanelistOptionSerializer(faculty, many=True).data,
        'panelists': PanelistOptionSerializer(faculty.filter(is_panelist=True), many=True).data,
        'documenters': PanelistOptionSerializer(faculty.filter(is_documenter=True), many=True).data,
        'external_evaluators': [evaluator_payload(e) for e in ExternalEvaluator.objects.filter(status='approved', is_active=True)]}


class AssignmentEditSerializer(serializers.Serializer):
    team_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=5000)
    defense_stage_id = serializers.IntegerField(min_value=1)
    expected_revisions = serializers.DictField(child=serializers.IntegerField(min_value=0))
    roster = RosterSerializer(required=False)
    changes = serializers.DictField(required=False)
    reason = serializers.CharField(required=False, max_length=2000)


def apply_roster_delta(before, changes):
    allowed = {'chair_panelist_id', 'documenter_id', 'add_panelist_ids', 'remove_panelist_ids',
               'add_external_evaluator_ids', 'remove_external_evaluator_ids'}
    if set(changes) - allowed:
        raise ValidationError({'changes': 'Use explicit member additions/removals or chair/documenter changes.'})
    result = {**before}
    for key in ('panelist_ids', 'external_evaluator_ids'):
        remove, add = changes.get('remove_' + key, []), changes.get('add_' + key, [])
        if not isinstance(remove, list) or not isinstance(add, list):
            raise ValidationError({'changes': 'Member changes must be lists of IDs.'})
        result[key] = [pk for pk in before[key] if pk not in remove] + [pk for pk in add if pk not in before[key]]
    for key in ('chair_panelist_id', 'documenter_id'):
        if key in changes:
            result[key] = changes[key]
    return result


@transaction.atomic
def save_assignments(actor, payload):
    term = current_term(actor, payload.get('semester_id'))
    parsed = AssignmentEditSerializer(data=payload)
    parsed.is_valid(raise_exception=True)
    data = parsed.validated_data
    lock_calendar_resources()
    teams = list(StudentTeam.objects.select_for_update().filter(pk__in=data['team_ids'], semester=term).order_by('pk'))
    if len(teams) != len(set(data['team_ids'])):
        raise ValidationError({'team_ids': 'Refresh the current roster selection.'})
    for team in teams:
        if not team.is_capstone or not team.intake_semester_id:
            raise ValidationError({'team_ids': 'Confirm the Capstone intake roster before assigning people.'})
        requirements = requirements_for(team)
        old = current_assignment(team)
        if data['defense_stage_id'] not in [r['id'] for r in requirements]:
            raise ValidationError({'defense_stage_id': 'Stage does not apply to this project.'})
        if data['expected_revisions'].get(str(team.pk)) != (old.revision if old else 0):
            raise StaleOperation()
        before = roster_payload(old)
        if old:
            if len(data.get('reason', '').strip()) < 5 or 'changes' not in data or 'roster' in data:
                raise ValidationError({'changes': 'Provide a reason and explicit changes to the continuing roster.'})
            candidate = apply_roster_delta(before, data['changes'])
        else:
            if not requirements:
                raise ValidationError({'defense_stage_id': 'Stage does not apply to this project.'})
            candidate = data.get('roster', {})
        roster, people, externals, doc = validate_roster(team, candidate, actor)
        if doc is None and DefenseStage.objects.filter(pk=data['defense_stage_id'], minutes_required=True).exists():
            raise ValidationError({'documenter_id': 'Assign a documenter: this configured stage requires signed minutes.'})
        if old and before == roster:
            continue
        if old:
            assignment = old
            assignment.revision += 1
            assignment.members.all().delete()
        else:
            assignment = CapstonePeopleAssignment(team=team, project_version=team.project_version,
                intake_semester_id=team.intake_semester_id, source_semester=term,
                initial_stage_id=requirements[0]['id'] if requirements else data['defense_stage_id'])
        assignment.adviser_id = team.adviser_id
        assignment.documenter = doc
        assignment.updated_by = actor
        assignment.save()
        CapstoneAssignmentMember.objects.bulk_create([
            CapstoneAssignmentMember(assignment=assignment, user=person, order=index,
                is_chair=person.pk == roster['chair_panelist_id']) for index, person in enumerate(people)] + [
            CapstoneAssignmentMember(assignment=assignment, external=person, order=len(people) + index)
            for index, person in enumerate(externals)])
        CapstoneAssignmentRevision.objects.create(assignment=assignment, revision=assignment.revision,
            before=before or {}, after=roster, reason=data.get('reason', 'Initial assignment'), actor=actor)
        DefenseSchedule.objects.filter(
            team=team,
            project_version=team.project_version,
            scope='capstone',
            continuing_assignment__isnull=True,
        ).update(continuing_assignment=assignment)
    return workspace(actor, term.pk)


class WindowSerializer(serializers.Serializer):
    start_time = serializers.TimeField()
    end_time = serializers.TimeField()


class ReplacementEventSerializer(serializers.Serializer):
    team_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=5000)
    scope = serializers.ChoiceField(choices=['stage_only', 'continuing'])
    reason = serializers.CharField(min_length=5, max_length=2000)
    changes = serializers.DictField(child=serializers.DictField(), default=dict)


class AutoPlanSerializer(serializers.Serializer):
    semester_id = serializers.IntegerField(min_value=1)
    defense_stage_id = serializers.IntegerField(min_value=1)
    team_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=5000)
    start_date = serializers.DateField()
    slot_duration = serializers.IntegerField(min_value=15, max_value=240)
    gap_minutes = serializers.IntegerField(min_value=0, max_value=240, default=0)
    room = serializers.CharField(max_length=120)
    include_sunday = serializers.BooleanField(default=False)
    excluded_dates = serializers.ListField(child=serializers.DateField(), default=list, max_length=5000)
    windows = WindowSerializer(many=True, min_length=1, max_length=20)
    overrides = serializers.DictField(child=RosterSerializer(), default=dict)
    replacement_reason = serializers.CharField(required=False, max_length=2000)
    replacement_events = ReplacementEventSerializer(many=True, required=False, default=list, max_length=5000)

    def validate(self, attrs):
        if 'must_finish_by' in self.initial_data or 'finish_by' in self.initial_data:
            raise ValidationError({'finish': 'The scheduler computes the finish; use unavailable dates and daily windows.'})
        if len(attrs['team_ids']) != len(set(attrs['team_ids'])):
            raise ValidationError({'team_ids': 'Each team must appear exactly once.'})
        spans = sorted((w['start_time'], w['end_time']) for w in attrs['windows'])
        for i, (start, end) in enumerate(spans):
            length = (datetime.combine(date.min, end) - datetime.combine(date.min, start)).total_seconds() / 60
            if length < attrs['slot_duration'] or (i and start < spans[i - 1][1]):
                raise ValidationError({'windows': 'Use nonoverlapping daily windows that fit a complete team slot.'})
        attrs['windows'] = [{'start_time': start, 'end_time': end} for start, end in spans]
        if set(attrs['overrides']) - {str(pk) for pk in attrs['team_ids']}:
            raise ValidationError({'overrides': 'Choose replacement teams from this plan.'})
        for event in attrs['replacement_events']:
            if set(event['team_ids']) - set(attrs['team_ids']) or set(event['changes']) - {str(pk) for pk in event['team_ids']}:
                raise ValidationError({'replacement_events': 'Audit replacements must refer to teams in this plan.'})
        return attrs


def allocate(queue, *, start_date, ends_on, windows, duration, gap=0, excluded=(), include_sunday=False, reservations=()):
    """Pure stable queue allocator. Skip blocking intervals without changing people/order."""
    slots = []
    index = 0
    day = start_date
    excluded = set(excluded)
    while index < len(queue) and day <= ends_on:
        if day in excluded or (day.weekday() == 6 and not include_sunday):
            day += timedelta(days=1)
            continue
        for block_index, window in enumerate(windows):
            cursor = datetime.combine(day, window['start_time'])
            stop = datetime.combine(day, window['end_time'])
            while index < len(queue) and cursor + timedelta(minutes=duration) <= stop:
                item = queue[index]
                end = cursor + timedelta(minutes=duration)
                blocked = [r for r in reservations if cursor < r['end'] and r['start'] < end and (
                    item['room'].strip().casefold() == r['room'] or item['people'] & r['people'] or item['externals'] & r['externals'])]
                if blocked:
                    cursor = max(r['end'] for r in blocked)
                    continue
                slots.append({'team_id': item['team_id'], 'scheduled_date': day.isoformat(),
                    'start_time': cursor.time().isoformat(), 'end_time': end.time().isoformat(),
                    'block_key': f'{day.isoformat()}:{block_index}', 'window_index': block_index,
                    'room': item['room'], 'slot_duration': duration})
                index += 1
                cursor = end + timedelta(minutes=gap)
        day += timedelta(days=1)
    return slots, [q['team_id'] for q in queue[index:]]


class PlanningScheduleSerializer(DefenseScheduleWriteSerializer):
    def _resolve_semester(self, attrs):
        return self.context['term']

    def _resolve_defense_stage(self, attrs):
        return self.context['stage']

    def _resolve_panelists(self, ids):
        return self.context['people']

    def _resolve_documenter(self, attrs):
        return self.context['documenter']

    def _validate_room_overlap(self, *args, **kwargs):
        pass  # The allocator advances past existing room/person reservations.

    def _validate_panelist_overlap(self, *args, **kwargs):
        pass

    def _validate_capstone_stage_setup(self, attrs):
        from grading.grades.evaluation_policy import concept_stage
        stage = attrs['defense_stage']
        config = config_for(stage, attrs['semester'])
        panel_only = concept_stage(stage)
        roles = ('panel',) if panel_only else ('panel', 'adviser', 'peer')
        if stage.qualifying_score is None or not config or not all(
                getattr(config, f'{role}_rubric_id') for role in roles):
            requirements = 'panel rubric' if panel_only else 'panel/adviser/peer rubrics'
            raise ValidationError({'defense_stage_id':
                f'Complete the stage qualifying score and published {requirements} in setup.'})
        attrs['rubric'] = config.panel_rubric
        for role in roles:
            rubric = getattr(config, f'{role}_rubric')
            if rubric.status != 'published':
                message = ('Publish the panel rubric before scheduling.' if panel_only
                    else 'Publish all configured stage rubrics before scheduling.')
                raise ValidationError({'defense_stage_id': message})
        return attrs


@read_projection()
def build_plan(actor, payload):
    parsed = AutoPlanSerializer(data=payload)
    parsed.is_valid(raise_exception=True)
    data = parsed.validated_data
    term = current_term(actor, data['semester_id'])
    validate_defense_date(term, data['start_date'], field='start_date')
    teams = {t.pk: t for t in StudentTeam.objects.filter(pk__in=data['team_ids'], semester=term).select_related('adviser')}
    if len(teams) != len(data['team_ids']):
        raise ValidationError({'team_ids': 'Refresh the current semester roster.'})
    stage = DefenseStage.objects.filter(pk=data['defense_stage_id'], is_active=True).first()
    if not stage:
        raise ValidationError({'defense_stage_id': 'Choose a configured stage.'})
    # Queue must keep each adviser/intake together, including when groups span days.
    seen, last = set(), None
    queue, revisions, serializers_by_team, assignments_by_team = [], [], {}, {}
    for pk in data['team_ids']:
        team = teams[pk]
        group = (team.adviser_id, team.intake_semester_id)
        if group != last and group in seen:
            raise ValidationError({'team_ids': 'Keep each adviser’s teams together in the queue.'})
        seen.add(group)
        last = group
        applicable = requirements_for(team)
        if not team.is_capstone or stage.pk not in [r['id'] for r in applicable]:
            raise ValidationError({'team_ids': f'This stage does not apply to {team.name}.'})
        assignment = current_assignment(team)
        assignments_by_team[pk] = assignment
        if assignment is None:
            raise ValidationError({'team_ids': f'Save the continuing panel and documenter for {team.name} first.'})
        roster = roster_payload(assignment)
        override = data['overrides'].get(str(pk))
        if override and override != roster:
            if len(data.get('replacement_reason', '').strip()) < 5:
                raise ValidationError({'replacement_reason': 'Give a reason for this defense’s temporary replacement.'})
            roster = override
        roster, people, externals, doc = validate_roster(team, roster, actor)
        request = type('Actor', (), {'user': actor})()
        serializer = PlanningScheduleSerializer(data={'scope': 'capstone', 'semester_id': term.pk,
            'defense_stage_id': stage.pk, 'team_id': pk, 'scheduled_date': data['start_date'],
            'start_time': data['windows'][0]['start_time'], 'slot_duration': data['slot_duration'],
            'room': data['room'], **roster}, context={'request': request, 'term': term, 'stage': stage,
                'people': people, 'documenter': doc})
        serializer.is_valid(raise_exception=True)
        serializers_by_team[pk] = serializer
        queue.append({'team_id': pk, 'room': data['room'], 'people': {p.pk for p in people} | ({doc.pk} if doc else set()),
            'externals': {p.pk for p in externals}})
        revisions.append([pk, team.project_version, team.intake_semester_id, team.adviser_id,
            team.updated_at, applicable, assignment.pk, assignment.revision, roster])
    reservations = []
    for schedule in DefenseSchedule.objects.filter(scheduled_date__gte=data['start_date'] - timedelta(days=1),
            scheduled_date__lte=term.ends_on, status__in=['scheduled', 'done']).prefetch_related('panel_assignments', 'guest_invitations'):
        start = datetime.combine(schedule.scheduled_date, schedule.start_time)
        reservations.append({'start': start, 'end': start + timedelta(minutes=schedule.slot_duration),
            'room': schedule.room.strip().casefold(),
            'people': {p.panelist_id for p in schedule.panel_assignments.all()} | ({schedule.documenter_id} if schedule.documenter_id else set()),
            'externals': {i.evaluator_id for i in schedule.guest_invitations.all() if i.is_active and i.evaluator_id}})
    slots, remaining = allocate(queue, start_date=data['start_date'], ends_on=term.ends_on, windows=data['windows'],
        duration=data['slot_duration'], gap=data['gap_minutes'], excluded=data['excluded_dates'],
        include_sunday=data['include_sunday'], reservations=reservations)
    for slot in slots:
        team = teams[slot['team_id']]
        assignment = assignments_by_team[team.pk]
        slot.update({'team_name': team.name, 'adviser_id': team.adviser_id,
            'intake_semester_id': team.intake_semester_id, 'assignment_id': assignment.pk,
            'roster': {k: serializers_by_team[team.pk].validated_data.get(k) for k in
                ('chair_panelist_id', 'panelist_ids', 'external_evaluator_ids', 'documenter_id')}})
    config = config_for(stage, term)
    fingerprint = digest([term.pk, term.starts_on, term.ends_on, revisions,
        list(DefenseStage.objects.filter(pk__in={r['id'] for t in teams.values() for r in requirements_for(t)})
            .order_by('pk').values()), list(StageGradingConfig.objects.filter(pk=config.pk).values()) if config else [], slots, remaining])
    result = {'slots': slots, 'remaining_team_ids': remaining, 'complete': not remaining,
        'blocking_reason': 'Remaining teams cannot fit inside the official semester calendar.' if remaining else None,
        'days': len({s['scheduled_date'] for s in slots}), 'sessions': len({s['block_key'] for s in slots}),
        'finish': f"{slots[-1]['scheduled_date']} {slots[-1]['end_time']}" if slots else None,
        'scheduled_dates': sorted({s['scheduled_date'] for s in slots}), 'fingerprint': fingerprint}
    return result, serializers_by_team


def preview_plan(actor, payload):
    result, _ = build_plan(actor, payload)
    normalized = json.loads(json.dumps(payload, default=str))
    result['preview_token'] = signing.dumps({'inputs': normalized, 'fingerprint': result['fingerprint']},
        salt='capstone-auto-plan', compress=True)
    return result


@transaction.atomic
def confirm_plan(actor, payload):
    require_admin(actor)
    try:
        key = uuid.UUID(str(payload.get('idempotency_key')))
        signed = signing.loads(payload.get('preview_token', ''), salt='capstone-auto-plan')
    except (ValueError, TypeError, signing.BadSignature):
        raise StaleOperation('Refresh the schedule preview before confirming.')
    request_hash = digest(signed)
    lock_calendar_resources()
    existing = CapstonePlanningBatch.objects.filter(idempotency_key=key).first()
    if existing:
        if existing.request_hash != request_hash or existing.created_by_id != actor.pk:
            raise StaleOperation('This confirmation key belongs to a different plan.')
        return existing
    try:
        signing.loads(payload.get('preview_token', ''), salt='capstone-auto-plan', max_age=8 * 60 * 60)
    except signing.BadSignature:
        raise StaleOperation('This preview expired. Generate a new preview before confirming.')
    list(StudentTeam.objects.select_for_update().filter(pk__in=signed['inputs'].get('team_ids', [])).order_by('pk'))
    try:
        result, writers = build_plan(actor, signed['inputs'])
    except ValidationError as exc:
        raise StaleOperation({'detail': 'The roster, readiness, or setup changed. Generate a new preview.', 'changes': exc.detail})
    if result['fingerprint'] != signed['fingerprint']:
        raise StaleOperation()
    if not result['complete']:
        raise ValidationError({'remaining_team_ids': result['remaining_team_ids'], 'detail': result['blocking_reason']})
    batch = CapstonePlanningBatch.objects.create(idempotency_key=key, request_hash=request_hash,
        fingerprint=result['fingerprint'], inputs=signed['inputs'], created_by=actor)
    sessions, groups, initialized = {}, {}, []
    for slot in result['slots']:
        writer = writers[slot['team_id']]
        attrs = dict(writer.validated_data)
        attrs['scheduled_date'] = date.fromisoformat(slot['scheduled_date'])
        attrs['start_time'] = time.fromisoformat(slot['start_time'])
        chair = attrs['chair_panelist_id']
        people, externals, doc = attrs.pop('panelists'), attrs['external_evaluators'], attrs.get('documenter')
        writer._ensure_panelist_roles(people, changed_by=actor)
        writer._ensure_documenter_role(doc, changed_by=actor)
        roster_key = digest(slot['roster'])
        key = (slot['block_key'], roster_key)
        # A configured window is one session, even when its teams have different
        # continuing panels/documenters. Keep invitation groups roster-scoped.
        session_id = sessions.setdefault(slot['block_key'], uuid.uuid4())
        writer._pop_schedule_meta(attrs)
        schedule = DefenseSchedule.objects.create(**attrs, batch_id=batch.pk, session_id=session_id,
            planning_batch=batch, planning_block_key=slot['block_key'], continuing_assignment_id=slot['assignment_id'], created_by=actor)
        writer._sync_panelists(schedule, people, chair_panelist_id=chair)
        initialized.append((writer, schedule))
        groups.setdefault(key, (externals, []))[1].append(schedule)
        if doc:
            from .serializers import send_documenter_assignment_notification
            # Dispatch only after the complete batch commits.
            transaction.on_commit(lambda s=schedule: send_documenter_assignment_notification(s))
    for externals, schedules in groups.values():
        create_invitations(externals, schedules, actor)
    for writer, schedule in initialized:
        writer._sync_grade_row(schedule)
        from notifications.services import notify_student_defense_schedule
        notify_student_defense_schedule(schedule)
    return batch
