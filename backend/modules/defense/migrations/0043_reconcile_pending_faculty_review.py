from django.db import migrations


def reconcile_pending_review(apps, schema_editor):
    """Reopen pending endorsements in every event, not only the team's mirror."""
    alias = schema_editor.connection.alias
    Schedule = apps.get_model('defense', 'DefenseSchedule')
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    Round = apps.get_model('repository', 'ConceptRound')
    Endorsement = apps.get_model('student_teams', 'PITTeamEventEndorsement')
    Team = apps.get_model('student_teams', 'StudentTeam')

    def missing(team, label, definitions):
        required = set(definitions.filter(deliverable_type='pre', required=True)
                       .values_list('deliverable_id', flat=True))
        accepted = set(Submission.objects.using(alias).filter(team_id=team.pk,
            project_version=team.project_version, stage_label=label, status='accepted')
            .values_list('deliverable_id', flat=True))
        return bool(required - accepted)

    for record in Endorsement.objects.using(alias).filter(endorsed_at__isnull=False).select_related('team', 'event'):
        team, event = record.team, record.event
        if record.project_version != team.project_version:
            continue
        if Schedule.objects.using(alias).filter(team_id=team.pk, semester_id=event.semester_id,
                project_version=record.project_version, scope='pit', event_name__iexact=event.event_name
                ).exclude(status='cancelled').exists():
            continue
        if missing(team, event.event_name, event.deliverables.using(alias)):
            Endorsement.objects.using(alias).filter(pk=record.pk).update(endorsed_at=None, endorsed_by_id=None)
            Team.objects.using(alias).filter(pk=team.pk, ready_for_stage=event.event_name).update(ready_for_stage=None)

    for hearing in Round.objects.using(alias).filter(schedule_id__isnull=True, verdict='', endorsed_at__isnull=False
            ).select_related('team', 'defense_stage', 'pit_event_config'):
        if hearing.project_version != hearing.team.project_version:
            continue
        context = hearing.defense_stage if hearing.defense_stage_id else hearing.pit_event_config
        label = context.label if hearing.defense_stage_id else context.event_name
        if missing(hearing.team, label, context.deliverables.using(alias)):
            Round.objects.using(alias).filter(pk=hearing.pk).update(endorsed_at=None, endorsed_by_id=None,
                endorsement_snapshot=[], override_reason='', review_required=True)
            Team.objects.using(alias).filter(pk=hearing.team_id, ready_for_stage=label).update(ready_for_stage=None)


class Migration(migrations.Migration):
    dependencies = [
        ('defense', '0042_unified_faculty_review'),
        ('student_teams', '0013_pit_event_endorsements'),
    ]
    operations = [migrations.RunPython(reconcile_pending_review, migrations.RunPython.noop)]
