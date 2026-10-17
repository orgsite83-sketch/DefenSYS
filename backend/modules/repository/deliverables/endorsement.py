"""Review the displayed scheduling files and endorse in one transaction."""
from django.core import signing
from django.db import transaction

from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from student_teams.models import StudentTeam
from student_teams.services import was_stage_endorsed
from .models import DeliverableSubmission
from .timing import scheduling_requirement


class StaleEndorsementReview(ValueError):
    pass


def endorsement_blocker(team, stage_label):
    from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
    from defense.stages.models import StageGradingConfig
    from .services import defense_stage_for_label, is_stage_defense_done

    if not team.semester_id or not team.semester.is_active:
        return 'Only teams in the active semester can be reviewed and endorsed.'
    from .concepts import stage_for
    stage = stage_for(team, stage_label)
    endorsed = was_stage_endorsed(team, stage) if stage else team.ready_for_stage == stage_label
    if endorsed:
        return 'This team is already endorsed.'
    schedules = DefenseSchedule.objects.filter(
        team=team, project_version=team.project_version, semester=team.semester,
        status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE],
    )
    schedules = schedules.filter(defense_stage=stage, scope='capstone') if team.is_capstone else schedules.filter(event_name__iexact=stage_label, scope='pit')
    from .concepts import latest_round
    current = latest_round(team, stage)
    preparing_next = bool(current and current.number > 1 and not current.schedule_id)
    if not preparing_next and (schedules.exists() or is_stage_defense_done(team, stage_label)):
        return 'This defense is already scheduled or complete.'
    config = (StageGradingConfig.objects.filter(defense_stage=stage, semester=team.semester)
              if team.is_capstone else PitEventGradingConfig.objects.filter(event_name__iexact=stage_label, semester=team.semester, year_level=team.year_level))
    if not preparing_next and config.filter(is_officially_complete=True).exists():
        return 'This stage is officially complete.'
    return ''


def endorsement_review(team, stage_label, *, definitions=None, submitted=None):
    from .services import get_deliverable_definitions_for_team, submissions_for, stage_deliverables_configured

    definitions = definitions if definitions is not None else get_deliverable_definitions_for_team(team, stage_label)
    submitted = submitted if submitted is not None else submissions_for(team, stage_label)
    required = sorted((d for d in definitions if scheduling_requirement(d)), key=lambda d: d['id'])
    files, snapshot = [], []
    reason = endorsement_blocker(team, stage_label)
    if not stage_deliverables_configured(team, stage_label):
        reason = reason or 'Configure the stage deliverables first.'
    if team.is_pit and not required:
        reason = reason or 'This PIT event does not require endorsement.'
    for item in required:
        submission = submitted.get(item['id'])
        from .documents import completeness, current_files
        from .services import defense_stage_for_label
        from .concepts import stage_for
        stage = stage_for(team, stage_label)
        has_file = bool(submission and submission.file) and completeness(submission, item, stage=stage)
        files.append({'id': item['id'], 'label': item['label'],
                      'file_name': submission.file_name if has_file else '',
                      'status': submission.status if submission else 'missing'})
        if not has_file:
            reason = reason or 'Upload all required before-endorsement files first.'
        elif submission.status == DeliverableSubmission.STATUS_REJECTED or submission.file_replacement_unlocked:
            reason = reason or 'The team must submit the requested corrections first.'
        snapshot.append({
            'definition': item,
            'submission': None if submission is None else {
                'id': submission.pk, 'file': submission.file.name,
                'file_name': submission.file_name,
                'uploaded_at': submission.uploaded_at.isoformat(),
                'status': submission.status,
                'replacement': submission.file_replacement_unlocked,
                'revision': submission.revision_review_unlocked,
                'documents': [(f.pk, f.revision, f.status) for f in current_files(submission)],
            },
        })
    review_snapshot = {'team': team.pk, 'project_version': team.project_version,
                       'semester': team.semester_id, 'stage': stage_label, 'files': snapshot}
    from .concepts import stage_for, latest_round
    concept_round = latest_round(team, stage_for(team, stage_label))
    if concept_round:
        review_snapshot['concepts'] = {'round': concept_round.number, 'titles': concept_round.concepts}
    return {
        'can_review_and_endorse': not reason,
        'reason': reason,
        'files': files,
        'review_token': signing.Signer(salt='deliverables.review-endorse').sign_object(review_snapshot, compress=True) if not reason else '',
    }


@transaction.atomic
def review_and_endorse(team, stage_label, *, actor, review_token):
    from .services import team_queryset_for_user, endorse_team, review_submission

    # Same lock order as uploads, removal and approved-file replacement requests.
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    if not (actor.is_superuser or actor.role in ('admin', 'faculty')) or not team_queryset_for_user(actor).filter(pk=team.pk).exists():
        raise PermissionError('Only assigned faculty or an Admin can review and endorse this team.')
    if actor.role == 'faculty' and team.is_capstone and not (actor.is_adviser and team.adviser_id == actor.pk):
        raise PermissionError('Only the assigned adviser or an Admin can endorse this Capstone team.')
    submitted = {s.deliverable_id: s for s in DeliverableSubmission.objects.select_for_update().filter(
        team=team, stage_label=stage_label).order_by('deliverable_id')}
    review = endorsement_review(team, stage_label, submitted=submitted)
    signer = signing.Signer(salt='deliverables.review-endorse')
    try:
        matches = signer.unsign_object(review_token) == signer.unsign_object(review['review_token'])
    except (signing.BadSignature, ValueError, TypeError):
        matches = False
    if not review['can_review_and_endorse']:
        raise ValueError(review['reason'])
    if not matches:
        raise StaleEndorsementReview('The required files or checklist changed. Refresh and review the current files before endorsing.')
    before = {f['id']: submitted[f['id']].status for f in review['files']}
    previous_stage = team.ready_for_stage
    for item in review['files']:
        submission = submitted[item['id']]
        if submission.status != DeliverableSubmission.STATUS_ACCEPTED:
            review_submission(team, stage_label, item['id'], DeliverableSubmission.STATUS_ACCEPTED,
                              submission.feedback, actor)
    endorse_team(team, stage_label, user=actor)
    scope = audit_scope_metadata(team=team, scope='capstone' if team.is_capstone else 'pit')
    log_high_impact_action(
        category=SystemAuditLog.CATEGORY_REPOSITORY, action='repository.review_and_endorse',
        target=team, actor=actor, reason='Reviewed scheduling files and endorsed the team.',
        old_values={**scope, 'stage_label': stage_label, 'ready_for_stage': previous_stage, 'files': before},
        new_values={**scope, 'stage_label': stage_label, 'ready_for_stage': stage_label,
                    'files': {f['id']: DeliverableSubmission.STATUS_ACCEPTED for f in review['files']}},
        strict=True,
    )
    return team
