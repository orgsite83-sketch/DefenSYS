"""Move explicitly selected local demo records to an existing panelist account."""
from pathlib import Path

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core import serializers
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Q

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.minutes.models import DefenseMinutes, MinutesPanelistComment
from defense.scheduler.models import DefenseSchedule, PanelistEvaluationDraft, SchedulePanelist
from defense.scheduler.operations import _overlap
from defense.scheduler.services import DEMO_PANELIST_SETUP_ACTION
from grading.grades.models import (
    GradeAttemptHistory, PanelistCriterionScore, PanelistGradeSubmission,
    StudentStageGrade, TeamGrade,
)
from student_teams.models import StudentTeam


class Command(BaseCommand):
    help = 'Preview or apply a local demo panelist identity change, preserving evaluation data.'

    def add_arguments(self, parser):
        parser.add_argument('--demo', action='store_true', help='Explicitly identify these as demonstration records.')
        parser.add_argument('--source', required=True, help='Original demo panelist username.')
        parser.add_argument('--replacement', required=True, help='Existing replacement panelist username.')
        parser.add_argument('--actor', required=True, help='Administrator recording the setup.')
        parser.add_argument('--schedule-ids', nargs='+', type=int, required=True)
        parser.add_argument('--temporary-source', help='Temporary replacement username on selected schedules.')
        parser.add_argument('--temporary-schedule-ids', nargs='+', type=int, default=[])
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--backup', help='New JSON backup file, required when applying.')

    @transaction.atomic
    def handle(self, *args, **options):
        if not settings.DEBUG or not options['demo']:
            raise CommandError('This setup is available only in DEBUG mode with --demo. Use amendments for institutional records.')
        users = get_user_model()
        actor = users.objects.filter(username=options['actor'], is_active=True).first()
        if actor is None or not (actor.role == 'admin' or actor.is_superuser):
            raise CommandError('Choose an active administrator as the audit actor.')
        source = users.objects.filter(username=options['source']).first()
        replacement = users.objects.filter(username=options['replacement'], is_active=True,
            role__in=['faculty', 'admin'], is_panelist=True).first()
        if source is None or replacement is None or source.pk == replacement.pk:
            raise CommandError('Choose distinct existing accounts and an active eligible replacement panelist.')
        if StudentTeam.objects.filter(adviser=replacement).exists():
            raise CommandError('The replacement must have no assigned advisees.')
        requested = set(options['schedule_ids'])
        temporary_ids = set(options['temporary_schedule_ids'])
        temporary = users.objects.filter(username=options['temporary_source']).first() if options['temporary_source'] else None
        if temporary_ids and (not temporary or not temporary_ids <= requested or temporary.pk in (source.pk, replacement.pk)):
            raise CommandError('Choose a distinct temporary source and schedules within the explicit selection.')
        schedules = list(DefenseSchedule.objects.select_for_update().filter(pk__in=requested).order_by('pk'))
        if len(schedules) != len(requested):
            raise CommandError('One or more selected schedules do not exist.')
        # Share team locks with adviser updates and ordinary scheduling writes.
        teams = {team.pk: team for team in StudentTeam.objects.select_for_update().filter(
            pk__in={s.team_id for s in schedules}).order_by('pk')}
        panels = list(SchedulePanelist.objects.select_for_update().filter(schedule_id__in=requested))
        minutes = list(DefenseMinutes.objects.select_for_update().filter(schedule_id__in=requested))
        for record in minutes:
            if (record.status != 'draft' or record.pdf_file or record.documenter_signed_at
                    or record.adviser_signed_at or record.chairman_signed_at or record.revisions.exists()):
                raise CommandError(f'{record.schedule_id}: signed minutes or retained revisions require an amendment.')
        plans = []
        for schedule in schedules:
            schedule.team = teams[schedule.team_id]
            departing = temporary if schedule.pk in temporary_ids else source
            roster = [p for p in panels if p.schedule_id == schedule.pk]
            previous = next((p for p in roster if p.panelist_id == departing.pk), None)
            existing = next((p for p in roster if p.panelist_id == replacement.pk), None)
            if previous is None and existing is not None:
                self.stdout.write(f'{schedule.pk}: already assigned to {replacement.username}; skipped.')
                continue
            if previous is None or existing is not None:
                raise CommandError(f'{schedule.pk}: expected one departing panelist and no replacement assignment.')
            if replacement.pk in (schedule.team.adviser_id, schedule.documenter_id):
                raise CommandError(f'{schedule.pk}: replacement conflicts with the adviser or documenter.')
            if (PanelistGradeSubmission.objects.filter(schedule=schedule, panelist=replacement).exists()
                    or PanelistEvaluationDraft.objects.filter(schedule=schedule, panelist=replacement).exists()
                    or MinutesPanelistComment.objects.filter(minutes__schedule=schedule, panelist=replacement).exists()):
                raise CommandError(f'{schedule.pk}: the replacement already has evaluation data; no records were merged.')
            plans.append((schedule, previous, departing))
            self.stdout.write(f'{schedule.pk} / {schedule.team.name} / {schedule.stage_label}: {departing.username} -> {replacement.username}; retain {schedule.status} and evaluation data.')
        open_schedules = [s for s, _, _ in plans if s.status == 'scheduled']
        others = list(DefenseSchedule.objects.filter(status='scheduled').exclude(pk__in=requested).filter(
            Q(panel_assignments__panelist=replacement) | Q(documenter=replacement) | Q(team__adviser=replacement)).distinct())
        for schedule in open_schedules:
            if any(schedule.scheduled_date == other.scheduled_date and _overlap(schedule, other)
                    for other in others + [s for s in open_schedules if s.pk != schedule.pk]):
                raise CommandError(f'{schedule.pk}: replacement has an overlapping defense.')
        if not options['apply']:
            self.stdout.write(f'Preview only: {len(plans)} schedules; no records changed.')
            return
        if not plans:
            self.stdout.write('No changes needed.')
            return
        if not options['backup']:
            raise CommandError('--backup is required before applying demo identity changes.')
        grade_ids = list(TeamGrade.all_objects.filter(schedule_id__in=requested).values_list('pk', flat=True))
        records = [
            schedules, panels, minutes,
            MinutesPanelistComment.objects.filter(minutes__schedule_id__in=requested),
            PanelistGradeSubmission.objects.filter(schedule_id__in=requested),
            PanelistCriterionScore.objects.filter(submission__schedule_id__in=requested),
            PanelistEvaluationDraft.objects.filter(schedule_id__in=requested),
            TeamGrade.all_objects.filter(pk__in=grade_ids),
            StudentStageGrade.objects.filter(team_grade_id__in=grade_ids),
            GradeAttemptHistory.objects.filter(schedule_id__in=requested),
        ]
        backup = Path(options['backup'])
        backup.parent.mkdir(parents=True, exist_ok=True)
        try:
            with backup.open('x', encoding='utf-8') as destination:
                serializers.serialize('json', (row for group in records for row in group), stream=destination, indent=2)
        except OSError as exc:
            raise CommandError(f'Could not create a new backup; no records changed: {exc}') from exc
        name = replacement.get_full_name() or replacement.username
        for schedule, assignment, departing in plans:
            old_panel_ids = [p.panelist_id for p in panels if p.schedule_id == schedule.pk]
            submissions = PanelistGradeSubmission.objects.filter(schedule=schedule, panelist_id__in={source.pk, departing.pk})
            drafts = PanelistEvaluationDraft.objects.filter(schedule=schedule, panelist_id__in={source.pk, departing.pk})
            comments = MinutesPanelistComment.objects.filter(minutes__schedule=schedule, panelist=source)
            retained = {'submission_ids': list(submissions.values_list('pk', flat=True)),
                'draft_ids': list(drafts.values_list('pk', flat=True)), 'comment_ids': list(comments.values_list('pk', flat=True))}
            # Update only identity fields. Keep primary keys, scores, comments,
            # timestamps, outcomes and published/completed states exactly as seeded.
            SchedulePanelist.objects.filter(pk=assignment.pk).update(panelist=replacement)
            submissions.update(panelist=replacement)
            drafts.update(panelist=replacement)
            comments.update(panelist=replacement, panelist_name_snapshot=name)
            TeamGrade.all_objects.filter(schedule=schedule, verdict_by=source).update(verdict_by=replacement)
            GradeAttemptHistory.objects.filter(schedule=schedule, verdict_by=source).update(verdict_by=replacement)
            new_panel_ids = [replacement.pk if pk == departing.pk else pk for pk in old_panel_ids]
            log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING,
                action=DEMO_PANELIST_SETUP_ACTION, target=schedule, actor=actor, strict=True,
                old_values={'scope': schedule.scope, 'panelist_ids': old_panel_ids, 'demo_source_id': source.pk, **retained},
                new_values={'scope': schedule.scope, 'panelist_ids': new_panel_ids,
                    'demo_panelist_id': replacement.pk, 'data_preserved': True, **retained},
                reason='Prepare explicitly selected local demonstration records for the panelist account.')
        self.stdout.write(self.style.SUCCESS(f'Prepared {len(plans)} demo schedules for {name} ({replacement.username}); data preserved. Backup: {backup}'))
