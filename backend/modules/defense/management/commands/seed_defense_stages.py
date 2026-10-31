from django.core.management.base import BaseCommand, CommandError
from defensys_backend.db_guard import current_database_name, is_test_database
from defense.stages.models import DefenseStage

class Command(BaseCommand):
    help = 'Create defense stage fixtures in isolated test databases only.'

    def handle(self, *args, **kwargs):
        if not is_test_database(current_database_name()):
            raise CommandError('Stage fixtures are test-only. Configure stages in the application.')
        defaults = [
            {
                'label': 'Concept Proposal',
                'code': 'concept-proposal',
                'display_order': 1,
                'description': 'Initial presentation of the project concept, problem statement, and proposed solution.',
            },
            {
                'label': 'Project Proposal',
                'code': 'project-proposal',
                'display_order': 2,
                'description': 'Detailed proposal including methodology, timeline, and technical specifications.',
            },
            {
                'label': 'Final Defense',
                'code': 'final-defense',
                'display_order': 3,
                'description': 'Final presentation of the completed project with full system demonstration.',
            },
        ]
        
        count = 0
        for item in defaults:
            obj, created = DefenseStage.objects.get_or_create(
                label=item['label'],
                defaults={
                    'code': item['code'],
                    'display_order': item['display_order'],
                    'description': item['description'],
                    'is_active': True,
                },
            )
            if created:
                count += 1
                
        if kwargs.get('verbosity', 1):
            self.stdout.write(self.style.SUCCESS(f'Successfully seeded {count} defense stages.'))
