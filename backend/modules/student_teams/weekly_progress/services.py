"""Calendar, collection projection, and version-specific physical-report review.

Deadlines only describe timing. Writes enforce ownership and recorded evidence,
never a deadline-based upload cutoff. All writers lock team, then period, report.
"""
from datetime import date, datetime, time, timedelta
from hashlib import sha256
from pathlib import PurePath
from uuid import UUID
from zoneinfo import ZoneInfo

from django.conf import settings
from django.core.exceptions import ValidationError as DomainValidationError
from django.db import transaction
from django.db.models import Prefetch
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from defensys_backend.read_projection import read_memoize
from defense.weekly_reporting import WEEKLY_ID
from .models import WeeklyProgressReport, WeeklyReportVersion, WeeklyReportingPeriod

MANILA = ZoneInfo('Asia/Manila')
MAX_PDF_BYTES = getattr(settings, 'WEEKLY_REPORT_MAX_BYTES', 50 * 1024 * 1024)


def week_dates(config, week):
    start = date.fromisoformat(config['starts_on']) + timedelta(weeks=week - 1)
    due_day = start + timedelta(days=(int(config['due_weekday']) - start.weekday()) % 7)
    due = datetime.combine(due_day, time.fromisoformat(config['due_time']), tzinfo=MANILA)
    return start, start + timedelta(days=6), due


def report_queryset():
    return WeeklyProgressReport.objects.select_related('team').prefetch_related(Prefetch('versions',
        queryset=WeeklyReportVersion.objects.filter(is_current=True).select_related('reviewed_by', 'uploaded_by')))


@read_memoize
def reports_for_collection(team, config):
    from defense.weekly_reporting import period_for
    period = period_for(config.get('period_id'))
    if period is None or not config.get('defense_stage_id') or period.defense_stage_id != config['defense_stage_id']:
        return []
    prefetched = getattr(team, '_prefetched_objects_cache', {}).get('student_progress_reports')
    if prefetched is not None:
        return [r for r in prefetched if r.period_id == config.get('period_id')
            and r.semester_id == team.semester_id and r.project_version == team.project_version]
    return list(report_queryset().filter(team=team, period_id=config.get('period_id'),
        period__defense_stage_id=config['defense_stage_id'],
        semester_id=team.semester_id, project_version=team.project_version))


def current_version(report):
    if report is None:
        return None
    return next((v for v in report.versions.all() if v.is_current), None)


def can_read_report(actor, report, *, team=None):
    if actor is None:
        return False
    team = team or report.team
    leader = bool(report.period_id and actor.role == 'student' and team.leader_id == actor.pk
        and team.semester.is_active and report.semester_id == team.semester_id
        and report.project_version == team.project_version)
    return bool(actor.is_superuser or actor.role == 'admin' or leader
        or actor.role == 'student' and report.student_id == actor.pk
        or actor.role == 'faculty' and actor.is_adviser and report.team.adviser_id == actor.pk)


def version_payload(version):
    return {'id': version.pk, 'revision': version.revision, 'is_current': version.is_current,
        'file_name': version.file_name, 'file_size': f'{version.byte_size / 1024:.1f} KB',
        'file_url': f'/api/teams/weekly-progress/{version.report_id}/file/?version_id={version.pk}',
        'uploaded_at': version.uploaded_at.isoformat(), 'status': version.status,
        'feedback': version.feedback, 'reviewed_at': version.reviewed_at.isoformat() if version.reviewed_at else None,
        'reviewed_by': version.reviewed_by_id,
        'reviewer_name': version.reviewed_by.get_full_name() if version.reviewed_by_id else '',
        'uploaded_by': version.uploaded_by_id}


