"""Separate legacy stage calendars after schema indexes have been committed."""
from copy import deepcopy

from django.db import migrations
from django.db.models import Min, Max


def separate_stage_calendars(apps, schema_editor):
    alias = schema_editor.connection.alias
    Period = apps.get_model('student_teams', 'WeeklyReportingPeriod')
    Stage = apps.get_model('defense', 'DefenseStage')
    Participation = apps.get_model('student_teams', 'TeamTermParticipation')
    mapping = {}
    for period in Period.objects.using(alias).order_by('pk'):
        stages = list(Stage.objects.using(alias).filter(
            weekly_reporting__period_id=period.pk).order_by('created_at', 'pk'))
        if not stages:
            # Unreferenced legacy evidence remains retained under its original ID.
            continue
        dates = period.reports.using(alias).aggregate(first=Min('submitted_at'), last=Max('submitted_at'))
        owner = stages[0]
        if dates['first'] and len(stages) > 1:
            possible = [stage for stage in stages if stage.created_at <= dates['last']]
            if len(possible) != 1 or possible[0].created_at > dates['first']:
                raise RuntimeError(
                    f'Weekly period {period.pk} has ambiguous historical stage ownership. '
                    'Review its reports and stage assignments before migrating; no reports were moved.')
            owner = possible[0]
        period.defense_stage_id = owner.pk
        period.save(using=alias, update_fields=['defense_stage'])
        for stage in stages:
            target = period if stage.pk == owner.pk else Period.objects.using(alias).create(
                semester_id=period.semester_id, defense_stage_id=stage.pk,
                starts_on=period.starts_on, total_weeks=stage.weekly_reporting['required_end'],
                due_weekday=period.due_weekday, due_time=period.due_time)
            mapping[(stage.pk, period.pk)] = target.pk
            policy = {**stage.weekly_reporting, 'period_id': target.pk}
            Stage.objects.using(alias).filter(pk=stage.pk).update(weekly_reporting=policy)
    for row in Participation.objects.using(alias).exclude(requirements=[]).iterator():
        requirements = deepcopy(row.requirements)
        changed = False
        for requirement in requirements:
            for definition in requirement.get('definitions', []):
                if definition.get('source') != 'weekly_reports':
                    continue
                policy = definition.get('weekly_reporting') or {}
                target = mapping.get((requirement.get('id'), policy.get('period_id')))
                if target is not None:
                    definition['weekly_reporting'] = {**policy, 'period_id': target,
                        'defense_stage_id': requirement['id']}
                    changed = True
        if changed:
            Participation.objects.using(alias).filter(pk=row.pk).update(requirements=requirements)


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0024_stage_weekly_reporting')]
    operations = [migrations.RunPython(separate_stage_calendars)]
