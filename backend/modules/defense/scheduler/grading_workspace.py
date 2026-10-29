"""Read-only, hearing-bound materials and shared decision context for grading."""
from defensys_backend.read_projection import read_memoize


def _context(schedule, hearing):
    if hearing:
        return hearing.defense_stage or hearing.pit_event_config
    if schedule.scope == 'capstone':
        return schedule.defense_stage
    from .pit_config import get_pit_event_config
    return get_pit_event_config(schedule.semester, schedule.event_name,
                                year_level=schedule.team.year_level)


def _materials(profile, actor):
    from repository.section_concepts import shared_deliverables as shared
    from repository.section_concepts.models import SectionConceptPaper, SharedDeliverableFile

    hearing = profile.get('round')
    # Later stages inherit the selected system's round for identity only;
    # its decision snapshot contains that earlier context's documents.
    frozen = (hearing.decision_snapshot.get('shared_documents')
              if hearing and hearing.verdict and profile.get('current_project') else None)
    output, seen = [], set()
    for definition in profile['definitions']:
        if definition['deliverable_type'] != 'pre' or not definition.get('is_defense_material'):
            continue
        slots = {slot['key']: slot for slot in shared.slots(profile, definition)}
        if frozen is not None:
            files = {}
            for item in frozen:
                if item['deliverable_id'] != definition['deliverable_id']:
                    continue
                model = SectionConceptPaper if item.get('legacy') else SharedDeliverableFile
                row = model.objects.filter(pk=item['id'], revision=item['revision']).first()
                if not row:
                    continue
                allowed = (shared.can_read_legacy_file(actor, row) if item.get('legacy')
                           else shared.can_read_file(actor, row))
                if allowed:
                    files[item['slot_key']] = shared.file_payload(row, legacy=item.get('legacy', False),
                        project_id=profile['project'].pk if profile.get('project') else None)
        else:
            files = shared.requirement_files(profile, definition)
        for key in dict.fromkeys([*slots, *files]):
            file = files.get(key)
            per_system = (definition.get('file_policy') or {}).get('mode') == 'concepts'
            candidate_key = key.split(':', 1)[0] if per_system else ''
            slot = slots.get(key, {})
            label = slot.get('label') or definition['label']
            if file is None:
                output.append({'slot_key': key, 'candidate_key': candidate_key,
                    'material_scope': 'shared', 'deliverable_id': definition['deliverable_id'],
                    'label': label, 'requirement_label': definition['label'], 'missing': True})
                continue
            identity = (file.get('legacy', False), file['id'], file['revision'])
            if identity in seen:
                continue
            seen.add(identity)
            output.append({**file, 'slot_key': key, 'candidate_key': candidate_key,
                'material_scope': 'shared', 'deliverable_id': definition['deliverable_id'],
                'name': label, 'label': label, 'requirement_label': definition['label'],
                'is_defense_material': True})
    return output


@read_memoize(copy=True)
def shared_context(schedule, hearing, actor):
    """Reuse shared checklist resolution and its existing scoped file policy."""
    if actor is None:
        return {}
    from repository.section_concepts import services, shared_deliverables as shared

    section_round = hearing.section_round if hearing and hearing.section_round_id else None
    profile = shared.for_round(section_round) if section_round else shared.resolve(
        schedule.team, _context(schedule, hearing))
    if not profile or not (shared.panel_access(actor, profile) or shared.staff_access(actor, profile)):
        return {}
    definitions = [d for d in profile['definitions']
                   if d['deliverable_type'] == 'pre' and d.get('is_defense_material')]
    result = {'shared_materials': _materials(profile, actor),
              'shared_materials_configured': bool(definitions)}
    if not section_round:
        return result

    project = section_round.project
    latest = services.latest(project)
    current = bool(latest and latest.pk == section_round.pk
                   and schedule.project_version == schedule.team.project_version)
    allowed = current and not section_round.verdict and services.decision_allowed(section_round, actor)
    reason = ''
    if not current:
        reason = 'This shared hearing is historical and read-only.'
    elif section_round.verdict:
        reason = 'The shared system decision is recorded.'
    elif not allowed:
        reason = 'The common panel chair records the shared system decision.'
    else:
        try:
            services.require_active(project)
        except PermissionError as exc:
            reason = str(exc)
        if not reason:
            reason = services.selection_blocker(section_round)
    # decide() already starts an eligible presentation within its transaction.
    # The inline control uses that operation rather than adding a second gate.
    result['shared_review'] = {
        'id': project.pk, 'round_id': section_round.pk,
        'review_token': services.review_token(section_round),
        'section': project.section.section,
        'teams': [{'id': team.pk, 'name': team.name} for team in profile['teams']],
        'systems': list(section_round.systems.order_by('pk').values('key', 'title', 'decision', 'remarks')),
        'selected_key': section_round.selected_key, 'verdict': section_round.verdict,
        'remarks': section_round.remarks, 'can_decide': bool(allowed and not reason),
        'decision_unavailable_reason': reason,
    }
    return result


def payload(schedule, hearing, actor, team_materials):
    keys = {c['key'] for c in hearing.concepts} if hearing else set()
    materials = []
    for file in team_materials:
        key = str(file.get('slot_key') or '').split(':', 1)[0]
        materials.append({**file, 'candidate_key': key if key in keys else '',
                          'material_scope': 'team'})
    return {'team_materials': materials, **shared_context(schedule, hearing, actor)}
