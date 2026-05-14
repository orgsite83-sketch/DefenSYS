from django.db import transaction
from django.db.models import Q

from academic_period_management.models import Semester
from defense_scheduler.models import DefenseSchedule
from defense_stages.models import DefenseStage
from student_teams.models import StudentTeam
from .models import DeliverableSubmission


STAGE_OPTIONS = ['Concept Proposal', 'Project Proposal', 'Final Defense']


def get_deliverable_definitions(stage_label):
    """Get deliverables from database instead of hardcoded dict"""
    try:
        stage = DefenseStage.objects.prefetch_related('deliverables').get(label=stage_label)
        deliverables = stage.deliverables.all()
        return [
            {
                'id': d.deliverable_id,
                'label': d.label,
                'required': d.required,
                'type': d.deliverable_type,
                'vault_note': d.vault_note,
            }
            for d in deliverables
        ]
    except DefenseStage.DoesNotExist:
        return []


# Keep old DELIVERABLE_DEFINITIONS as fallback for backward compatibility
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


def display_name(user):
    if user is None:
        return None
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def definition_for(stage_label, deliverable_id):
    # Try database first
    definitions = get_deliverable_definitions(stage_label)
    for item in definitions:
        if item['id'] == deliverable_id:
            return item
    
    # Fallback to hardcoded definitions
    for item in DELIVERABLE_DEFINITIONS.get(stage_label, []):
        if item['id'] == deliverable_id:
            return item
    
    return None


def current_stage_for_team(team):
    return team.current_defense_stage or team.ready_for_stage or STAGE_OPTIONS[0]


def team_queryset_for_user(user):
    queryset = (
        StudentTeam.objects.select_related(
            'semester',
            'semester__school_year',
            'leader',
            'adviser',
        )
        .prefetch_related(
            'memberships',
            'memberships__student',
            'deliverable_submissions',
        )
        .filter(level__icontains='Capstone')
    )

    if getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False):
        return queryset
    if getattr(user, 'role', None) == 'faculty':
        if getattr(user, 'is_adviser', False):
            return queryset.filter(adviser=user)
        return queryset.none()
    if getattr(user, 'role', None) == 'student':
        return queryset.filter(memberships__student=user).distinct()
    return queryset.none()


def filter_teams(request, queryset):
    search = request.query_params.get('search', '').strip()
    status_filter = request.query_params.get('status', '').strip()

    if search:
        queryset = queryset.filter(
            Q(name__icontains=search)
            | Q(project_title__icontains=search)
            | Q(leader__first_name__icontains=search)
            | Q(leader__last_name__icontains=search)
            | Q(adviser__first_name__icontains=search)
            | Q(adviser__last_name__icontains=search)
            | Q(adviser__username__icontains=search)
        ).distinct()

    if status_filter == 'ready':
        queryset = queryset.exclude(ready_for_stage__isnull=True).exclude(ready_for_stage='')
    elif status_filter == 'missing':
        ready_ids = [
            team.id
            for team in queryset
            if required_complete(team, current_stage_for_team(team))
        ]
        queryset = queryset.exclude(pk__in=ready_ids)

    return queryset


def vault_unlocked(team, stage_label):
    if team.status == StudentTeam.STATUS_APPROVED:
        return True
    return DefenseSchedule.objects.filter(
        team=team,
        status=DefenseSchedule.STATUS_DONE,
    ).filter(Q(defense_stage__label=stage_label) | Q(event_name=stage_label)).exists()


def submissions_for(team, stage_label):
    return {
        submission.deliverable_id: submission
        for submission in team.deliverable_submissions.all()
        if submission.stage_label == stage_label
    }


def required_complete(team, stage_label):
    submitted = submissions_for(team, stage_label)
    return all(
        item['id'] in submitted
        for item in DELIVERABLE_DEFINITIONS.get(stage_label, [])
        if item['type'] == DeliverableSubmission.TYPE_PRE and item['required']
    )


def stage_payload(team, stage_label):
    submitted = submissions_for(team, stage_label)
    # Try database first, fallback to hardcoded
    definitions = get_deliverable_definitions(stage_label)
    if not definitions:
        definitions = DELIVERABLE_DEFINITIONS.get(stage_label, [])
    
    unlocked = vault_unlocked(team, stage_label)
    rows = []

    for item in definitions:
        submission = submitted.get(item['id'])
        is_vault = item['type'] == DeliverableSubmission.TYPE_VAULT
        rows.append({
            'id': item['id'],
            'label': item['label'],
            'required': item['required'],
            'type': item['type'],
            'vault_note': item.get('vault_note', ''),
            'uploaded': submission is not None,
            'locked': is_vault and not unlocked,
            'submission': submission_payload(submission) if submission else None,
        })

    pre_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_PRE]
    vault_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_VAULT]
    required_items = [item for item in pre_items if item['required']]

    return {
        'stage_label': stage_label,
        'endorsed': team.ready_for_stage == stage_label,
        'vault_unlocked': unlocked,
        'required_complete': all(item['uploaded'] for item in required_items),
        'pre_uploaded': sum(1 for item in pre_items if item['uploaded']),
        'pre_total': len(pre_items),
        'required_uploaded': sum(1 for item in required_items if item['uploaded']),
        'required_total': len(required_items),
        'vault_uploaded': sum(1 for item in vault_items if item['uploaded']),
        'vault_total': len(vault_items),
        'deliverables': rows,
    }


