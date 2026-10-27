from django.db import transaction
from django.core.exceptions import ValidationError

from grading.rubrics.models import Rubric

from .models import PitEventGradingConfig, PitEventDeliverable
from defense.deliverable_timing import validate_timing
from defense.shared_deliverables import shared_definitions


DEFAULT_PIT_PANEL_WEIGHT = 80
DEFAULT_PIT_PEER_WEIGHT = 20


def default_pit_weights():
    return {
        'panel_weight': DEFAULT_PIT_PANEL_WEIGHT,
        'peer_weight': DEFAULT_PIT_PEER_WEIGHT,
        'adviser_weight': 0,
    }


from defensys_backend.read_projection import read_memoize


@read_memoize
def get_pit_event_config(semester, event_name, *, year_level=None):
    if not semester or not (event_name or '').strip():
        return None
    configs = (
        PitEventGradingConfig.objects.select_related('panel_rubric', 'peer_rubric')
        .prefetch_related('deliverables')
        .filter(semester=semester, event_name__iexact=event_name.strip())
    )
    if year_level is not None:
        from .event_scope import pit_year
        year = pit_year(year_level)
        if not year:
            return None
        configs = configs.filter(year_level=year)
    return configs.first()


def pit_endorsement_required(config):
    """Only required files cleared before scheduling need a PIT endorsement."""
    return bool(config and config.deliverables.filter(
        deliverable_type=PitEventDeliverable.TYPE_PRE,
        required=True,
    ).exists())


def weights_for_pit_event(semester, event_name, *, year_level=None):
    config = get_pit_event_config(semester, event_name, year_level=year_level)
    if config is None:
        return default_pit_weights()
    return {
        'panel_weight': config.panel_weight,
        'peer_weight': config.peer_weight,
        'adviser_weight': 0,
    }


def peer_rubric_for_pit_event(semester, event_name, *, year_level=None):
    config = get_pit_event_config(semester, event_name, year_level=year_level)
    if config is None:
        return None
    return config.peer_rubric


@read_memoize
def check_pit_event_locked(config, semester=None):
    if not config:
        return False, None

    if config.is_officially_complete:
        return True, 'This PIT event is officially complete for the active semester.'
    from repository.section_concepts.models import SharedDeliverableSet
    if SharedDeliverableSet.objects.filter(pit_event_config=config).exists():
        return True, 'A section has started shared deliverable submissions for this PIT event.'
    from repository.deliverables.models import ConceptRound
    from repository.section_concepts.models import SectionConceptProject
    if SectionConceptProject.objects.filter(pit_event_config=config).exists():
        return True, 'A section has already started shared system concepts for this PIT event.'
    if ConceptRound.objects.filter(pit_event_config=config).exists():
        return True, 'Students have already started concept submissions for this PIT event.'

    sem = semester or config.semester

    from django.db.models import Q
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade

    # 1. Scheduled Defenses
    if sem and DefenseSchedule.objects.filter(semester=sem, scope='pit', team__year_level=config.year_level, event_name__iexact=config.event_name).exists():
        return True, 'This PIT event has scheduled defenses for the active semester.'

    # 2. Recorded Evaluation Grades
    grades_exist = TeamGrade.objects.filter(pit_event_config=config).exclude(status=TeamGrade.STATUS_PENDING).exists()
    if not grades_exist and sem:
        grades_exist = TeamGrade.objects.filter(
            semester=sem,
            scope=TeamGrade.SCOPE_PIT,
            team__year_level=config.year_level,
            stage_label__iexact=config.event_name,
        ).exclude(status=TeamGrade.STATUS_PENDING).exists()

    if grades_exist:
        return True, 'This PIT event has recorded evaluation grades.'

    return False, None


