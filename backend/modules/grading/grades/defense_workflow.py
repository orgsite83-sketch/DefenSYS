"""Defense outcomes, clearance, and authorized recovery, independent of dates."""
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from student_teams.models import StudentTeam, TeamRecoveryAuthorization, TeamStageProgress
from .models import TeamGrade


def is_admin(user):
    return bool(user and (getattr(user, 'role', None) == 'admin' or user.is_superuser))


def is_chair(grade, user):
    return bool(grade.schedule_id and grade.schedule.panel_assignments.filter(panelist=user, is_chair=True).exists())


def passed_and_cleared(grade):
    if grade.verdict == TeamGrade.VERDICT_APPROVED:
        return True
    if grade.verdict == TeamGrade.VERDICT_APPROVED_WITH_REVISIONS:
        return bool(grade.revisions_cleared_at)
    return grade.scope == TeamGrade.SCOPE_PIT and grade.result == 'passed'


def recovery_for(team, stage):
    return TeamRecoveryAuthorization.objects.filter(
        team=team, semester=team.semester, defense_stage=stage,
        project_version=team.project_version, action='retake', consumed_at__isnull=True,
    ).first()


def replacement_for(team, stage):
    return TeamRecoveryAuthorization.objects.filter(
        team=team, semester=team.semester, defense_stage=stage, action='new_concept',
        replacement_project_version=team.project_version, consumed_at__isnull=True,
    ).first()


def require_current(grade):
    if grade.project_version != grade.team.project_version:
        raise ValidationError('This assessment belongs to a previous project and is read-only.')


def audit(grade, actor, action, **values):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_GRADE_CENTER, action=action,
                           target=grade, actor=actor, new_values={
                               'team_id': grade.team_id, 'stage_label': grade.stage_label,
                               'project_version': grade.project_version, **values,
                           }, strict=True)


@transaction.atomic
def record_verdict(grade, *, actor, verdict, remarks='', deadline=None, verification_required=False):
    StudentTeam.objects.select_for_update().get(pk=grade.team_id)
    if grade.schedule_id:
        from defense.scheduler.models import DefenseSchedule
        DefenseSchedule.objects.select_for_update().get(pk=grade.schedule_id)
    grade = TeamGrade.objects.select_for_update(of=('self',)).select_related('team', 'schedule', 'semester').get(pk=grade.pk)
    require_current(grade)
    if not (is_admin(actor) or is_chair(grade, actor)):
        raise PermissionError('Only the panel chair or an administrator can record a verdict.')
    if verdict not in dict(TeamGrade.VERDICT_CHOICES):
        raise ValidationError('Select a valid defense verdict.')
    if grade.status == TeamGrade.STATUS_PUBLISHED:
        raise ValidationError('This grade is finalized. Use the correction process before changing its verdict.')
    from defense.scheduler.panelist_evaluation import verdict_unavailable_reason
    from .services import team_grading_readiness
    if grade.schedule_id:
        reason = verdict_unavailable_reason(grade.schedule, grade)
        if reason:
            raise ValidationError(reason)
    elif not team_grading_readiness(grade, grade.semester, grade.scope)['panel_complete']:
        raise ValidationError('Every required panel evaluation must be submitted before a verdict.')
    if verdict in (TeamGrade.VERDICT_FOR_REDEFENSE, TeamGrade.VERDICT_FAILED, TeamGrade.VERDICT_PROJECT_REJECTED) and not remarks.strip():
        raise ValidationError('Record the reason and required action for this outcome.')
    grade.verdict = verdict
    grade.verdict_remarks = remarks.strip()
    grade.verdict_by = actor
    grade.verdict_at = timezone.now()
    grade.revision_deadline = deadline if verdict == TeamGrade.VERDICT_APPROVED_WITH_REVISIONS else None
    grade.revisions_cleared_at = None
    grade.revisions_cleared_by = None
    grade.clearance_remarks = ''
    grade.compliance_review_date = None
    grade.redefense_verification_required = bool(verification_required and verdict == TeamGrade.VERDICT_FOR_REDEFENSE)
    grade.redefense_verified_at = None
    grade.redefense_verified_by = None
    grade.save()
    if grade.schedule_id and grade.schedule.status == 'scheduled':
        from defense.scheduler.services import transition_schedule_status
        transition_schedule_status(grade.schedule, 'done', actor=actor, reason='panel_attempt_assessed')
        grade.schedule.refresh_from_db()
    from .services import _apply_team_result_from_grade, maybe_auto_finalize_passed_grade
    _apply_team_result_from_grade(grade)
    maybe_auto_finalize_passed_grade(grade, user=actor)
    audit(grade, actor, 'defense.verdict_submitted', verdict=verdict, verdict_remarks=remarks,
          verification_required=grade.redefense_verification_required)
    return grade


