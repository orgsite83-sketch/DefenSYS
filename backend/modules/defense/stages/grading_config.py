"""Stage-level grade composition (Panel / Adviser / Peer) per semester."""

from academic_period_management.models import Semester

from .models import (
    DEFAULT_ADVISER_WEIGHT,
    DEFAULT_PANEL_WEIGHT,
    DEFAULT_PEER_WEIGHT,
    DefenseStage,
    StageGradingConfig,
)


def default_capstone_weights():
    return {
        'panel_weight': DEFAULT_PANEL_WEIGHT,
        'adviser_weight': DEFAULT_ADVISER_WEIGHT,
        'peer_weight': DEFAULT_PEER_WEIGHT,
    }


def resolve_semester(semester_id=None):
    if semester_id:
        return Semester.objects.select_related('school_year').filter(pk=semester_id).first()
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def get_or_create_stage_grading_config(stage, semester, *, defaults=None):
    if stage is None or semester is None:
        return None
    create_defaults = defaults or default_capstone_weights()
    config, _created = StageGradingConfig.objects.select_related(
        'panel_rubric',
        'adviser_rubric',
        'peer_rubric',
    ).get_or_create(
        defense_stage=stage,
        semester=semester,
        defaults=create_defaults,
    )
    return config


def weights_for_capstone_stage(stage, semester):
    """Return panel/adviser/peer weights for a capstone defense stage."""
    if stage is None or semester is None:
        return default_capstone_weights()
    config = get_or_create_stage_grading_config(stage, semester)
    return config.as_weights_dict()


def grading_config_payload(config):
    if config is None:
        weights = default_capstone_weights()
        return {
            **weights,
            'weights': {
                'panel': weights['panel_weight'],
                'adviser': weights['adviser_weight'],
                'peer': weights['peer_weight'],
            },
            'semester_id': None,
        }
    return {
        'id': config.id,
        'semester_id': config.semester_id,
        'panel_weight': config.panel_weight,
        'adviser_weight': config.adviser_weight,
        'peer_weight': config.peer_weight,
        'is_officially_complete': config.is_officially_complete,
        'peer_grading_enabled': config.peer_grading_enabled,
        'weights': {
            'panel': config.panel_weight,
            'adviser': config.adviser_weight,
            'peer': config.peer_weight,
        },
        'updated_at': config.updated_at,
    }


def sync_rubric_weights_from_stage(rubric):
    """Mirror stage grading config onto a capstone rubric row (backward compatibility)."""
    from grading.rubrics.models import Rubric

    if rubric.scope != Rubric.SCOPE_CAPSTONE or not rubric.defense_stage_id:
        return rubric
    weights = weights_for_capstone_stage(rubric.defense_stage, rubric.semester)
    rubric.panel_weight = weights['panel_weight']
    rubric.adviser_weight = weights['adviser_weight']
    rubric.peer_weight = weights['peer_weight']
    return rubric
