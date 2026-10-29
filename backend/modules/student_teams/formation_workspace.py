"""Reviewable, account-preserving imports shared by the team creation page."""
from hashlib import sha256
from uuid import uuid4

from django.contrib.auth import get_user_model
from django.core import signing
from django.db import transaction
from django.db import IntegrityError
from django.core.exceptions import ValidationError as ModelValidationError
from rest_framework import serializers
from rest_framework.exceptions import ValidationError
from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.serializers import SemesterSerializer
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.event_scope import pit_events_for_user
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment
from . import formation
from .bulk_import import resolve_user_by_full_name, resolve_adviser, imported_concept_requirement
from .formation_access import CanFormTeams, CanGenerateTeams, instructor_sections, is_manager, require_formation_scope
from .models import StudentTeam
from .serializers import StudentTeamWriteSerializer, BulkTeamRowSerializer
from .team_levels import is_capstone_scope, user_is_admin, user_is_pit_lead_only, normalize_year_level
from .term_scope import get_active_semester

User = get_user_model()
SALT = 'student-teams.workspace.v1'


def clean(value):
    return ' '.join(str(value or '').strip().split())


def empty_section(value):
    return not clean(value) or clean(value).upper() == 'BSIT'


def readable_error(exc):
    detail = getattr(exc, 'detail', str(exc))
    if isinstance(detail, dict):
        return ' '.join(f'{key}: {value}' for key, value in detail.items())
    return str(detail)


class ImportAPIView(APIView):
    def handle_exception(self, exc):
        if isinstance(exc, (IntegrityError, ModelValidationError)):
            exc = ValidationError('A team name or enrollment changed while saving. Review the import again.')
        return super().handle_exception(exc)


class TeamCreationContextView(APIView):
    permission_classes = [CanFormTeams]

    def get(self, request):
        term = get_active_semester()
        if not term:
            raise ValidationError('No active semester is configured.')
        assignments = instructor_sections(request.user, term)
        if is_manager(request.user):
            assignments = SectionInstructorAssignment.objects.filter(semester=term, is_active=True)
            if user_is_pit_lead_only(request.user):
                assignments = assignments.filter(year_level=request.user.pit_lead_year)
        levels = []
        for level, _ in StudentTeam.LEVEL_CHOICES:
            year = level.rsplit(' ', 1)[0]
            if not is_manager(request.user) and ('PIT' not in level or not assignments.filter(year_level=year).exists()):
                continue
            if user_is_pit_lead_only(request.user) and ('PIT' not in level or year != request.user.pit_lead_year):
                continue
            levels.append(level)
        return Response({
            'levels': levels, 'semester': SemesterSerializer(term).data,
            'assignments': list(assignments.values('year_level', 'section').distinct()),
            'events': list(pit_events_for_user(request.user, semester=term).values(
                'id', 'year_level', 'event_name', 'is_officially_complete')),
            'can_manage_policy': is_manager(request.user),
            'can_generate': request.user.role == 'faculty' and instructor_sections(request.user, term).exists(),
        })


def import_context(user, data):
    return formation.formation_scope(user, data, generation=False)


def roster_preview(user, data):
    # A roster can be prepared before a PIT event is configured.
    term = get_active_semester()
    if not term:
        raise ValidationError('No active semester is configured.')
    level = serializers.ChoiceField(choices=StudentTeam.LEVEL_CHOICES).run_validation(data.get('level'))
    require_formation_scope(user, term, level)
    year = level.rsplit(' ', 1)[0]
    rows = data.get('students', [])
    if not isinstance(rows, list) or not 0 < len(rows) <= 5000:
        raise ValidationError('Upload a class list containing 1 to 5,000 students.')
    default_section = clean(data.get('section'))
    records, seen = [], set()
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            raise ValidationError('Each class-list row must be an object.')
        username = clean(row.get('id_number') or row.get('student_number') or row.get('username'))
        section = clean(row.get('section') or default_section)
        issues = []
        if not username or username in seen:
            issues.append('Missing or repeated student number in this file.')
        seen.add(username)
        if empty_section(section) or len(section) > 80:
            issues.append('A valid class section is required.')
        else:
            require_formation_scope(user, term, level, section)
        user_record = User.objects.filter(username=username, role='student', is_active=True).first()
        record = StudentAcademicRecord.objects.filter(student=user_record, semester=term).first() if user_record else None
        if row.get('year_level') and normalize_year_level(row['year_level']) != year:
            issues.append('The class-list year level differs from the selected year.')
        if not user_record:
            issues.append('Student account not found. Ask the chair/admin to enroll this student.')
        elif not record:
            from .roster_enrollment import missing_enrollment_issues
            issues.extend(missing_enrollment_issues([user_record.pk], term))
        elif record.year_level != year:
            issues.append(f'Student is enrolled in {record.year_level}, not {year}.')
        conflict = bool(record and not empty_section(record.section) and record.section != section)
        if conflict and (not is_manager(user) or data.get('resolve_conflicts') is not True):
            issues.append(f'Existing section is {record.section}. An admin/PIT lead must review the reassignment.')
        records.append({'row': index, 'username': username, 'student_id': user_record.pk if user_record else None,
            'name': user_record.get_full_name() or username if user_record else username,
            'section': section, 'previous_section': record.section if record else None,
            'year_level': record.year_level if record else None, 'issues': issues,
            'action': 'unchanged' if record and record.section == section else 'assign section'})
    return term, records


