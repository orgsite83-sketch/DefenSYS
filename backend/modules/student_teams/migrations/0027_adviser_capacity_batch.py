"""Add batch identity; backfill in 0028 after this schema transaction commits."""
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0026_adviser_capacity_exception')]
    operations = [
        migrations.AddField(model_name='advisercapacityexception', name='intake_semester',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT,
                related_name='intake_adviser_capacity_exceptions', to='academic_period_management.semester')),
        migrations.AddField(model_name='advisercapacityexception', name='end_kind',
            field=models.CharField(blank=True, default='', max_length=20, choices=[
                ('revoked', 'Revoked'), ('retired', 'Cycle ended'), ('legacy_ended', 'Previously ended')])),
        migrations.RemoveConstraint(model_name='advisercapacityexception', name='unique_adviser_capacity_term'),
        migrations.AddConstraint(model_name='advisercapacityexception',
            constraint=models.UniqueConstraint(fields=('adviser', 'intake_semester'), name='unique_adviser_capacity_intake')),
    ]
