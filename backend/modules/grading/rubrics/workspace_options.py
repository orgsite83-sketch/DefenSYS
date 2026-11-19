"""Read-only destinations and authoritative rubric slots for the workspace."""
from defense.stages.grading_config import default_capstone_weights
from defense.stages.models import StageGradingConfig
from grading.grades.evaluation_policy import concept_stage


def rubric_slot(rubric, *, required):
    return {
        'required': bool(required),
        'rubric_id': rubric.pk if rubric else None,
        'rubric_name': rubric.name if rubric else None,
        'status': rubric.status if rubric else None,
    }


def stage_workspace_options(stages, semester):
    from defense.stages.serializers import DefenseStageSerializer

    stages = list(stages)
    configs = {
        config.defense_stage_id: config
        for config in StageGradingConfig.objects.filter(
            semester=semester, defense_stage__in=stages,
        ).select_related('panel_rubric', 'adviser_rubric', 'peer_rubric')
    } if semester else {}
    rows = DefenseStageSerializer(stages, many=True, context={'semester': semester}).data
    for stage, row in zip(stages, rows):
        config = configs.get(stage.pk)
        weights = config.as_weights_dict() if config else default_capstone_weights()
        panel_only = concept_stage(stage)
        enabled = {
            'panel': True,
            'adviser': bool(semester and semester.capstone_adviser_grading_enabled),
            'peer': bool(semester and semester.capstone_peer_evaluation_enabled),
        }
        row['rubric_slots'] = {
            role: rubric_slot(
                getattr(config, f'{role}_rubric', None),
                required=(role == 'panel' or (
                    not panel_only and enabled[role] and weights[f'{role}_weight'] > 0
                )),
            ) for role in ('panel', 'adviser', 'peer')
        }
    return rows
