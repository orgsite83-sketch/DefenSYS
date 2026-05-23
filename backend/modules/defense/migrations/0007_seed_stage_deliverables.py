"""Seed default capstone deliverables per defense stage (idempotent)."""

from django.db import migrations


STAGE_DELIVERABLES = {
    'Concept Proposal': [
        ('WPR', 'Weekly Progress Report', 'pre', True, ''),
        ('D1', 'D1 - Advisers Acceptance Form', 'pre', True, ''),
        ('D2', 'D2 - Nomination of Panel Members', 'pre', True, ''),
        ('D3', 'D3 - Approved Concept Hearing Form', 'pre', True, ''),
        ('D4', 'D4 - Concept Paper and Pitch Deck', 'pre', True, ''),
        ('D5', 'D5 - Signed Minutes (Concept)', 'pre', True, ''),
        (
            'D4.1',
            'D4.1 - Approved Concept Paper',
            'vault',
            False,
            'Uploaded to the vault after Concept defense is approved.',
        ),
    ],
    'Project Proposal': [
        ('WPR', 'Weekly Progress Report', 'pre', True, ''),
        ('D6', 'D6 - Weekly Accomplishment Report', 'pre', True, ''),
        ('D7', 'D7 - Chapter 1', 'pre', True, ''),
        ('D8', 'D8 - Chapter 2', 'pre', True, ''),
        ('D9', 'D9 - Chapter 3', 'pre', True, ''),
        ('D11', 'D11 - Approved Proposal Defense Form', 'pre', True, ''),
        ('D12', 'D12 - Signed Minutes (Proposal)', 'pre', True, ''),
        ('D13', 'D13 - Signed Matrix of Revision', 'pre', True, ''),
        (
            'D10',
            'D10 - Chapters 1-3 (Complete)',
            'vault',
            False,
            'Uploaded to the vault after Proposal defense is approved.',
        ),
    ],
    'Final Defense': [
        ('WPR', 'Weekly Progress Report', 'pre', True, ''),
        ('D14', 'D14 - Final Manuscript (Chapters 1-3)', 'pre', True, ''),
        (
            'D15',
            'D15 - Fully Functional Software System and Source Code',
            'vault',
            False,
            'Restricted vault item after Final defense.',
        ),
        (
            'D16',
            'D16 - Full-Length Technical Manuscript (Chapters 1-5)',
            'vault',
            False,
            'Restricted vault item after Final defense.',
        ),
        ('D17', 'D17 - 7-Page Executive Journal', 'vault', False, ''),
        ('D18', 'D18 - Project Poster', 'vault', False, ''),
        ('D19', 'D19 - Promotional Video', 'vault', False, ''),
    ],
}


def seed_stage_deliverables(apps, schema_editor):
    DefenseStage = apps.get_model('defense', 'DefenseStage')
    StageDeliverable = apps.get_model('defense', 'StageDeliverable')

    for stage_label, rows in STAGE_DELIVERABLES.items():
        stage = DefenseStage.objects.filter(label=stage_label).first()
        if stage is None:
            continue
        for order, row in enumerate(rows, start=1):
            deliverable_id, label, deliverable_type, required, vault_note = row
            StageDeliverable.objects.get_or_create(
                defense_stage_id=stage.id,
                deliverable_id=deliverable_id,
                defaults={
                    'label': label,
                    'deliverable_type': deliverable_type,
                    'required': required,
                    'display_order': order,
                    'vault_note': vault_note,
                },
            )


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0006_stagegrading_group_flags'),
    ]

    operations = [
        migrations.RunPython(seed_stage_deliverables, migrations.RunPython.noop),
    ]