@read_memoize
def write_blockers(team, config):
    from student_teams.participation import require_open
    from defense.stages.models import DefenseStage, StageGradingConfig
    from defense.scheduler.models import DefenseSchedule
    base = ''
    try:
        require_open(team)
    except (ValidationError, DomainValidationError, PermissionError) as exc:
        base = str(exc)
    if not base and not team.semester.is_active:
        base = 'Historical reporting periods are read-only.'
    if not base and team.term_participations.filter(semester_id=team.semester_id, closed_at__isnull=False).exists():
        base = 'This term participation is closed.'
    if base:
        return {week: base for week in range(1, config['total_weeks'] + 1)}
    stages = list(DefenseStage.objects.filter(pk=config.get('defense_stage_id'),
        weekly_reporting__enabled=True, weekly_reporting__period_id=config.get('period_id')))
    closed = set(StageGradingConfig.objects.filter(defense_stage__in=stages,
        semester_id=team.semester_id, is_officially_complete=True).values_list('defense_stage_id', flat=True))
    retained = set(DefenseSchedule.objects.filter(team=team, semester_id=team.semester_id,
        project_version=team.project_version, defense_stage__in=stages,
        status__in=['scheduled', 'done', 'archived']).values_list('defense_stage_id', flat=True))
    blockers = {}
    for stage in stages:
        policy = stage.weekly_reporting
        from repository.deliverables.stage_access import manually_locked, deliverable_override
        specific = deliverable_override(team, stage.label, WEEKLY_ID)
        reason = ('This weekly report is part of a completed stage.' if stage.pk in closed else
            'This weekly report is retained as scheduled or completed hearing evidence.' if stage.pk in retained else
            'Weekly report uploads are locked by an administrator.' if specific is False or (
                specific is None and manually_locked(team, stage.label, 'pre')) else '')
        if reason:
            for number in range(policy['required_start'], policy['required_end'] + 1):
                blockers.setdefault(number, reason)
    return blockers


def write_blocker(team, config, week):
    return write_blockers(team, config).get(week, '')


def collection_state(team, definition, *, actor=None, details=False, now=None):
    config = definition.get('weekly_reporting') or {}
    now = now or timezone.now()
    if not config.get('period_id') or not config.get('starts_on'):
        return {**definition, 'uploaded': False, 'completed': False, 'submission': None,
            'weekly_summary': {'required': 0, 'uploaded': 0, 'accepted': 0},
            'weekly_blocker': 'Complete weekly reporting setup first.', 'weeks': []}
    reports = {r.week_number: r for r in reports_for_collection(team, config)}
    required = range(config['required_start'], config['required_end'] + 1)
    counts = {key: 0 for key in ('uploaded', 'accepted', 'pending', 'rejected', 'missing', 'late', 'overdue')}
    slots, files, weeks, missing, pending, corrections = [], [], [], [], [], []
    blockers = write_blockers(team, config) if details else {}
    for number in required:
        start, end, due = week_dates(config, number)
        report = reports.get(number)
        version = current_version(report)
        submitted = bool(version and version.file)
        status = version.status if submitted else 'missing'
        first_at = report.submitted_at if report else None
        timing = ('late' if first_at > due else 'on_time') if submitted else (
            'overdue' if now > due else 'upcoming' if now.astimezone(MANILA).date() < start else 'due')
        is_required = number in required
        if is_required:
            counts['uploaded'] += int(submitted)
            counts['accepted'] += int(submitted and status == 'accepted')
            counts['pending'] += int(submitted and status == 'pending')
            counts['rejected'] += int(submitted and status == 'rejected')
            counts['missing'] += int(not submitted)
            counts['late'] += int(timing == 'late')
            counts['overdue'] += int(timing == 'overdue')
            if not submitted:
                missing.append(number)
            elif status == 'rejected':
                corrections.append(number)
            elif status != 'accepted':
                pending.append(number)
        may_read = report is not None and can_read_report(actor, report, team=team)
        visible = version_payload(version) if submitted and may_read else None
        if visible:
            visible['slot_key'] = f'week:{number}'
            visible['timing'] = timing
            visible['report_id'] = report.pk
        if is_required:
            slots.append({'key': f'week:{number}', 'label': f'Week {number}', 'required': True,
                'file_format': 'pdf'})
            if visible:
                files.append(visible)
        if details:
            blocker = blockers.get(number, '')
            leader = bool(actor and actor.role == 'student' and actor.pk == team.leader_id)
            owner = report is None or leader or bool(actor and report.student_id == actor.pk)
            reviewer = bool(actor and actor.role == 'faculty' and actor.is_adviser and team.adviser_id == actor.pk)
            weeks.append({'week_number': number, 'required': is_required, 'starts_on': str(start),
                'ends_on': str(end), 'due_at': due.isoformat(), 'timing': timing, 'status': status,
                'file': visible, 'report_id': report.pk if may_read else None,
                'first_submitted_at': first_at.isoformat() if first_at else None,
                'can_upload': leader and owner and not blocker and status != 'accepted',
                'can_review': reviewer and submitted and not blocker,
                'blocker': blocker or ('Accepted reports require a correction request before replacement.'
                    if status == 'accepted' else ''),
                'history_url': f'/api/teams/weekly-progress/{report.pk}/versions/' if may_read else None})
    complete = counts['accepted'] == len(required)
    status = 'accepted' if complete else 'rejected' if counts['rejected'] else 'pending'
    reasons = []
    for numbers, label in ((missing, 'missing'), (pending, 'awaiting adviser acceptance'), (corrections, 'need correction')):
        if numbers:
            reasons.append('Weeks ' + ', '.join(map(str, numbers)) + ' ' + label)
    current = (now.astimezone(MANILA).date() - date.fromisoformat(config['starts_on'])).days // 7 + 1
    return {**definition, 'document_slots': slots, 'uploaded': counts['uploaded'] == len(required),
        'completed': complete, 'locked': False, 'can_upload': False, 'can_faculty_review': False,
        'submission': {'status': status, 'files': files, 'file_name': '', 'file_url': None,
            'feedback': '', 'uploaded_at': None} if counts['uploaded'] else None,
        'weekly_summary': {'required': len(required), **counts},
        'weekly_blocker': 'Weekly reports incomplete: ' + '; '.join(reasons) + '.' if reasons else '',
        'current_week': 0 if current < config['required_start'] else min(current, config['required_end']),
        'period_ended': current > config['required_end'], 'weeks': weeks}


