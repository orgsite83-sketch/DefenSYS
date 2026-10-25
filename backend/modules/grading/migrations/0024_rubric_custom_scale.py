from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('grading', '0023_gradeattempthistory_assessment_policy_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='rubric',
            name='custom_max_score',
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        *[
            migrations.AlterField(
                model_name=model_name,
                name='scale',
                field=models.CharField(
                    choices=[
                        ('5-Point Scale', '5-Point Scale'),
                        ('10-Point Scale', '10-Point Scale'),
                        ('100-Point Scale', '100-Point Scale'),
                        ('Custom Scale', 'Custom Scale'),
                    ],
                    default='10-Point Scale',
                    max_length=30,
                ),
            )
            for model_name in ('rubric', 'rubriccriterion')
        ],
    ]