@transaction.atomic
def upsert_pit_event_config(
    *,
    semester,
    event_name,
    year_level,
    config_id=None,
    event_code=None,
    panel_rubric=None,
    peer_rubric=None,
    panel_weight=80,
    peer_weight=20,
    archive_file_template=None,
    deliverables=None,
    peer_grading_enabled=None,
    concept_config=None,
    shared_deliverables=None,
    project_setup_policy=None,
    user=None,
    request=None,
):
    from django.db.models import Q
    from grading.grades.models import TeamGrade

    event_name = (event_name or '').strip()
    from .event_scope import require_pit_year, require_event_management
    year_level = require_pit_year(year_level)
    if not event_name:
        raise ValidationError({'event_name': 'PIT event name is required.'})
    if panel_weight + peer_weight != 100:
        raise ValidationError('Panel and peer weights must total 100%.')
    if deliverables is not None:
        from rest_framework.exceptions import ValidationError as ApiValidationError
        if not isinstance(deliverables, list) or any(not isinstance(item, dict) for item in deliverables):
            raise ValidationError({'deliverables': 'Deliverables must be a list of document requirements.'})
        for item in deliverables:
            try:
                item.update(validate_timing(item))
            except ApiValidationError as exc:
                raise ValidationError({'deliverables': str(exc.detail)}) from exc

    configs = PitEventGradingConfig.objects.select_for_update().filter(semester=semester)
    if config_id is not None:
        # Names are editable. An explicit ID must resolve to the original event
        # and must never fall back to creating (or updating) a different event.
        if isinstance(config_id, bool) or not str(config_id).isdigit():
            raise ValidationError({'config_id': 'Choose a valid PIT event to edit.'})
        config_id = int(config_id)
        if not 0 < config_id <= 9223372036854775807:
            raise ValidationError({'config_id': 'Choose a valid PIT event to edit.'})
        existing_config = configs.filter(pk=config_id).first()
        if existing_config is None:
            raise ValidationError({'config_id': 'This PIT event no longer exists in the selected semester.'})
    else:
        # Retain the name-based upsert used by existing rubric clients.
        existing_config = configs.filter(event_name__iexact=event_name).first()
    if existing_config and existing_config.year_level != year_level:
        raise ValidationError({'year_level': 'This event belongs to a different or unclassified PIT year level.'})
    if user is not None:
        from types import SimpleNamespace
        require_event_management(user, existing_config or SimpleNamespace(year_level=year_level))
    if configs.filter(event_name__iexact=event_name).exclude(
        pk=existing_config.pk if existing_config else None
    ).exists():
        raise ValidationError({'event_name': 'A PIT event with this name already exists in the selected semester.'})
    for rubric in (panel_rubric, peer_rubric):
        owner_year = getattr(getattr(rubric, 'created_by', None), 'pit_lead_year', '')
        if owner_year and owner_year != year_level:
            raise ValidationError({'rubric': 'Selected rubric belongs to a different PIT year level.'})
        if rubric and rubric.semester_id != semester.pk:
            raise ValidationError({'rubric': 'Selected rubric belongs to a different semester.'})
    old_values = pit_event_audit_values(existing_config) if existing_config else {}
    if project_setup_policy is not None and project_setup_policy not in ('continue', 'new'):
        raise ValidationError({'project_setup_policy': 'Choose existing projects allowed or new projects required.'})
    if existing_config and project_setup_policy is not None and project_setup_policy != existing_config.project_setup_policy:
        from student_teams.pit_rosters import event_in_use
        sections = set(existing_config.section_rosters.values_list('section', flat=True))
        from student_teams.models import StudentTeam
        sections.update(StudentTeam.objects.filter(semester=semester, year_level=year_level,
            level__icontains='PIT').values_list('section', flat=True))
        if existing_config.is_officially_complete or any(event_in_use(existing_config, section) for section in sections):
            raise ValidationError('Project requirements cannot change after event setup or activity begins.')
    from defense.document_policy import validate_concept_config, validate_file_policy, with_concept_papers
    concept_config = validate_concept_config(
        concept_config if concept_config is not None else getattr(existing_config, 'concept_config', {}))
    concept_deliverables = deliverables if deliverables is not None else (
        list(existing_config.deliverables.values())
        if existing_config else [])
    effective_shared = shared_deliverables if shared_deliverables is not None else getattr(existing_config, 'shared_deliverables', None)
    generated = with_concept_papers(concept_deliverables, concept_config,
                                   shared_items=effective_shared if isinstance(effective_shared, list) else [])
    if generated != concept_deliverables:
        concept_deliverables = deliverables = generated
    from defense.shared_deliverables import validate_shared_deliverables, shared_definitions
    if shared_deliverables is None and existing_config and any(
            row.get('team_deliverable_id') for row in (existing_config.shared_deliverables or [])):
        shared_deliverables = existing_config.shared_deliverables
    if shared_deliverables is not None:
        shared_deliverables = validate_shared_deliverables(shared_deliverables, concept_config, concept_deliverables)
        if existing_config:
            shared_locked, shared_reason = check_pit_event_locked(existing_config)
            if shared_locked and shared_deliverables != validate_shared_deliverables(shared_definitions(existing_config), existing_config.concept_config):
                raise ValidationError(f'Cannot modify shared deliverables: {shared_reason}')
    concept_items = []
    for item in concept_deliverables:
        policy = validate_file_policy(item.get('file_policy', {}))
        if policy.get('mode') == 'concepts':
            concept_items.append(item)
    if any(d.get('deliverable_type', 'pre') != 'pre' for d in concept_items):
        raise ValidationError('Concept documents must be pre-defense requirements.')
    shared_concepts = [d for d in shared_deliverables or [] if d.get('deliverable_type') == 'pre'
                       and (d.get('file_policy') or {}).get('mode') == 'concepts']
    if concept_config.get('enabled') and not any(
        d.get('required', True) and d.get('requirement_timing', 'scheduling') == 'scheduling'
        for d in concept_items + shared_concepts
    ):
        raise ValidationError('Concept selection needs a required concept-documents deliverable cleared before scheduling.')

    # Rubric Exclusivity Check
    if panel_rubric:
        other = PitEventGradingConfig.objects.filter(semester=semester).exclude(
            pk=existing_config.pk if existing_config else None
        ).filter(
            Q(panel_rubric=panel_rubric) | Q(peer_rubric=panel_rubric)
        ).first()
        if other:
            raise ValidationError(
                f"Panel Rubric '{panel_rubric.name}' is already assigned to PIT event '{other.event_name}'."
            )

    if peer_rubric:
        other = PitEventGradingConfig.objects.filter(semester=semester).exclude(
            pk=existing_config.pk if existing_config else None
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
            changing_name = existing_config.event_name != event_name
            if changing_name or changing_rubrics or changing_weights or changing_code or existing_config.concept_config != concept_config:
                raise ValidationError(f"Cannot update configuration parameters: {lock_reason}")

            if deliverables is not None:
                existing_delivs = list(existing_config.deliverables.all().values(
                    'id', 'label', 'deliverable_type', 'required', 'is_defense_material',
                    'file_policy', 'requirement_timing', 'deadline_hours_before'
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
                        or existing_d.get('is_defense_material', False) != bool(d.get('is_defense_material', False))
                        or existing_d['file_policy'] != d.get('file_policy', {})
                        or existing_d['requirement_timing'] != d['requirement_timing']
                        or existing_d['deadline_hours_before'] != d['deadline_hours_before']
                    ):
                        raise ValidationError(f"Cannot modify deliverable checklist: {lock_reason}")

    defaults = {
        'year_level': year_level,
        'concept_config': concept_config,
        'panel_rubric': panel_rubric,
        'peer_rubric': peer_rubric,
        'panel_weight': panel_weight,
        'peer_weight': peer_weight,
    }
    if shared_deliverables is not None:
        defaults['shared_deliverables'] = shared_deliverables
    if project_setup_policy is not None:
        defaults['project_setup_policy'] = project_setup_policy
    if event_code is not None:
        defaults['event_code'] = event_code.strip()
    if archive_file_template is not None:
        defaults['archive_file_template'] = archive_file_template.strip()

    if peer_weight == 0:
        defaults['peer_grading_enabled'] = False
    elif peer_grading_enabled is not None:
        if existing_config and existing_config.is_officially_complete and peer_grading_enabled:
            raise ValidationError({'peer_grading_enabled': 'Peer grading cannot be enabled while the event is officially complete.'})
        defaults['peer_grading_enabled'] = bool(peer_grading_enabled)
    elif not existing_config:
        # Persist the access preference even when rubrics are attached later.
        # Per-team availability separately requires a configured peer rubric
        # and a finished panel assessment of the scheduled defense.
        defaults['peer_grading_enabled'] = True

    with transaction.atomic():
        if existing_config:
            old_name = existing_config.event_name
            config = existing_config
            config.event_name = event_name
            for field, value in defaults.items():
                setattr(config, field, value)
            config.save()
            _created = False
            if old_name != event_name:
                _rename_pit_event_references(config, old_name)
        else:
            config = PitEventGradingConfig.objects.create(
                semester=semester, event_name=event_name, **defaults,
            )
            _created = True
        if deliverables is not None:
            # Reconcile deliverables by primary key ID or deliverable_id
            existing_by_id = {d.id: d for d in config.deliverables.all()}
            existing_by_deliv_id = {d.deliverable_id: d for d in config.deliverables.all() if d.deliverable_id}

            matched_pks = set()
            paired_deliverables = []
            for index, d in enumerate(deliverables, start=1):
                d_id = d.get('id')
                provided_deliv_id = (d.get('deliverable_id') or '').strip()

                target = None
                if d_id:
                    try:
                        target = existing_by_id.get(int(d_id))
                    except (ValueError, TypeError):
                        pass
                if not target and provided_deliv_id:
                    target = existing_by_deliv_id.get(provided_deliv_id)

                if target:
                    matched_pks.add(target.id)
                paired_deliverables.append((target, d, index, provided_deliv_id))

            # Delete deliverables that were actually removed from the checklist
            to_delete = config.deliverables.exclude(id__in=matched_pks)
            from repository.deliverables.models import DeliverableSubmission
            for td in to_delete:
                if td.deliverable_id and DeliverableSubmission.objects.filter(
                    team__semester=semester, team__year_level=year_level, team__level__icontains='PIT',
                    stage_label__iexact=config.event_name,
                    deliverable_id=td.deliverable_id,
                ).exists():
                    raise ValidationError(
                        f"Cannot delete deliverable '{td.label}' because student submissions already exist for it."
                    )
            to_delete.delete()

            for target, d, index, provided_deliv_id in paired_deliverables:
                label = d.get('label', '').strip()
                deliv_type = d.get('deliverable_type', 'pre').strip()
                required = bool(d.get('required', True))
                display_order = int(d.get('display_order', index))
                archive_note = d.get('archive_note', '').strip()
                archive_file_template = d.get('archive_file_template', '').strip()
                is_restricted = bool(d.get('is_restricted', False))
                is_defense_material = bool(d.get('is_defense_material', False))
                file_format = (d.get('file_format') or 'any').strip()
                from defense.document_policy import validate_file_policy
                file_policy = validate_file_policy(d.get('file_policy', {}))

                if target:
                    # Update existing in-place
                    target.label = label
                    target.deliverable_type = deliv_type
                    target.required = required
                    target.display_order = display_order
                    target.archive_note = archive_note
                    target.archive_file_template = archive_file_template
                    target.is_restricted = is_restricted
                    target.is_defense_material = is_defense_material
                    target.requirement_timing = d['requirement_timing']
                    target.deadline_hours_before = d['deadline_hours_before']
                    target.file_format = file_format
                    target.file_policy = file_policy
                    if provided_deliv_id:
                        target.deliverable_id = provided_deliv_id
                    elif not target.deliverable_id or target.deliverable_id.startswith('d_') or target.deliverable_id.startswith('deliv_'):
                        target.deliverable_id = str(target.id)
                    target.save()
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
                        is_defense_material=is_defense_material,
                        requirement_timing=d['requirement_timing'],
                        deadline_hours_before=d['deadline_hours_before'],
                        file_format=file_format,
                        file_policy=file_policy,
                    )
                    if not deliv.deliverable_id:
                        deliv.deliverable_id = str(deliv.id)
                        deliv.save()
        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING,
            action='pit_event.create' if _created else 'pit_event.update', target=config,
            actor=user, request=request, old_values=old_values,
            new_values=pit_event_audit_values(config), strict=True)
    return config


