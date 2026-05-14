from django.core.management.base import BaseCommand
from defense_stages.models import DefenseStage, StageDeliverable


# Hardcoded deliverables from capstone_deliverables/services.py
DELIVERABLE_DEFINITIONS = {
    'Concept Proposal': [
        {'id': 'WPR', 'label': 'Weekly Progress Report', 'required': True, 'type': 'pre'},
        {'id': 'D1', 'label': 'D1 - Advisers Acceptance Form', 'required': True, 'type': 'pre'},
        {'id': 'D2', 'label': 'D2 - Nomination of Panel Members', 'required': True, 'type': 'pre'},
        {'id': 'D3', 'label': 'D3 - Approved Concept Hearing Form', 'required': True, 'type': 'pre'},
        {'id': 'D4', 'label': 'D4 - Concept Paper and Pitch Deck', 'required': True, 'type': 'pre'},
        {'id': 'D5', 'label': 'D5 - Signed Minutes (Concept)', 'required': True, 'type': 'pre'},
        {
            'id': 'D4.1',
            'label': 'D4.1 - Approved Concept Paper',
            'required': False,
            'type': 'vault',
            'vault_note': 'Uploaded to the vault after Concept defense is approved.',
        },
    ],
    'Project Proposal': [
        {'id': 'WPR', 'label': 'Weekly Progress Report', 'required': True, 'type': 'pre'},
        {'id': 'D6', 'label': 'D6 - Weekly Accomplishment Report', 'required': True, 'type': 'pre'},
        {'id': 'D7', 'label': 'D7 - Chapter 1', 'required': True, 'type': 'pre'},
        {'id': 'D8', 'label': 'D8 - Chapter 2', 'required': True, 'type': 'pre'},
        {'id': 'D9', 'label': 'D9 - Chapter 3', 'required': True, 'type': 'pre'},
        {'id': 'D11', 'label': 'D11 - Approved Proposal Defense Form', 'required': True, 'type': 'pre'},
        {'id': 'D12', 'label': 'D12 - Signed Minutes (Proposal)', 'required': True, 'type': 'pre'},
        {'id': 'D13', 'label': 'D13 - Signed Matrix of Revision', 'required': True, 'type': 'pre'},
        {
            'id': 'D10',
            'label': 'D10 - Chapters 1-3 (Complete)',
            'required': False,
            'type': 'vault',
            'vault_note': 'Uploaded to the vault after Proposal defense is approved.',
        },
    ],
    'Final Defense': [
        {'id': 'WPR', 'label': 'Weekly Progress Report', 'required': True, 'type': 'pre'},
        {'id': 'D14', 'label': 'D14 - Final Manuscript (Chapters 1-3)', 'required': True, 'type': 'pre'},
        {
            'id': 'D15',
            'label': 'D15 - Fully Functional Software System and Source Code',
            'required': False,
            'type': 'vault',
            'vault_note': 'Restricted vault item after Final defense.',
        },
        {
            'id': 'D16',
            'label': 'D16 - Full-Length Technical Manuscript (Chapters 1-5)',
            'required': False,
            'type': 'vault',
            'vault_note': 'Restricted vault item after Final defense.',
        },
        {'id': 'D17', 'label': 'D17 - 7-Page Executive Journal', 'required': False, 'type': 'vault'},
        {'id': 'D18', 'label': 'D18 - Project Poster', 'required': False, 'type': 'vault'},
        {'id': 'D19', 'label': 'D19 - Promotional Video', 'required': False, 'type': 'vault'},
    ],
}


class Command(BaseCommand):
    help = 'Migrate hardcoded deliverables to database'

    def handle(self, *args, **options):
        total_created = 0
        total_updated = 0

        for stage_label, deliverables in DELIVERABLE_DEFINITIONS.items():
            try:
                stage = DefenseStage.objects.get(label=stage_label)
                self.stdout.write(f'\nProcessing stage: {stage_label}')

                for idx, item in enumerate(deliverables):
                    deliverable, created = StageDeliverable.objects.update_or_create(
                        defense_stage=stage,
                        deliverable_id=item['id'],
                        defaults={
                            'label': item['label'],
                            'deliverable_type': item['type'],
                            'required': item['required'],
                            'display_order': idx + 1,
                            'vault_note': item.get('vault_note', ''),
                        },
                    )

                    if created:
                        total_created += 1
                        self.stdout.write(
                            self.style.SUCCESS(f'  ✓ Created: {item["id"]} - {item["label"]}')
                        )
                    else:
                        total_updated += 1
                        self.stdout.write(
                            self.style.WARNING(f'  ↻ Updated: {item["id"]} - {item["label"]}')
                        )

            except DefenseStage.DoesNotExist:
                self.stdout.write(
                    self.style.ERROR(f'✗ Stage not found: {stage_label}')
                )
                self.stdout.write(
                    self.style.WARNING(f'  Please create the "{stage_label}" stage first.')
                )

        self.stdout.write('\n' + '=' * 60)
        self.stdout.write(
            self.style.SUCCESS(f'\n✓ Migration complete!')
        )
        self.stdout.write(f'  Created: {total_created} deliverables')
        self.stdout.write(f'  Updated: {total_updated} deliverables')
        self.stdout.write(f'  Total: {total_created + total_updated} deliverables\n')
