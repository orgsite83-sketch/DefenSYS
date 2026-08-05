from django.db import transaction
from django.core.exceptions import ValidationError

from grading.rubrics.models import Rubric

from .models import PitEventGradingConfig, PitEventDeliverable


DEFAULT_PIT_PANEL_WEIGHT = 80
DEFAULT_PIT_PEER_WEIGHT = 20


def default_pit_weights():
    return {
        'panel_weight': DEFAULT_PIT_PANEL_WEIGHT,
        'peer_weight': DEFAULT_PIT_PEER_WEIGHT,
        'adviser_weight': 0,
    }


def get_pit_event_config(semester, event_name):
    if not semester or not (event_name or '').strip():
        return None
    return (
        PitEventGradingConfig.objects.select_related('panel_rubric', 'peer_rubric')
        .prefetch_related('deliverables')
        .filter(semester=semester, event_name__iexact=event_name.strip())
        .first()
    )


def weights_for_pit_event(semester, event_name):
    config = get_pit_event_config(semester, event_name)
    if config is None:
        return default_pit_weights()
    return {
        'panel_weight': config.panel_weight,
        'peer_weight': config.peer_weight,
        'adviser_weight': 0,
    }


def peer_rubric_for_pit_event(semester, event_name):
    config = get_pit_event_config(semester, event_name)
    if config is None:
        return None
    return config.peer_rubric


def check_pit_event_locked(config, semester=None):
    if not config:
        return False, None

    if config.is_officially_complete:
        return True, 'This PIT event is officially complete for the active semester.'

    sem = semester or config.semester

    from django.db.models import Q
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade

    # 1. Scheduled Defenses
    if sem and DefenseSchedule.objects.filter(semester=sem, event_name__iexact=config.event_name).exists():
        return True, 'This PIT event has scheduled defenses for the active semester.'

    # 2. Recorded Evaluation Grades
    grades_exist = TeamGrade.objects.filter(pit_event_config=config).exclude(status=TeamGrade.STATUS_PENDING).exists()
    if not grades_exist and sem:
        grades_exist = TeamGrade.objects.filter(
            semester=sem,
            scope=TeamGrade.SCOPE_PIT,
            stage_label__iexact=config.event_name,
        ).exclude(status=TeamGrade.STATUS_PENDING).exists()

    if grades_exist:
        return True, 'This PIT event has recorded evaluation grades.'

    # 3. Deliverable Submissions
    from repository.deliverables.models import DeliverableSubmission
    deliv_ids = list(config.deliverables.values_list('deliverable_id', flat=True))
    if deliv_ids:
        if DeliverableSubmission.objects.filter(
            stage_label__iexact=config.event_name,
            deliverable_id__in=deliv_ids,
        ).exists():
            return True, 'This PIT event has student deliverable submissions.'

    return False, None


