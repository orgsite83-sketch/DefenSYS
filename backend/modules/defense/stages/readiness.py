"""Read-only setup checks for the active semester, independent of defense progress."""


def stage_setup_readiness(stage, config, semester):
    issues = []
    required_roles = []
    if semester is None:
        issues.append('Activate a semester to configure grading.')
    elif config is None:
        issues.append('Configure grade weights and evaluation rubrics.')
    else:
        if sum((config.panel_weight, config.adviser_weight, config.peer_weight)) != 100:
            issues.append('Grade weights must total 100%.')
        enabled = {
            'panel': True,
            'adviser': semester.capstone_adviser_grading_enabled,
            'peer': semester.capstone_peer_evaluation_enabled,
        }
        for role, is_enabled in enabled.items():
            if not is_enabled or getattr(config, f'{role}_weight') <= 0:
                continue
            required_roles.append(role)
            rubric = getattr(config, f'{role}_rubric')
            if rubric is None:
                issues.append(f'Attach a {role} evaluation rubric.')
            elif rubric.status != 'published':
                issues.append(f'Publish the {role} evaluation rubric.')
            elif rubric.scope != 'capstone' or rubric.evaluation_type != role:
                issues.append(f'Choose a Capstone {role} evaluation rubric.')

    # Oral/demo stages intentionally have no student upload requirements.
    if not stage.is_presentation_only and not stage.deliverables.exists():
        issues.append('Add deliverable requirements or select presentation only.')

    return {
        'ready': not issues,
        'issues': issues,
        'required_rubric_roles': required_roles,
    }
