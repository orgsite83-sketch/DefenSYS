"""Returning students enter through normal team imports; no separate roster copier."""
from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0021_retire_active_extension_choices')]
    operations = [migrations.RemoveField(model_name='studentteam', name='previous_team')]
