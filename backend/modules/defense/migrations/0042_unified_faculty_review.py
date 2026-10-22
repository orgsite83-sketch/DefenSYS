from collections import defaultdict

from django.db import migrations, models


def unify_faculty_review(apps, schema_editor):
    """Normalize configuration without cancelling slots or reopening final grades."""
    alias = schema_editor.connection.alias
    Schedule = apps.get_model('defense', 'DefenseSchedule')
    StageFile = apps.get_model('defense', 'StageDeliverable')
    EventFile = apps.get_model('defense', 'PitEventDeliverable')
    Event = apps.get_model('defense', 'PitEventGradingConfig')
    Grade = apps.get_model('grading', 'TeamGrade')
    History = apps.get_model('grading', 'GradeAttemptHistory')
    Round = apps.get_model('repository', 'ConceptRound')
    Team = apps.get_model('student_teams', 'StudentTeam')

    stage_files, event_files = defaultdict(list), defaultdict(list)
    for row in StageFile.objects.using(alias).all().values():
        stage_files[row['defense_stage_id']].append(row)
    for row in EventFile.objects.using(alias).all().values():
        event_files[row['pit_event_config_id']].append(row)
    stage_ids = dict(apps.get_model('defense', 'DefenseStage').objects.using(alias).values_list('label', 'pk'))
    # Legacy imports can have finalized grades without a schedule. Preserve
    # their recorded exemption on that exact attempt, never on the next one.
    for grade in Grade.objects.using(alias).filter(scope='capstone', status='published', verdict='approved').iterator():
        definitions = stage_files[grade.defense_stage_id or stage_ids.get(grade.stage_label)]
        waived = [d['deliverable_id'] for d in definitions if d['deliverable_type'] == 'post'
                  and d.get('verdict_condition') == 'revisions_only']
        if waived:
            Grade.objects.using(alias).filter(pk=grade.pk).update(legacy_deliverable_policy={
                'attempt': grade.attempt_count, 'waived_ids': waived})
    event_ids = {(row['semester_id'], row['year_level'], row['event_name'].lower()): row['id']
                 for row in Event.objects.using(alias).all().values('id', 'semester_id', 'year_level', 'event_name')}
    completed_approvals = set(Grade.objects.using(alias).filter(status='published', verdict='approved')
                              .values_list('schedule_id', flat=True))
    completed_approvals.update(History.objects.using(alias).filter(verdict='approved')
                               .values_list('schedule_id', flat=True))
    schedules = Schedule.objects.using(alias).select_related('team').all()
    updates = []
    for schedule in schedules.iterator(chunk_size=500):
        definitions = stage_files[schedule.defense_stage_id] if schedule.scope == 'capstone' else event_files[
            event_ids.get((schedule.semester_id, schedule.team.year_level, schedule.event_name.lower()))]
        timings = {d['deliverable_id']: {'requirement_timing': 'defense',
                    'deadline_hours_before': d['deadline_hours_before']}
                   for d in definitions if d['deliverable_type'] == 'pre' and d['requirement_timing'] == 'defense'}
        waived = [d['deliverable_id'] for d in definitions if d.get('verdict_condition') == 'revisions_only'
                  and d['deliverable_type'] == 'post' and schedule.pk in completed_approvals]
        if timings or waived:
            schedule.legacy_deliverable_policy = {'timings': timings, 'waived_ids': waived}
            updates.append(schedule)
        if len(updates) == 500:
            Schedule.objects.using(alias).bulk_update(updates, ['legacy_deliverable_policy'])
            updates = []
    if updates:
        Schedule.objects.using(alias).bulk_update(updates, ['legacy_deliverable_policy'])

    Submission = apps.get_model('repository', 'DeliverableSubmission')
    Progress = apps.get_model('student_teams', 'TeamStageProgress')
    for team in Team.objects.using(alias).exclude(ready_for_stage__isnull=True).exclude(ready_for_stage='').iterator():
        if 'PIT' in team.level:
            context_id = event_ids.get((team.semester_id, team.year_level, team.ready_for_stage.lower()))
            definitions = event_files[context_id]
            hearings = Schedule.objects.using(alias).filter(team_id=team.pk, semester_id=team.semester_id,
                project_version=team.project_version, scope='pit', event_name__iexact=team.ready_for_stage)
            stage_id = None
        else:
            stage = apps.get_model('defense', 'DefenseStage').objects.using(alias).filter(label=team.ready_for_stage).first()
            stage_id = stage.pk if stage else None
            definitions = stage_files[stage_id]
            hearings = Schedule.objects.using(alias).filter(team_id=team.pk, semester_id=team.semester_id,
                project_version=team.project_version, scope='capstone', defense_stage_id=stage_id)
        if hearings.exclude(status='cancelled').exists():
            continue
        newly_required = {d['deliverable_id'] for d in definitions if d['deliverable_type'] == 'pre'
                          and d['required'] and d['requirement_timing'] == 'defense'}
        accepted = set(Submission.objects.using(alias).filter(team_id=team.pk,
            project_version=team.project_version, stage_label=team.ready_for_stage, status='accepted')
            .values_list('deliverable_id', flat=True))
        if newly_required - accepted:
            Team.objects.using(alias).filter(pk=team.pk).update(ready_for_stage=None)
            if stage_id:
                Progress.objects.using(alias).filter(team_id=team.pk, semester_id=team.semester_id,
                    defense_stage_id=stage_id, status='ready').update(status='locked')

    StageFile.objects.using(alias).all().update(requirement_timing='scheduling', deadline_hours_before=24,
                                              verdict_condition='all_pass')
    EventFile.objects.using(alias).all().update(requirement_timing='scheduling', deadline_hours_before=24)
    for model_name in ('DefenseStage', 'PitEventGradingConfig'):
        Model = apps.get_model('defense', model_name)
        for row in Model.objects.using(alias).filter(concept_config__enabled=True).iterator():
            config = {**row.concept_config, 'review_policy': 'always'}
            Model.objects.using(alias).filter(pk=row.pk).update(concept_config=config)

    # Unscheduled rounds whose review was optional need explicit endorsement
    # under the new rule. File reviews, history and scheduled hearings stay intact.
    for hearing in Round.objects.using(alias).filter(schedule_id__isnull=True, verdict='', review_required=False):
        Round.objects.using(alias).filter(pk=hearing.pk).update(review_required=True, endorsed_at=None,
            endorsed_by_id=None, override_reason='', endorsement_snapshot=[],
            policy_snapshot={**hearing.policy_snapshot, 'review_policy': 'always'})
        context = (apps.get_model('defense', 'DefenseStage').objects.using(alias).filter(pk=hearing.defense_stage_id).first()
                   if hearing.defense_stage_id else Event.objects.using(alias).filter(pk=hearing.pit_event_config_id).first())
        if context:
            label = context.label if hearing.defense_stage_id else context.event_name
            Team.objects.using(alias).filter(pk=hearing.team_id, project_version=hearing.project_version,
                                             ready_for_stage=label).update(ready_for_stage=None)


class Migration(migrations.Migration):
    dependencies = [
        ('defense', '0041_piteventgradingconfig_project_setup_policy'),
        ('repository', '0031_shared_hearing_final_papers'),
        ('grading', '0021_legacy_deliverable_policy'),
    ]

    operations = [
        migrations.AddField(model_name='defenseschedule', name='legacy_deliverable_policy',
                            field=models.JSONField(blank=True, default=dict, editable=False)),
        migrations.RunPython(unify_faculty_review, migrations.RunPython.noop),
    ]
