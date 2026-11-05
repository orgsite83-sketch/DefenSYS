"""Adopt reviewed PIT concept hearings; optionally archive/replace private drafts."""
import json
import os
from hashlib import sha256
from pathlib import Path

from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction
from django.db.models import F
from django.utils import timezone

from defense.document_policy import validate_concept_config
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from grading.grades.models import TeamGrade
from grading.management.commands.automatic_outcome_adoption_report import adoption_row


class Command(BaseCommand):
    help = 'Preview PIT concept adoption. Apply requires named schedules, review token, and reason.'

    def add_arguments(self, parser):
        parser.add_argument('--event-id', type=int, required=True)
        parser.add_argument('--qualifying-score', required=True)
        parser.add_argument('--schedule-id', nargs='+', type=int, default=[])
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--review-token')
        parser.add_argument('--reason', default='')
        parser.add_argument('--replace-drafts', action='store_true',
            help='Explicitly replace unsubmitted drafts after saving a private archive. Submitted scores still block adoption.')
        parser.add_argument('--draft-archive', type=Path,
            help='New private JSON archive path; required when applying --replace-drafts.')

    def handle(self, *args, **options):
        apply, ids = options['apply'], options['schedule_id']
        replace_drafts = options['replace_drafts']
        if replace_drafts and not ids:
            raise CommandError('Replacing drafts requires explicitly named schedules.')
        if apply and replace_drafts and not options['draft_archive']:
            raise CommandError('Replacing drafts requires --draft-archive pointing to a new private file.')
        if options['draft_archive'] and not replace_drafts:
            raise CommandError('--draft-archive requires --replace-drafts.')
        if apply and (not options['review_token'] or not options['reason'].strip()):
            raise CommandError('Apply requires the preview review token and an adoption reason.')
        if len(options['reason']) > 5000:
            raise CommandError('Use an adoption reason of up to 5000 characters.')
        already_atomic = connection.in_atomic_block
        with transaction.atomic():
            if not apply and not already_atomic and connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            events = PitEventGradingConfig.objects.all()
            if apply:
                events = events.select_for_update()
            event = events.filter(pk=options['event_id']).first()
            if not event or not event.semester.is_active or event.is_officially_complete:
                raise CommandError('Choose an active, unfinished PIT event.')
            if not event.concept_config.get('enabled'):
                raise CommandError('This PIT event does not use Concept selection.')
            try:
                config = validate_concept_config({**event.concept_config,
                    'qualifying_score': options['qualifying_score']})
            except ValidationError as exc:
                raise CommandError(str(exc)) from exc
            grades = TeamGrade.objects.filter(scope='pit', pit_event_config=event,
                schedule__isnull=False).order_by('pk')
            if ids:
                grades = grades.filter(schedule_id__in=ids)
            if apply:
                from student_teams.models import StudentTeam
                list(StudentTeam.objects.select_for_update().filter(pk__in=grades.values('team_id')).order_by('pk'))
                list(DefenseSchedule.objects.select_for_update().filter(pk__in=grades.values('schedule_id')).order_by('pk'))
                grades = grades.select_for_update(of=('self',))
            grades = list(grades.select_related('team', 'semester', 'schedule'))
            rows = []
            archived_drafts = []
            for grade in grades:
                row = adoption_row(grade)
                drafts = grade.schedule.evaluation_drafts.order_by('pk')
                if apply:
                    drafts = drafts.select_for_update()
                draft_rows = list(drafts.values('id', 'schedule_id', 'panelist_id',
                    'guest_code_id', 'context_signature', 'submissions', 'updated_at'))
                row['drafts_to_replace'] = len(draft_rows) if replace_drafts else 0
                # A legacy team score cannot be reinterpreted as three concept
                # scores. Only explicitly authorized, unsubmitted drafts can go.
                if replace_drafts:
                    row['blockers'] = [b for b in row['blockers']
                        if b != 'A private evaluation draft already exists']
                    row['review_context'].append(draft_rows)
                    archived_drafts.extend(draft_rows)
                hearing = getattr(grade.schedule, 'concept_round', None)
                if not hearing:
                    row['blockers'].append('The hearing has no captured concept set')
                else:
                    from repository.deliverables.concepts import latest_round
                    current = latest_round(grade.team, event)
                    if not current or current.pk != hearing.pk:
                        row['blockers'].append('This is not the current concept hearing')
                    row['review_context'].append([hearing.pk, hearing.concepts, hearing.policy_snapshot])
                rubric = grade.schedule.rubric
                if (not rubric or rubric.pk != event.panel_rubric_id or rubric.status != 'published'):
                    row['blockers'].append('The published event panel rubric must match this hearing')
                elif not rubric.criteria.exists():
                    row['blockers'].append('The panel rubric has no criteria')
                else:
                    row['review_context'].append([rubric.pk, rubric.target_type,
                        list(rubric.criteria.order_by('pk').values('id', 'name', 'max_score', 'weight', 'target_type'))])
                if grade.semester_id != grade.team.semester_id or grade.team.year_level != event.year_level:
                    row['blockers'].append('The team no longer belongs to this event period and year')
                if grade.schedule.assessment_policy.get('automatic_outcomes'):
                    row['blockers'].append('This hearing already uses automatic outcomes')
                row['eligible'] = not row['blockers']
                rows.append(row)
            token = sha256(json.dumps({'event': event.pk, 'prior_config': event.concept_config,
                'weights': [event.panel_weight, event.peer_weight], 'cutoff': config['qualifying_score'],
                'hearings': rows}, sort_keys=True, default=str).encode()).hexdigest()
            if apply:
                if sorted(set(ids)) != sorted(row['schedule_id'] for row in rows):
                    raise CommandError('Name exactly the schedules included in this preview.')
                if token != options['review_token'] or any(not row['eligible'] for row in rows):
                    raise CommandError('The review changed or includes existing assessment evidence. Preview again.')
                if replace_drafts:
                    archive = options['draft_archive'].expanduser().resolve()
                    archive.parent.mkdir(parents=True, exist_ok=True)
                    # Exclusive creation prevents overwriting a recovery file.
                    # Save before deleting anything; a failed archive aborts DB writes.
                    try:
                        descriptor = os.open(archive, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
                            json.dump({'event_id': event.pk, 'schedule_ids': ids,
                                'review_token': token, 'reason': options['reason'],
                                'created_at': timezone.now().isoformat(), 'drafts': archived_drafts},
                                stream, indent=2, default=str)
                            stream.flush()
                            os.fsync(stream.fileno())
                    except OSError as exc:
                        raise CommandError(f'Could not save draft archive; no database changes applied: {exc}') from exc
                from authentication_access_control.audit import log_high_impact_action
                from authentication_access_control.models import SystemAuditLog
                from grading.grades.defense_workflow import audit
                from grading.grades.outcome_rules import capture_policy
                before = event.concept_config
                # Avoid model save synchronization: only the named untouched grades
                # may change. Existing graded hearings retain their policy and weights.
                PitEventGradingConfig.objects.filter(pk=event.pk).update(concept_config=config,
                    panel_weight=100, peer_weight=0, peer_grading_enabled=False, updated_at=timezone.now())
                event.concept_config = config
                log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING,
                    action='pit_event.concept_policy_adopted', target=event, reason=options['reason'],
                    old_values={'concept_config': before}, new_values={'concept_config': config}, strict=True)
                for grade in grades:
                    prior = grade.schedule.assessment_policy
                    policy = capture_policy(grade.schedule)
                    if not policy.get('automatic_outcomes'):
                        raise CommandError('Could not capture the configured PIT concept policy.')
                    DefenseSchedule.objects.filter(pk=grade.schedule_id).update(assessment_policy=policy,
                        revision=F('revision') + 1, updated_at=timezone.now())
                    TeamGrade.objects.filter(pk=grade.pk).update(panel_weight=100, peer_weight=0,
                        adviser_weight=0, updated_at=timezone.now())
                    if replace_drafts:
                        grade.schedule.evaluation_drafts.filter(
                            pk__in=[draft['id'] for draft in archived_drafts]).delete()
                    audit(grade, None, 'defense.pit_concept_policy_adopted', reason=options['reason'],
                        prior_policy=prior, adopted_policy=policy,
                        replaced_draft_count=next(row['drafts_to_replace'] for row in rows
                            if row['schedule_id'] == grade.schedule_id),
                        draft_archive=str(archive) if replace_drafts else None)
            for row in rows:
                row.pop('review_context')
        self.stdout.write(json.dumps({'read_only': not apply, 'event_id': event.pk,
            'qualifying_score': config['qualifying_score'], 'review_token': token,
            'hearings': rows, 'adopted_count': len(rows) if apply else 0}, indent=2))
