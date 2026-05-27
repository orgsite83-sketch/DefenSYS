import django.db.models.deletion
from django.db import migrations, models


def _single_id(queryset):
    ids = list(queryset.values_list('id', flat=True)[:2])
    return ids[0] if len(ids) == 1 else None


def backfill_teamgrade_stage_identity(apps, schema_editor):
    TeamGrade = apps.get_model('grading', 'TeamGrade')
    DefenseSchedule = apps.get_model('defense', 'DefenseSchedule')
    DefenseStage = apps.get_model('defense', 'DefenseStage')
    PitEventGradingConfig = apps.get_model('defense', 'PitEventGradingConfig')

    for grade in TeamGrade.objects.all().iterator():
        if grade.scope == 'capstone':
            stage_id = None
            if grade.schedule_id:
                stage_id = (
                    DefenseSchedule.objects.filter(pk=grade.schedule_id)
                    .values_list('defense_stage_id', flat=True)
                    .first()
                )
            if stage_id is None:
                stage_id = _single_id(DefenseStage.objects.filter(label=grade.stage_label))
            if stage_id is not None:
                if TeamGrade.objects.filter(
                    team_id=grade.team_id,
                    semester_id=grade.semester_id,
                    scope='capstone',
                    defense_stage_id=stage_id,
                ).exclude(pk=grade.pk).exists():
                    continue
                stage_label = (
                    DefenseStage.objects.filter(pk=stage_id)
                    .values_list('label', flat=True)
                    .first()
                ) or grade.stage_label
                TeamGrade.objects.filter(pk=grade.pk).update(
                    defense_stage_id=stage_id,
                    pit_event_config_id=None,
                    stage_label=stage_label,
                )
            continue

        if grade.scope == 'pit':
            event_name = grade.stage_label
            if grade.schedule_id:
                event_name = (
                    DefenseSchedule.objects.filter(pk=grade.schedule_id)
                    .values_list('event_name', flat=True)
                    .first()
                ) or event_name
            config_id = _single_id(
                PitEventGradingConfig.objects.filter(
                    semester_id=grade.semester_id,
                    event_name__iexact=(event_name or '').strip(),
                )
            )
            if config_id is not None:
                if TeamGrade.objects.filter(
                    team_id=grade.team_id,
                    semester_id=grade.semester_id,
                    scope='pit',
                    pit_event_config_id=config_id,
                ).exclude(pk=grade.pk).exists():
                    continue
                config_label = (
                    PitEventGradingConfig.objects.filter(pk=config_id)
                    .values_list('event_name', flat=True)
                    .first()
                ) or event_name
                TeamGrade.objects.filter(pk=grade.pk).update(
                    defense_stage_id=None,
                    pit_event_config_id=config_id,
                    stage_label=config_label,
                )


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0009_stagegradingconfig_rubrics'),
        ('grading', '0004_teamgrade_ready_for_archive'),
    ]

    operations = [
        migrations.AddField(
            model_name='teamgrade',
            name='defense_stage',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='grade_records',
                to='defense.defensestage',
            ),
        ),
        migrations.AddField(
            model_name='teamgrade',
            name='pit_event_config',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='grade_records',
                to='defense.piteventgradingconfig',
            ),
        ),
        migrations.RunPython(
            backfill_teamgrade_stage_identity,
            migrations.RunPython.noop,
        ),
        migrations.RemoveConstraint(
            model_name='teamgrade',
            name='unique_grade_record_per_team_context',
        ),
        migrations.AddConstraint(
            model_name='teamgrade',
            constraint=models.UniqueConstraint(
                condition=models.Q(('defense_stage__isnull', False), ('scope', 'capstone')),
                fields=('team', 'semester', 'scope', 'defense_stage'),
                name='unique_capstone_grade_per_team_stage',
            ),
        ),
        migrations.AddConstraint(
            model_name='teamgrade',
            constraint=models.UniqueConstraint(
                condition=models.Q(('pit_event_config__isnull', False), ('scope', 'pit')),
                fields=('team', 'semester', 'scope', 'pit_event_config'),
                name='unique_pit_grade_per_team_event',
            ),
        ),
        migrations.AddIndex(
            model_name='teamgrade',
            index=models.Index(fields=['defense_stage'], name='grade_cente_def_sta_idx'),
        ),
        migrations.AddIndex(
            model_name='teamgrade',
            index=models.Index(fields=['pit_event_config'], name='grade_cente_pit_evt_idx'),
        ),
    ]