def weekly_definition_for(team, stage_label):
    from repository.deliverables.services import get_deliverable_definitions_for_team
    from student_teams.capstone_lifecycle import requirements_for
    if not any(r['label'].casefold() == str(stage_label).casefold() for r in requirements_for(team)):
        return None
    return next((d for d in get_deliverable_definitions_for_team(team, stage_label)
        if d.get('source') == 'weekly_reports'), None)


def require_definition(team, stage_label):
    definition = weekly_definition_for(team, stage_label)
    if not team.is_capstone or not definition:
        raise ValidationError('Weekly reporting is not configured for this team and stage.')
    period = period_for_definition(definition)
    from defense.stages.context import stage_for_label
    stage = stage_for_label(stage_label, team=team)
    if (period is None or period.semester_id != team.semester_id
            or stage is None or period.defense_stage_id != stage.pk):
        raise ValidationError('This reporting period does not belong to the selected team context.')
    definition['weekly_reporting'] = {**definition['weekly_reporting'], 'defense_stage_id': stage.pk}
    return definition


def period_for_definition(definition):
    return WeeklyReportingPeriod.objects.filter(pk=definition['weekly_reporting'].get('period_id')).first()


def audit(actor, target, action, **values):
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY, action=action,
        target=target, actor=actor, strict=True, new_values=values)


@transaction.atomic
def upload_report(team, stage_label, *, actor, week, file, request_id=None):
    from student_teams.models import StudentTeam
    expected_context = (team.semester_id, team.project_version)
    team = StudentTeam.objects.select_for_update().select_related('semester').get(pk=team.pk)
    if expected_context != (team.semester_id, team.project_version):
        raise ValidationError('The team term or project changed. Refresh before uploading.')
    definition = require_definition(team, stage_label)
    config = definition['weekly_reporting']
    WeeklyReportingPeriod.objects.select_for_update().get(pk=config['period_id'])
    definition = require_definition(team, stage_label)
    config = definition['weekly_reporting']
    if actor.role != 'student' or team.leader_id != actor.pk or not team.memberships.filter(student=actor).exists():
        raise PermissionError('Only the assigned team leader can upload weekly reports.')
    try:
        week = int(week)
        if not config['required_start'] <= week <= config['required_end']:
            raise ValueError()
        key = UUID(str(request_id)) if request_id else None
    except (TypeError, ValueError, AttributeError):
        raise ValidationError('Choose a valid configured week and upload identifier.')
    if reason := write_blocker(team, config, week):
        raise PermissionError(reason)
    name = PurePath(str(getattr(file, 'name', '')).replace('\\', '/')).name
    if (file is None or not 0 < file.size <= MAX_PDF_BYTES or not name.lower().endswith('.pdf')
            or len(name) > 255 or any(ord(char) < 32 for char in name)):
        raise ValidationError('Choose a non-empty PDF of up to 50 MB.')
    data = file.read()
    file.seek(0)
    try:
        import pypdfium2 as pdfium
        with pdfium.PdfDocument(data) as pdf:
            if not len(pdf):
                raise ValueError()
    except Exception as exc:
        raise ValidationError('Choose a readable PDF document.') from exc
    digest = sha256(data).hexdigest()
    if key and (previous := WeeklyReportVersion.objects.filter(request_id=key).select_related('report').first()):
        if (previous.report.team_id, previous.report.period_id, previous.report.project_version,
                previous.report.week_number, previous.uploaded_by_id, previous.sha256) != (
                team.pk, config['period_id'], team.project_version, week, actor.pk, digest):
            raise ValidationError('This upload identifier was already used for another file.')
        return previous
    report = WeeklyProgressReport.objects.select_for_update().filter(team=team, period_id=config['period_id'],
        project_version=team.project_version, week_number=week).first()
    current = current_version(report)
    if current and current.status == 'accepted':
        raise PermissionError('The adviser must request correction before an accepted report can be replaced.')
    if current and current.sha256 == digest and current.status == 'pending':
        return current
    if report is None:
        report = WeeklyProgressReport.objects.create(student=actor, team=team, period_id=config['period_id'],
            semester=team.semester, project_version=team.project_version, week_number=week,
            report_date=timezone.localdate())
    revision = max((v.revision for v in report.versions.all()), default=0) + 1
    report.versions.filter(is_current=True).update(is_current=False)
    version = WeeklyReportVersion(report=report, revision=revision, file_name=name,
        byte_size=file.size, sha256=digest, request_id=key, uploaded_by=actor)
    try:
        version.file.save(name, file, save=False)
        version.save()
        audit(actor, version, 'weekly_report.uploaded', team_id=team.pk, period_id=config['period_id'],
            week_number=week, revision=revision, semester_id=team.semester_id)
    except Exception:
        if version.file.name:
            version.file.storage.delete(version.file.name)
        raise
    return version