def workflow_payload(grade):
    from repository.deliverables.models import DeliverableSubmission
    from defense.scheduler.models import DefenseSchedule
    authorization = recovery_for(grade.team, grade.defense_stage) if grade.defense_stage_id else None
    records = grade.team.recovery_authorizations.select_related('authorized_by', 'defense_stage', 'semester')
    return {
        'chair_id': grade.schedule.panel_assignments.filter(is_chair=True).values_list('panelist_id', flat=True).first() if grade.schedule_id else None,
        'adviser_id': grade.team.adviser_id,
        'passed_and_cleared': passed_and_cleared(grade),
        'revisions_pending': grade.verdict == 'approved_with_revisions' and not grade.revisions_cleared_at,
        'retake_authorized': bool(authorization),
        'redefense_ready': (grade.verdict == 'for_redefense' or bool(authorization)) and (
            not grade.redefense_verification_required or bool(grade.redefense_verified_at)),
        'previous_projects': [{'version': g.project_version, 'title': g.project_title_snapshot,
                               'grade_id': g.pk, 'stage_label': g.stage_label, 'verdict': g.verdict}
                              for g in TeamGrade.all_objects.filter(team=grade.team).exclude(project_version=grade.team.project_version).order_by('project_version', 'id')],
        'project_files': [{'id': f.pk, 'name': f.file_name or f.label,
                           'stage_label': f.stage_label, 'status': f.status,
                           'file_url': f.file.url if f.file else None}
                          for f in DeliverableSubmission.all_objects.filter(team=grade.team,
                              project_version=grade.project_version).order_by('stage_label', 'id')],
        'defense_records': [{'schedule_id': s.pk, 'date': str(s.scheduled_date),
                             'stage_label': s.stage_label, 'status': s.status,
                             'minutes_id': s.minutes.pk if hasattr(s, 'minutes') else None}
                            for s in DefenseSchedule.objects.filter(team=grade.team,
                                project_version=grade.project_version).select_related('minutes').order_by('scheduled_date', 'id')],
        'recovery_history': [{'id': r.pk, 'action': r.action, 'reason': r.reason,
                              'stage_label': r.defense_stage.label, 'academic_period': r.semester.display_name,
                              'project_version': r.project_version, 'previous_project_title': r.previous_project_title,
                              'replacement_project_version': r.replacement_project_version,
                              'authorized_at': r.authorized_at.isoformat(),
                              'authorized_by': r.authorized_by.get_full_name() or r.authorized_by.username if r.authorized_by else '',
                              'consumed': bool(r.consumed_at)} for r in records],
    }


