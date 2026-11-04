"""Evaluation roles for new concept hearings and their captured assessments."""

PANEL_ONLY_CONCEPT = 'panel_only_concept'
PANEL_ONLY_WEIGHTS = {'panel_weight': 100, 'adviser_weight': 0, 'peer_weight': 0}


def concept_stage(stage):
    return bool(stage and (getattr(stage, 'concept_config', None) or {}).get('enabled'))


def panel_only_grade(grade):
    if grade.schedule_id:
        # An existing hearing's policy wins over later edits to its stage.
        return (grade.schedule.assessment_policy or {}).get('evaluation_mode') == PANEL_ONLY_CONCEPT
    if grade.scope == 'pit':
        return concept_stage(grade.pit_event_config) if grade.pit_event_config_id else False
    return concept_stage(grade.defense_stage) if grade.defense_stage_id else False