def seal(user, kind, data, state):
    return signing.dumps({'actor': user.pk, 'kind': kind, 'data': data, 'state': state,
                          'nonce': uuid4().hex}, salt=SALT, compress=True)


def open_preview(user, token, kind):
    try:
        payload = signing.loads(token, salt=SALT, max_age=3600)
    except (signing.BadSignature, TypeError) as exc:
        raise ValidationError('This preview expired. Review the import again.') from exc
    if payload.get('actor') != user.pk or payload.get('kind') != kind:
        raise ValidationError('This preview belongs to another user or import.')
    return payload


def receipt(user, token, action):
    return SystemAuditLog.objects.filter(actor=user, action=action,
        new_values__preview_id=sha256(token.encode()).hexdigest()).first()


def record_receipt(request, token, action, target, result):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS, action=action,
        target=target, request=request, strict=True,
        new_values={**result, 'preview_id': sha256(token.encode()).hexdigest()})


class SectionRosterPreviewView(APIView):
    permission_classes = [CanFormTeams]

    def post(self, request):
        term, rows = roster_preview(request.user, request.data)
        ready = not any(row['issues'] for row in rows)
        return Response({'rows': rows, 'ready': ready, 'semester_id': term.pk,
            'preview_token': seal(request.user, 'roster', dict(request.data), [term.pk, rows]) if ready else None})


class SectionRosterCommitView(ImportAPIView):
    permission_classes = [CanFormTeams]

    @transaction.atomic
    def post(self, request):
        token = request.data.get('preview_token', '')
        payload = open_preview(request.user, token, 'roster')
        list(User.objects.select_for_update().filter(pk=request.user.pk))
        previous = receipt(request.user, token, 'teams.roster_import')
        if previous:
            return Response(previous.new_values)
        ids = [r['student_id'] for r in payload['state'][1] if r['student_id']]
        list(User.objects.select_for_update().filter(pk__in=ids).order_by('pk'))
        list(StudentAcademicRecord.objects.select_for_update().filter(student_id__in=ids).order_by('pk'))
        term, rows = roster_preview(request.user, payload['data'])
        from .roster_enrollment import require_roster_enrollment
        require_roster_enrollment(ids, term, lock=True)
        if [term.pk, rows] != payload['state'] or any(row['issues'] for row in rows):
            raise ValidationError('The roster changed. Review the class list again before saving.')
        updated = 0
        for row in rows:
            updated += StudentAcademicRecord.objects.filter(student_id=row['student_id'], semester=term).exclude(
                section=row['section']).update(section=row['section'])
        result = {'updated_count': updated, 'unchanged_count': len(rows) - updated, 'semester_id': term.pk}
        record_receipt(request, token, 'teams.roster_import', term, result)
        return Response(result)


def team_import_preview(user, data):
    from .pit_rosters import replacement_import
    if not isinstance(data.get('teams'), list):
        raise ValidationError('Upload a list of prepared teams.')
    _, _, _, event = import_context(user, data)
    sections = {clean(r.get('section') or data.get('section')) for r in data.get('teams', []) if isinstance(r, dict)}
    with replacement_import(user, event, sections, data.get('roster_override') is True):
        return _team_import_preview(user, data)