@transaction.atomic
def apply_workflow_action(grade, *, actor, action, reason='', project_title='', review_date=None):
    team = StudentTeam.objects.select_for_update().get(pk=grade.team_id)
    grade = TeamGrade.objects.select_for_update(of=('self',)).select_related('team', 'defense_stage', 'semester').get(pk=grade.pk)
    require_current(grade)
    if grade.scope != TeamGrade.SCOPE_CAPSTONE:
        raise ValidationError('Recovery and revision clearance apply to Capstone defenses.')
    is_assigned_adviser = bool(team.adviser_id and team.adviser_id == actor.pk)
    if action in ('clear_revisions', 'schedule_compliance_review'):
        if not (is_admin(actor) or is_chair(grade, actor) or is_assigned_adviser):
            raise PermissionError('Only the panel chair, assigned adviser, or an administrator can manage revision clearance.')
        if grade.verdict != 'approved_with_revisions':
            raise ValidationError('This defense does not have a revision-clearance outcome.')
        if grade.status == 'published':
            raise ValidationError('This assessment is finalized.')
        if action == 'clear_revisions':
            if not reason.strip():
                raise ValidationError('Record which corrections and evidence were verified.')
            grade.revisions_cleared_at = timezone.now()
            grade.revisions_cleared_by = actor
            grade.clearance_remarks = reason.strip()
        else:
            if review_date is None:
                raise ValidationError('Choose a compliance review date.')
            grade.compliance_review_date = review_date
        grade.save()
        from .services import _apply_team_result_from_grade, maybe_auto_finalize_passed_grade
        _apply_team_result_from_grade(grade)
        maybe_auto_finalize_passed_grade(grade, user=actor)
    elif action == 'verify_redefense':
        if not (is_admin(actor) or team.adviser_id == actor.pk):
            raise PermissionError('Only the assigned adviser or an administrator can verify corrections.')
        if grade.verdict != 'for_redefense' or not grade.redefense_verification_required:
            raise ValidationError('No adviser verification is required for this attempt.')
        if not reason.strip():
            raise ValidationError('Record the corrections that were verified.')
        grade.redefense_verified_at = timezone.now()
        grade.redefense_verified_by = actor
        grade.clearance_remarks = reason.strip()
        grade.save()
    elif action in ('authorize_retake', 'authorize_new_concept', 'keep_blocked'):
        if not is_admin(actor):
            raise PermissionError('Only an administrator can record a recovery authorization.')
        if grade.verdict not in ('failed', 'project_rejected'):
            raise ValidationError('Recovery authorization requires a Failed or Project Rejected verdict.')
        if not reason.strip():
            raise ValidationError('Record the institutional decision or authorization reference.')
        if action == 'keep_blocked':
            TeamRecoveryAuthorization.objects.filter(team=team, project_version=team.project_version,
                defense_stage=grade.defense_stage, action='retake', consumed_at__isnull=True).update(consumed_at=timezone.now())
        elif action == 'authorize_retake':
            if grade.verdict == 'project_rejected':
                raise ValidationError('A rejected concept needs an authorized replacement concept.')
            if recovery_for(team, grade.defense_stage):
                raise ValidationError('Another attempt is already authorized for this outcome.')
            TeamRecoveryAuthorization.objects.create(team=team, semester=team.semester, defense_stage=grade.defense_stage,
                project_version=team.project_version, previous_project_title=team.project_title,
                action='retake', reason=reason.strip(), authorized_by=actor)
        else:
            if not project_title.strip() or len(project_title.strip()) > 255:
                raise ValidationError('Enter a replacement concept title (up to 255 characters).')
            from defense.stages.models import DefenseStage
            first_stage = DefenseStage.objects.filter(is_active=True).order_by('display_order', 'id').first()
            if not first_stage:
                raise ValidationError('Configure the first defense stage before creating a replacement concept.')
            TeamRecoveryAuthorization.objects.create(team=team, semester=team.semester, defense_stage=first_stage,
                project_version=team.project_version, previous_project_title=team.project_title,
                replacement_project_version=team.project_version+1, replacement_project_title=project_title.strip(),
                action='new_concept', reason=reason.strip(), authorized_by=actor)
            team.project_version += 1
            team.project_title = project_title.strip()
            team.status = StudentTeam.STATUS_PENDING
            team.current_defense_stage = first_stage.label
            team.ready_for_stage = None
            team.unlocked_stages = []
            team.save(update_fields=['project_version', 'project_title', 'status', 'current_defense_stage', 'ready_for_stage', 'unlocked_stages', 'updated_at'])
            TeamStageProgress.objects.create(team=team, semester=team.semester, defense_stage=first_stage,
                status=TeamStageProgress.STATUS_LOCKED, created_by=actor, updated_by=actor)
            from .services import GradeContextService
            GradeContextService.get_or_create_unscheduled_team(team, stage_label=first_stage.label)
    else:
        raise ValidationError('Select a valid workflow action.')
    audit(grade, actor, f'defense.{action}', reason=reason, replacement_project_title=project_title,
          review_date=str(review_date) if review_date else None)
    return team
