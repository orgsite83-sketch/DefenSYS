"""Stable assessment identities for comparing academic-year cohorts."""


def comparison_key(explorer, grade):
    if explorer.scope == 'capstone':
        return explorer.context_key(grade)
    name = grade.pit_event_config.event_name if grade.pit_event_config_id else grade.stage_label
    name = ' '.join(name.casefold().split())
    return f'pit:{grade.semester.label}:{name}'


def comparison_options(explorer):
    options = {}
    for grade in explorer.grades:
        key = comparison_key(explorer, grade)
        if key not in options:
            label = grade.defense_stage.label if grade.defense_stage_id else (
                grade.pit_event_config.event_name if grade.pit_event_config_id else grade.stage_label)
            options[key] = {'id': key, 'label': label, 'contexts': [],
                            'semester_label': grade.semester.label if explorer.scope == 'pit' else None}
            if explorer.scope == 'pit':
                options[key]['label'] += f' ({grade.semester.label})'
        context = explorer.context_key(grade)
        if context not in options[key]['contexts']:
            options[key]['contexts'].append(context)
    return sorted(options.values(), key=lambda option: option['label'].casefold())
