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


def upsert_pit_event_config(
    *,
    semester,
    event_name,
    panel_rubric,
    peer_rubric,
    panel_weight,
    peer_weight,
    vault_file_template=None,
    deliverables=None,
):
    event_name = (event_name or '').strip()
    if not event_name:
        raise ValidationError({'event_name': 'PIT event name is required.'})
    if panel_weight + peer_weight != 100:
        raise ValidationError('Panel and peer weights must total 100%.')
    
    defaults = {
        'panel_rubric': panel_rubric,
        'peer_rubric': peer_rubric,
        'panel_weight': panel_weight,
        'peer_weight': peer_weight,
    }
    if vault_file_template is not None:
        defaults['vault_file_template'] = vault_file_template.strip()

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
                vault_note = d.get('vault_note', '').strip()
                vault_file_template = d.get('vault_file_template', '').strip()
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
                        deliv.vault_note = vault_note
                        deliv.vault_file_template = vault_file_template
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
                        vault_note=vault_note,
                        vault_file_template=vault_file_template,
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
    deliverables_data = [
        {
            'id': d.id,
            'deliverable_id': d.deliverable_id,
            'label': d.label,
            'deliverable_type': d.deliverable_type,
            'required': d.required,
            'display_order': d.display_order,
            'vault_note': d.vault_note,
            'vault_file_template': d.vault_file_template,
            'is_restricted': d.is_restricted,
        }
        for d in config.deliverables.all().order_by('display_order', 'deliverable_id')
    ]
    return {
        'id': config.id,
        'event_name': config.event_name,
        'panel_rubric_id': config.panel_rubric_id,
        'peer_rubric_id': config.peer_rubric_id,
        'panel_weight': config.panel_weight,
        'peer_weight': config.peer_weight,
        'is_officially_complete': config.is_officially_complete,
        'peer_grading_enabled': config.peer_grading_enabled,
        'vault_file_template': config.vault_file_template,
        'deliverables': deliverables_data,
    }