def _team_import_preview(user, data):
    term, level, year, event = import_context(user, data)
    input_rows = data.get('teams', [])
    if not isinstance(input_rows, list) or not 0 < len(input_rows) <= 500:
        raise ValidationError('Upload between 1 and 500 teams.')
    setups = data.get('project_setups', {})
    if not isinstance(setups, dict):
        raise ValidationError('Project setup must be configured by section.')
    for section, config in setups.items():
        if not isinstance(config, dict) or config.get('architecture') not in ('shared', 'independent'):
            raise ValidationError('Choose independent projects or a shared system for each section.')
        require_formation_scope(user, term, level, section)
        if config.get('architecture') == 'shared':
            from .formation_views import SharedSystemGenerationSerializer
            validation = SharedSystemGenerationSerializer(data=config)
            validation.is_valid(raise_exception=True)
            formation.generation_concept_context(event, config, semester=term, pit_year=year if 'PIT' in level else None)
            if not config.get('project_manager_id'):
                raise ValidationError('Choose the shared system project manager before reviewing the import.')
    results, state, seen, batch_members = [], [], set(), set()
    for index, raw in enumerate(input_rows, 1):
        issues, warnings, payload = [], [], None
        if not isinstance(raw, dict):
            raise ValidationError('Each team row must be an object.')
        row = {**raw, 'level': level, 'year_level': year,
               'section': clean(raw.get('section') or data.get('section')),
               'current_defense_stage': event.event_name if event else ''}
        name = clean(row.get('team_name'))
        if name in seen:
            issues.append('This team name appears more than once in the file.')
        seen.add(name)
        if raw.get('level') and raw['level'] != level:
            issues.append('The file program/year differs from the selected context.')
        require_formation_scope(user, term, level, row['section'])
        existing = StudentTeam.objects.filter(name=name, level=level, semester=term).first()
        setup = setups.get(row['section'], {})
        shared = setup.get('architecture') == 'shared'
        if shared:
            warnings.append('Supplied module titles fill the first shared proposal. Leaders complete the remaining modules for the same shared alternatives.')
        if existing and (existing.semester_id != term.pk or
                (existing.current_defense_stage or '') != (event.event_name if event else '')):
            issues.append('This name belongs to another semester/event. Choose a distinct team name.')
        if existing and not is_manager(user):
            require_formation_scope(user, term, level, existing.section)
        record_state = []
        ser = BulkTeamRowSerializer(data=row)
        if not ser.is_valid():
            issues.append(readable_error(ValidationError(ser.errors)))
        else:
            resolved = []
            for ref in ser.validated_data['member_ids']:
                student, error = resolve_user_by_full_name(ref, role='student', field_label='Member')
                if error or not student or not student.is_active:
                    issues.append(error or 'Member account is missing or inactive.')
                else:
                    resolved.append(student.pk)
            leader, error = resolve_user_by_full_name(ser.validated_data['leader_id'], role='student', field_label='Leader')
            if error or not leader:
                issues.append(error or 'A valid leader is required.')
            adviser_id = existing.adviser_id if existing else None
            if 'Capstone' in level and (row.get('adviser_name') or row.get('adviser_id')):
                adviser, status, _ = resolve_adviser(str(row.get('adviser_name') or row.get('adviser_id')))
                if status != 'valid':
                    issues.append('The adviser reference is missing, inactive, or ambiguous.')
                adviser_id = adviser.pk if adviser else None
            instructor, instructor_error = resolve_user_by_full_name(row.get('instructor_name'),
                role=['faculty', 'admin'], field_label='Instructor')
            if instructor_error:
                issues.append(instructor_error)
            if instructor and not instructor.is_active:
                issues.append('The referenced instructor account is inactive.')
            if instructor and not is_manager(user) and instructor.pk != user.pk:
                issues.append('An instructor import cannot assign another instructor.')
            if shared and instructor and SectionInstructorAssignment.objects.filter(semester=term,
                    year_level=year, section=row['section'], is_active=True).exclude(faculty=instructor).exists():
                issues.append('This shared section already has a different instructor. Resolve the section instructor assignment before importing its shared project.')
            for record in StudentAcademicRecord.objects.filter(student_id__in=resolved, semester=term).order_by('student_id'):
                record_state.append([record.student_id, record.year_level, record.section])
                if record.year_level != year and not ('Capstone' in level and record.year_level in ('3rd Year', '4th Year')):
                    issues.append(f'{record.student.username} is enrolled in another year level.')
                if row['section'] and not empty_section(record.section) and record.section != row['section']:
                    if not is_manager(user) or data.get('resolve_conflicts') is not True:
                        issues.append(f'{record.student.username}: existing section {record.section}; ask your lead to review the reassignment.')
                    else:
                        warnings.append(f'{record.student.username}: section changes from {record.section} to {row["section"]}.')
            from .roster_enrollment import missing_enrollment_issues
            issues.extend(missing_enrollment_issues(resolved, term))
            if len(resolved) != len(set(resolved)):
                issues.append('The same student is listed more than once in this team.')
            if (not event or event.team_membership_policy != 'multiple') and batch_members.intersection(resolved):
                issues.append('A student appears in more than one team in this file. Review the event membership setting or fix the rows.')
            batch_members.update(resolved)
            payload = {'name': name, 'level': level, 'year_level': year, 'section': row['section'],
                'semester_id': term.pk, 'member_ids': resolved, 'leader_id': leader.pk if leader else 0,
                'adviser_id': adviser_id, 'project_title': row.get('project_title') or (existing.project_title if existing else ''),
                'current_defense_stage': event.event_name if event else None}
            validator = StudentTeamWriteSerializer(instance=existing, data=payload,
                context={'user': user, 'assigned_by': user, 'team_id': existing.pk if existing else None,
                         'preserve_section': True, 'formation': True, 'roster_import': True})
            if not issues:
                try:
                    validator.is_valid(raise_exception=True)
                except APIException as exc:
                    issues.append(readable_error(exc))
        action = 'update' if existing else 'create'
        if existing:
            warnings.append('Existing team matched. Review its changes before importing; no duplicate team will be created.')
        from .participation import roster_preview as participation_preview
        participations = participation_preview(payload['member_ids'], term) if payload and 'Capstone' in level and not issues else []
        results.append({'row': index, 'team_name': name, 'section': row['section'],
            'ready': not issues, 'issues': issues, 'warnings': warnings, 'action': action,
            'member_count': len(payload['member_ids']) if payload else 0, 'participation_preview': participations})
        state.append({'payload': payload, 'records': record_state, 'existing_id': existing.pk if existing else None,
                      'participations': participations,
                      'updated_at': existing.updated_at.isoformat() if existing else None,
                      'members': list(existing.memberships.order_by('student_id').values_list('student_id', flat=True)) if existing else [],
                      'issues': issues})
    from collections import Counter
    repeated_names = Counter(r['team_name'] for r in results)
    repeated_members = Counter(i for r in state if r['payload'] for i in r['payload']['member_ids'])
    for row, saved in zip(results, state):
        repeated = repeated_names[row['team_name']] > 1 or ((not event or event.team_membership_policy != 'multiple')
            and saved['payload'] and any(repeated_members[i] > 1 for i in saved['payload']['member_ids']))
        if repeated:
            row['ready'] = False
            row['issues'].append('Repeated team name or student across rows. Resolve the overlapping rows before importing.')
    # Replacement sections and shared projects are indivisible. Independent
    # current-roster imports can retain the existing ready-row import behavior.
    blocked_sections = {r['section'] for r in results if not r['ready'] and
        (data.get('roster_override') or setups.get(r['section'], {}).get('architecture') == 'shared')}
    for row, saved in zip(results, state):
        if row['section'] in blocked_sections and row['ready']:
            row['ready'] = False
            saved['issues'] = row['issues'] = ['Resolve all rows in this section before importing its complete roster/project setup.']
    return term, event, results, state