def upsert_pit_event_config(
    *,
    semester,
    event_name,
    event_code=None,
    panel_rubric=None,
    peer_rubric=None,
    panel_weight=80,
    peer_weight=20,
    archive_file_template=None,
    deliverables=None,
):
    from django.db.models import Q
    from grading.grades.models import TeamGrade

    event_name = (event_name or '').strip()
    if not event_name:
        raise ValidationError({'event_name': 'PIT event name is required.'})
    if panel_weight + peer_weight != 100:
        raise ValidationError('Panel and peer weights must total 100%.')

    existing_config = PitEventGradingConfig.objects.filter(
        semester=semester, event_name__iexact=event_name
    ).first()

    # Rubric Exclusivity Check
    if panel_rubric:
        other = PitEventGradingConfig.objects.filter(semester=semester).exclude(
            event_name__iexact=event_name
        ).filter(
            Q(panel_rubric=panel_rubric) | Q(peer_rubric=panel_rubric)
        ).first()
        if other:
            raise ValidationError(
                f"Panel Rubric '{panel_rubric.name}' is already assigned to PIT event '{other.event_name}'."
            )

    if peer_rubric:
        other = PitEventGradingConfig.objects.filter(semester=semester).exclude(
            event_name__iexact=event_name
        ).filter(
            Q(panel_rubric=peer_rubric) | Q(peer_rubric=peer_rubric)
        ).first()
        if other:
            raise ValidationError(
                f"Peer Rubric '{peer_rubric.name}' is already assigned to PIT event '{other.event_name}'."
            )

    # Lock Check for existing config
    if existing_config:
        is_locked, lock_reason = check_pit_event_locked(existing_config, semester)
        if is_locked:
            changing_rubrics = (
                existing_config.panel_rubric_id != (panel_rubric.id if panel_rubric else None)
                or existing_config.peer_rubric_id != (peer_rubric.id if peer_rubric else None)
            )
            changing_weights = (
                existing_config.panel_weight != panel_weight
                or existing_config.peer_weight != peer_weight
            )
            changing_code = (
                event_code is not None and (existing_config.event_code or '').strip() != event_code.strip()
            )
            if changing_rubrics or changing_weights or changing_code:
                raise ValidationError(f"Cannot update configuration parameters: {lock_reason}")

            if deliverables is not None:
                existing_delivs = list(existing_config.deliverables.all().values(
                    'id', 'label', 'deliverable_type', 'required'
                ))
                if len(deliverables) != len(existing_delivs):
                    raise ValidationError(f"Cannot add or remove deliverables: {lock_reason}")
                for d in deliverables:
                    d_id = d.get('id')
                    if not d_id:
                        raise ValidationError(f"Cannot add new deliverables: {lock_reason}")
                    existing_d = next((item for item in existing_delivs if item['id'] == d_id), None)
                    if not existing_d:
                        raise ValidationError(f"Cannot modify deliverables: {lock_reason}")
                    if (
                        existing_d['label'] != d.get('label', '').strip()
                        or existing_d['deliverable_type'] != d.get('deliverable_type', 'pre').strip()
                        or existing_d['required'] != bool(d.get('required', True))
                    ):
                        raise ValidationError(f"Cannot modify deliverable checklist: {lock_reason}")

    defaults = {
        'panel_rubric': panel_rubric,
        'peer_rubric': peer_rubric,
        'panel_weight': panel_weight,
        'peer_weight': peer_weight,
    }
    if event_code is not None:
        defaults['event_code'] = event_code.strip()
    if archive_file_template is not None:
        defaults['archive_file_template'] = archive_file_template.strip()

    with transaction.atomic():
        config, _created = PitEventGradingConfig.objects.update_or_create(
            semester=semester,
            event_name=event_name,
            defaults=defaults,
        )
        if deliverables is not None:
            # Reconcile deliverables instead of blind delete and recreate
            keep_ids = []
            for d in deliverables:
                d_id = d.get('id')
                if d_id:
                    try:
                        keep_ids.append(int(d_id))
                    except (ValueError, TypeError):
                        pass
            
            # Delete those that are not kept
            config.deliverables.exclude(id__in=keep_ids).delete()
            
            for index, d in enumerate(deliverables, start=1):
                d_id = d.get('id')
                label = d.get('label', '').strip()
                deliv_type = d.get('deliverable_type', 'pre').strip()
                required = bool(d.get('required', True))
                display_order = int(d.get('display_order', index))
                archive_note = d.get('archive_note', '').strip()
                archive_file_template = d.get('archive_file_template', '').strip()
                is_restricted = bool(d.get('is_restricted', False))
                
                # Check client-provided deliverable_id (usually empty/generated)
                provided_deliv_id = d.get('deliverable_id', '').strip()
                
                if d_id:
                    # Update existing
                    deliv = config.deliverables.filter(id=d_id).first()
                    if deliv:
                        deliv.label = label
                        deliv.deliverable_type = deliv_type
                        deliv.required = required
                        deliv.display_order = display_order
                        deliv.archive_note = archive_note
                        deliv.archive_file_template = archive_file_template
                        deliv.is_restricted = is_restricted
                        
                        # Use provided ID if non-empty, otherwise fallback to database ID string
                        if provided_deliv_id:
                            deliv.deliverable_id = provided_deliv_id
                        elif not deliv.deliverable_id or deliv.deliverable_id.startswith('d_') or deliv.deliverable_id.startswith('deliv_'):
                            deliv.deliverable_id = str(deliv.id)
                        deliv.save()
                else:
                    # Create new
                    deliv = PitEventDeliverable.objects.create(
                        pit_event_config=config,
                        deliverable_id=provided_deliv_id,
                        label=label,
                        deliverable_type=deliv_type,
                        required=required,
                        display_order=display_order,
                        archive_note=archive_note,
                        archive_file_template=archive_file_template,
                        is_restricted=is_restricted,
                    )
                    # If deliverable_id is empty, use the stringified database primary key ID
                    if not deliv.deliverable_id:
                        deliv.deliverable_id = str(deliv.id)
                        deliv.save()
    return config


def pit_event_config_payload(config):
    if config is None:
        return None
    is_locked, lock_reason = check_pit_event_locked(config)
    deliverables_data = [
        {
            'id': d.id,
            'deliverable_id': d.deliverable_id,
            'label': d.label,
            'deliverable_type': d.deliverable_type,
            'required': d.required,
            'display_order': d.display_order,
            'archive_note': d.archive_note,
            'archive_file_template': d.archive_file_template,
            'is_restricted': d.is_restricted,
        }
        for d in config.deliverables.all().order_by('display_order', 'deliverable_id')
    ]
    return {
        'id': config.id,
        'event_name': config.event_name,
        'event_code': config.event_code,
        'panel_rubric_id': config.panel_rubric_id,
        'peer_rubric_id': config.peer_rubric_id,
        'panel_weight': config.panel_weight,
        'peer_weight': config.peer_weight,
        'is_officially_complete': config.is_officially_complete,
        'peer_grading_enabled': config.peer_grading_enabled,
        'archive_file_template': config.archive_file_template,
        'is_locked': is_locked,
        'lock_reason': lock_reason,
        'deliverables': deliverables_data,
    }