@transaction.atomic
def review_report(team, stage_label, *, actor, version_id, decision, feedback=''):
    from student_teams.models import StudentTeam
    expected_context = (team.semester_id, team.project_version)
    team = StudentTeam.objects.select_for_update().select_related('semester').get(pk=team.pk)
    if expected_context != (team.semester_id, team.project_version):
        raise ValidationError('The team term or project changed. Refresh before reviewing.')
    definition = require_definition(team, stage_label)
    config = definition['weekly_reporting']
    WeeklyReportingPeriod.objects.select_for_update().get(pk=config['period_id'])
    definition = require_definition(team, stage_label)
    config = definition['weekly_reporting']
    if actor.role != 'faculty' or not actor.is_adviser or team.adviser_id != actor.pk:
        raise PermissionError('Only the assigned Capstone adviser can review weekly reports.')
    version = WeeklyReportVersion.objects.select_for_update().select_related('report').filter(pk=version_id,
        report__team=team, report__period_id=config['period_id'], report__semester_id=team.semester_id,
        report__project_version=team.project_version,
        report__week_number__gte=config['required_start'], report__week_number__lte=config['required_end']).first()
    if version is None or not version.is_current:
        raise ValidationError('The report changed. Refresh and review the current PDF before accepting it.')
    if reason := write_blocker(team, config, version.report.week_number):
        raise PermissionError(reason)
    feedback = str(feedback or '').strip()
    if decision not in ('accepted', 'rejected') or (decision == 'rejected' and not feedback):
        raise ValidationError('Choose Accept or provide feedback when requesting correction.')
    if version.status == 'rejected' and decision == 'accepted':
        raise ValidationError('The student must submit a corrected version before acceptance.')
    if version.status == decision and version.feedback == feedback:
        return version
    version.status, version.feedback = decision, feedback
    version.reviewed_by, version.reviewed_at = actor, timezone.now()
    version.save(update_fields=['status', 'feedback', 'reviewed_by', 'reviewed_at'])
    audit(actor, version, 'weekly_report.reviewed', team_id=team.pk, week_number=version.report.week_number,
        decision=decision, feedback=feedback, semester_id=team.semester_id,
        reviewer_name=actor.get_full_name() or actor.username, reviewed_at=version.reviewed_at.isoformat())
    if decision == 'rejected':
        from defense.stages.models import DefenseStage
        from student_teams.services import was_stage_endorsed
        from repository.deliverables.services import unendorse_team
        for stage in DefenseStage.objects.filter(pk=config['defense_stage_id']):
            policy = stage.weekly_reporting
            if (policy['required_start'] <= version.report.week_number <= policy['required_end']
                    and was_stage_endorsed(team, stage)):
                unendorse_team(team, stage.label)
    return version