def import_ready(user, data, rows):
    return bool(rows) and (any(r['ready'] for r in rows) if 'PIT' in data.get('level', '') and is_manager(user) and data.get('partial') is True
        else all(r['ready'] for r in rows))


def import_state(term, event, state):
    from .pit_rosters import resolve
    years = {r['payload']['year_level'] for r in state if r['payload'] and 'PIT' in r['payload']['level']}
    return [term.pk, event.team_membership_policy if event else 'single', state,
        {year: resolve(term.pk, year, event.pk if event else None) for year in years}]


class PreparedTeamsPreviewView(APIView):
    permission_classes = [CanFormTeams]

    def post(self, request):
        term, event, rows, state = team_import_preview(request.user, request.data)
        ready = import_ready(request.user, request.data, rows)
        return Response({'rows': rows, 'ready': ready,
            'preview_token': seal(request.user, 'teams', dict(request.data),
                import_state(term, event, state)) if ready else None})


class PreparedTeamsCommitView(ImportAPIView):
    permission_classes = [CanFormTeams]

    @transaction.atomic
    def post(self, request):
        token = request.data.get('preview_token', '')
        preview = open_preview(request.user, token, 'teams')
        term, level, year, event = formation.formation_scope(request.user, preview['data'], lock=True, generation=False)
        list(User.objects.select_for_update().filter(pk=request.user.pk))
        previous = receipt(request.user, token, 'teams.prepared_import')
        if previous:
            return Response({k: v for k, v in previous.new_values.items() if k != 'preview_id'})
        ids = sorted({i for row in preview['state'][2] for i in (row['payload'] or {}).get('member_ids', [])})
        list(User.objects.select_for_update().filter(pk__in=ids).order_by('pk'))
        list(StudentTeam.objects.select_for_update().filter(pk__in=[r['existing_id'] for r in preview['state'][2] if r['existing_id']]).order_by('pk'))
        list(StudentAcademicRecord.objects.select_for_update().filter(student_id__in=ids, semester=term).order_by('pk'))
        from .roster_enrollment import require_roster_enrollment
        require_roster_enrollment(ids, term, lock=True)
        term, event, rows, state = team_import_preview(request.user, preview['data'])
        if import_state(term, event, state) != preview['state'] or not import_ready(request.user, preview['data'], rows):
            raise ValidationError('Teams, roster, or event settings changed. Review the import again.')
        from .pit_rosters import replacement_import
        sections = {r['payload']['section'] for r in state if r['payload']}
        with replacement_import(request.user, event, sections, preview['data'].get('roster_override') is True):
            return self.save_rows(request, token, preview, term, level, year, event, state)

    def save_rows(self, request, token, preview, term, level, year, event, state):
        created, updated, team_ids = 0, 0, []
        from .pit_rosters import ensure_current
        if 'PIT' in level and (not event or preview['data'].get('roster_override') is True):
            ensure_current(term.pk, year, {r['payload']['section'] for r in state if not r['issues']})
        for row, saved in zip(preview['data']['teams'], state):
            if saved['issues']:
                continue
            existing = StudentTeam.objects.filter(pk=saved['existing_id']).first() if saved['existing_id'] else None
            serializer = StudentTeamWriteSerializer(instance=existing, data=saved['payload'], context={
                'user': request.user, 'assigned_by': request.user, 'team_id': existing.pk if existing else None,
                'preserve_section': True, 'formation': True, 'roster_import': True})
            serializer.is_valid(raise_exception=True)
            assignment, _ = imported_concept_requirement({**row, 'level': level, 'year_level': year,
                'current_defense_stage': event.event_name if event else '', 'section': saved['payload']['section']})
            team = serializer.save(**({} if existing else {'concept_assignment': assignment,
                                   'project_pending': not bool(saved['payload']['project_title'])}))
            setup = preview['data'].get('project_setups', {}).get(team.section, {})
            if is_manager(request.user) and row.get('instructor_name') and team.section:
                instructor, _ = resolve_user_by_full_name(row['instructor_name'], role=['faculty', 'admin'], field_label='Instructor')
                if instructor:
                    SectionInstructorAssignment.objects.update_or_create(faculty=instructor, semester=term,
                        year_level=year, section=team.section, defaults={'assigned_by': request.user, 'is_active': True})
            team_ids.append(team.pk)
            created += existing is None
            updated += existing is not None
        from .pit_rosters import register
        saved_teams = list(StudentTeam.objects.filter(pk__in=team_ids))
        if not event or preview['data'].get('roster_override') is True:
            register(saved_teams, request.user, event=event, replace=bool(event))
        for section, config in preview['data'].get('project_setups', {}).items():
            if config.get('architecture') != 'shared' or not any(t.section == section for t in saved_teams):
                continue
            from repository.section_concepts.services import configure
            context = formation.generation_concept_context(event, config, semester=term,
                pit_year=year if 'PIT' in level else None)
            configure(request.user, [t for t in saved_teams if t.section == section], context, config)
        result = {'created_count': created, 'updated_count': updated, 'team_ids': team_ids, 'skipped_count': sum(bool(r['issues']) for r in state)}
        record_receipt(request, token, 'teams.prepared_import', team, result)
        return Response(result, status=201)
