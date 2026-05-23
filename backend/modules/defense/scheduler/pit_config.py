from django.core.exceptions import ValidationError

from grading.rubrics.models import Rubric

from .models import PitEventGradingConfig


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
):
    event_name = (event_name or '').strip()
    if not event_name:
        raise ValidationError({'event_name': 'PIT event name is required.'})
    if panel_weight + peer_weight != 100:
        raise ValidationError('Panel and peer weights must total 100%.')
    config, _created = PitEventGradingConfig.objects.update_or_create(
        semester=semester,
        event_name=event_name,
        defaults={
            'panel_rubric': panel_rubric,
            'peer_rubric': peer_rubric,
            'panel_weight': panel_weight,
            'peer_weight': peer_weight,
        },
    )
    return config


def pit_event_config_payload(config):
    if config is None:
        return None
    return {
        'event_name': config.event_name,
        'panel_rubric_id': config.panel_rubric_id,
        'peer_rubric_id': config.peer_rubric_id,
        'panel_weight': config.panel_weight,
        'peer_weight': config.peer_weight,
        'is_officially_complete': config.is_officially_complete,
        'peer_grading_enabled': config.peer_grading_enabled,
    }
