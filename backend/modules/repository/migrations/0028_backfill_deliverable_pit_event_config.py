from django.db import migrations


def backfill_pit_event_configs(apps, schema_editor):
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    Config = apps.get_model('defense', 'PitEventGradingConfig')
    database = schema_editor.connection.alias

    for submission in Submission.objects.using(database).filter(pit_event_config__isnull=True).select_related('team').iterator():
        team = submission.team
        if not team:
            continue
        level = submission.archive_team_level or getattr(team, 'level', '') or ''
        if 'PIT' not in level and not getattr(team, 'is_pit', False):
            continue
        semester_id = submission.archive_semester_id or getattr(team, 'semester_id', None)
        year_level = submission.archive_year_level or getattr(team, 'year_level', '')
        config = Config.objects.using(database).filter(
            semester_id=semester_id,
            event_name__iexact=submission.stage_label.strip(),
        )
        if year_level:
            config = config.filter(year_level=year_level)
        matched_cfg = config.first()
        if matched_cfg:
            submission.pit_event_config_id = matched_cfg.id
            submission.save(using=database, update_fields=['pit_event_config'])


class Migration(migrations.Migration):
    dependencies = [
        ('repository', '0027_sectionconceptround_revision_notes_and_more'),
        ('defense', '0040_pit_peer_access_default'),
    ]

    operations = [
        migrations.RunPython(backfill_pit_event_configs, migrations.RunPython.noop),
    ]