def _rename_pit_event_references(config, old_name):
    """Keep current workflow labels attached to an event renamed before defense.

    Scheduled/completed events are locked above. Bulk updates preserve uploaded
    files, review timestamps and historical project snapshots.
    """
    from django.db.models import Q
    from grading.grades.models import TeamGrade
    from repository.deliverables.models import DeliverableSubmission
    from student_teams.models import StudentTeam

    legacy = Q(pit_event_config__isnull=True, stage_label__iexact=old_name)
    TeamGrade.objects.filter(
        Q(pit_event_config=config) | legacy,
        semester=config.semester, scope=TeamGrade.SCOPE_PIT,
        team__year_level=config.year_level,
    ).update(pit_event_config=config, stage_label=config.event_name,
             panel_weight=config.panel_weight, peer_weight=config.peer_weight)
    DeliverableSubmission.objects.filter(
        Q(pit_event_config=config) | legacy,
        team__semester=config.semester, team__year_level=config.year_level,
        team__level__icontains='PIT',
    ).update(pit_event_config=config, stage_label=config.event_name)
    teams = StudentTeam.objects.filter(
        semester=config.semester, year_level=config.year_level, level__icontains='PIT',
    )
    for field in ('current_defense_stage', 'ready_for_stage'):
        teams.filter(**{f'{field}__iexact': old_name}).update(**{field: config.event_name})
    for team in teams.exclude(unlocked_stages=[]).only('pk', 'unlocked_stages'):
        renamed = [config.event_name + value[len(old_name):]
                   if value == old_name or value.startswith(f'{old_name}:') else value
                   for value in team.unlocked_stages]
        if renamed != team.unlocked_stages:
            StudentTeam.objects.filter(pk=team.pk).update(unlocked_stages=renamed)