def submission_payload(submission):
    if submission is None:
        return None
    return {
        'id': submission.id,
        'deliverable_id': submission.deliverable_id,
        'file_name': submission.file_name,
        'file_size': submission.file_size,
        'uploaded_by_name': display_name(submission.uploaded_by),
        'uploaded_at': submission.uploaded_at,
    }


def team_payload(team, selected_stage=None):
    selected = selected_stage or current_stage_for_team(team)
    stages = [stage_payload(team, stage) for stage in STAGE_OPTIONS]
    selected_payload = next((item for item in stages if item['stage_label'] == selected), stages[0])
    return {
        'id': team.id,
        'name': team.name,
        'project_title': team.project_title,
        'level': team.level,
        'year_level': team.year_level,
        'status': team.status,
        'ready_for_stage': team.ready_for_stage,
        'current_defense_stage': team.current_defense_stage,
        'current_stage': current_stage_for_team(team),
        'selected_stage': selected_payload,
        'stages': stages,
        'adviser_name': display_name(team.adviser),
        'leader_name': display_name(team.leader),
        'member_count': team.memberships.count(),
        'submitted_count': team.deliverable_submissions.count(),
    }


def counts_payload(teams):
    team_list = list(teams)
    submitted_total = sum(team.deliverable_submissions.count() for team in team_list)
    ready_count = sum(1 for team in team_list if team.ready_for_stage)
    missing_count = sum(
        1
        for team in team_list
        if not required_complete(team, current_stage_for_team(team))
    )
    vault_total = DeliverableSubmission.objects.filter(
        team__in=team_list,
        deliverable_type=DeliverableSubmission.TYPE_VAULT,
    ).count() if team_list else 0
    return {
        'teams': len(team_list),
        'ready': ready_count,
        'missing_requirements': missing_count,
        'submitted_files': submitted_total,
        'vault_files': vault_total,
    }


@transaction.atomic
def upsert_submission(team, stage_label, deliverable_id, file_name, file_size, user, file=None):
    definition = definition_for(stage_label, deliverable_id)
    if definition is None:
        raise ValueError('Deliverable does not exist for this stage.')
    if definition['type'] == DeliverableSubmission.TYPE_VAULT and not vault_unlocked(team, stage_label):
        raise PermissionError('Vault submissions are locked until this defense is done.')

    defaults = {
        'label': definition['label'],
        'deliverable_type': definition['type'],
        'required': definition['required'],
        'file_name': file_name.strip(),
        'file_size': (file_size or '').strip(),
        'uploaded_by': user,
    }
    
    # Add file if provided
    if file is not None:
        defaults['file'] = file

    submission, _ = DeliverableSubmission.objects.update_or_create(
        team=team,
        stage_label=stage_label,
        deliverable_id=deliverable_id,
        defaults=defaults,
    )
    return submission


@transaction.atomic
def remove_submission(team, stage_label, deliverable_id):
    deleted, _ = DeliverableSubmission.objects.filter(
        team=team,
        stage_label=stage_label,
        deliverable_id=deliverable_id,
    ).delete()
    if hasattr(team, '_prefetched_objects_cache'):
        team._prefetched_objects_cache.pop('deliverable_submissions', None)
    if team.ready_for_stage == stage_label and not required_complete(team, stage_label):
        team.ready_for_stage = None
        team.save(update_fields=['ready_for_stage', 'updated_at'])
    return deleted


@transaction.atomic
def endorse_team(team, stage_label):
    if not required_complete(team, stage_label):
        raise ValueError('All required pre-defense deliverables must be uploaded before endorsement.')
    team.ready_for_stage = stage_label
    team.current_defense_stage = stage_label
    team.save(update_fields=['ready_for_stage', 'current_defense_stage', 'updated_at'])
    return team


@transaction.atomic
def demo_fill_required(teams, stage_label, user):
    created = 0
    # Try database first, fallback to hardcoded
    definitions = get_deliverable_definitions(stage_label)
    if not definitions:
        definitions = DELIVERABLE_DEFINITIONS.get(stage_label, [])
    
    for team in teams:
        for item in definitions:
            if item['type'] != DeliverableSubmission.TYPE_PRE or not item['required']:
                continue
            safe_name = item['label'].split(' - ', 1)[-1].replace(' ', '_')
            _, made = DeliverableSubmission.objects.update_or_create(
                team=team,
                stage_label=stage_label,
                deliverable_id=item['id'],
                defaults={
                    'label': item['label'],
                    'deliverable_type': item['type'],
                    'required': item['required'],
                    'file_name': f'{team.name.replace(" ", "_")}_{safe_name}.pdf',
                    'file_size': '512 KB',
                    'uploaded_by': user,
                },
            )
            if made:
                created += 1
    return created
