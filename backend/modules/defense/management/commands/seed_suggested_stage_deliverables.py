"""

Opt-in dev helper: load suggested deliverable checklists into Defense Stages.



Does not run automatically. Not a runtime fallback.

"""



from django.core.management.base import BaseCommand

from django.db import transaction



from defense.stages.models import DefenseStage, StageDeliverable

from repository.deliverables.deliverable_templates import SUGGESTED_DELIVERABLE_TEMPLATES





class Command(BaseCommand):

    help = (
        'TESTS/OPT-IN ONLY: seed suggested StageDeliverable rows. '
        'Do not run on dev demo or production DB. Use Defense Stages UI instead.'
    )



    def add_arguments(self, parser):

        parser.add_argument(

            '--force',

            action='store_true',

            help='Replace existing deliverables for matching stages.',

        )

        parser.add_argument(

            '--stage',

            action='append',

            dest='stages',

            help='Only seed these stage labels (can repeat flag).',

        )



    def handle(self, *args, **options):

        force = options['force']

        only_stages = options['stages']

        created_total = 0



        with transaction.atomic():

            for label, templates in SUGGESTED_DELIVERABLE_TEMPLATES.items():

                if only_stages and label not in only_stages:

                    continue

                try:

                    stage = DefenseStage.objects.get(label=label)

                except DefenseStage.DoesNotExist:

                    self.stdout.write(self.style.WARNING(f'Skipping missing stage: {label}'))

                    continue



                existing = stage.deliverables.count()

                if existing and not force:

                    self.stdout.write(f'{label}: already has {existing} deliverable(s) — skipped')

                    continue



                if existing and force:

                    stage.deliverables.all().delete()



                for order, item in enumerate(templates, start=1):

                    StageDeliverable.objects.create(

                        defense_stage=stage,

                        deliverable_id=item['id'],

                        label=item['label'],

                        deliverable_type=item['type'],

                        required=item['required'],

                        display_order=order,

                        vault_note=item.get('vault_note', ''),

                    )

                    created_total += 1



                self.stdout.write(

                    self.style.SUCCESS(f'{label}: seeded {len(templates)} deliverable(s)')

                )



        self.stdout.write(self.style.SUCCESS(f'Done. {created_total} row(s) written.'))