def pit_event_audit_values(config):
    values = pit_event_config_payload(config)
    return {**values, 'scope': 'pit', 'year_level': config.year_level,
            'semester_id': config.semester_id}


@read_memoize(copy=True)
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
            'is_defense_material': getattr(d, 'is_defense_material', False),
            'requirement_timing': d.requirement_timing,
            'deadline_hours_before': d.deadline_hours_before,
            'file_format': getattr(d, 'file_format', 'any') or 'any',
            'file_policy': d.file_policy,
        }
        for d in config.deliverables.all().order_by('display_order', 'deliverable_id')
    ]
    from student_teams.pit_rosters import resolve
    rosters = list(resolve(config.semester_id, config.year_level, config.pk).values())
    return {
        'id': config.id,
        'event_name': config.event_name,
        'roster_context': rosters,
        'roster_summary': 'Uses current roster automatically' if not any(r['source'] == 'custom' or r['in_use'] for r in rosters) else 'Includes saved or custom section rosters',
        'year_level': config.year_level,
        'event_code': config.event_code,
        'panel_rubric_id': config.panel_rubric_id,
        'panel_rubric_name': config.panel_rubric.name if config.panel_rubric_id else None,
        'peer_rubric_id': config.peer_rubric_id,
        'peer_rubric_name': config.peer_rubric.name if config.peer_rubric_id else None,
        'panel_weight': config.panel_weight,
        'peer_weight': config.peer_weight,
        'is_officially_complete': config.is_officially_complete,
        'peer_grading_enabled': config.peer_grading_enabled,
        'concept_config': config.concept_config,
        'shared_deliverables': shared_definitions(config),
        'team_membership_policy': config.team_membership_policy,
        'project_setup_policy': config.project_setup_policy,
        'roster_setup_opened': config.section_rosters.filter(started_at__isnull=False).exists(),
        'archive_file_template': config.archive_file_template,
        'is_locked': is_locked,
        'lock_reason': lock_reason,
        'deliverables': deliverables_data,
    }

