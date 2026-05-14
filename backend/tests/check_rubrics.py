import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from rubric_engine.models import Rubric

print(f'Total rubrics: {Rubric.objects.count()}')
print(f'Published rubrics: {Rubric.objects.filter(status="published").count()}')
print(f'Panel rubrics: {Rubric.objects.filter(evaluation_type="panel").count()}')
print(f'Published panel rubrics: {Rubric.objects.filter(status="published", evaluation_type="panel").count()}')

print('\nAll rubrics:')
for rubric in Rubric.objects.all():
    print(f'  - {rubric.name} ({rubric.get_evaluation_type_display()}) - {rubric.get_status_display()}')
