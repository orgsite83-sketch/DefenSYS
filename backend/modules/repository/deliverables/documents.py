"""Current document slots and append-only file revisions."""
from uuid import uuid4
from django.core.exceptions import ValidationError
from django.utils import timezone
from .models import DeliverableSubmissionFile


def current_files(submission):
    return [f for f in submission.files.all() if f.is_current] if submission else []


def slots_for(definition, team=None, stage=None):
    policy = definition.get('file_policy') or {}
    mode = policy.get('mode', 'single')
    slots = policy.get('slots') or [{'key': 'paper', 'label': 'Concept paper', 'required': True,
                                     'file_format': definition.get('file_format') if definition.get('file_format') not in (None, 'any', '') else 'pdf'}]
    if mode == 'concepts':
        policy = definition.get('concept_policy')
        if policy is None and team is not None and stage is not None:
            from student_teams.concept_policy import resolve_policy
            policy = resolve_policy(team, stage)
        count = (policy or (stage.concept_config if stage else {}) or {}).get('required_count', 3)
        keys = (policy or {}).get('concept_keys') or [f'c{i}' for i in range(1, count + 1)]
        return [{**s, 'key': f'{key}:{s["key"]}', 'label': f'Concept {key.removeprefix("c")} · {s["label"]}'}
                for key in keys for s in slots]
    if mode == 'named':
        return slots
    if mode == 'single':
        return [{'key': 'primary', 'label': definition['label'], 'required': True,
                 'file_format': definition.get('file_format', 'any')}]
    return []


def completeness(submission, definition, *, accepted=False, stage=None):
    files = current_files(submission)
    if not (definition.get('file_policy') or {}):
        if submission and not submission.file and not files and submission.files.exists():
            return False
        # Legacy metadata fixtures and historical primary-file records retain their semantics.
        return bool(submission and (not accepted or submission.status == 'accepted'))
    if accepted and (definition.get('file_policy') or {}).get('mode') == 'concepts' and definition.get('type') != 'post':
        from repository.title_workflow import team_guard, file_acceptance
        try:
            for f in files:
                file_acceptance(f, team_guard(submission.team, stage, f.slot_key.split(':')[0], accepting=True))
        except ValidationError:
            return False
    valid = [f for f in files if f.file and (f.status == 'accepted' if accepted else f.status != 'rejected')]
    mode = definition['file_policy'].get('mode', 'single')
    if mode == 'multiple':
        policy = definition['file_policy']
        within_limits = policy.get('min_files', 1) <= len(valid) <= policy.get('max_files', 10)
        # Acceptance covers every submitted attachment, including extras beyond
        # the minimum. One accepted file must not conceal unreviewed evidence.
        return within_limits and (not accepted or len(valid) == len(files))
    present = {f.slot_key for f in valid}
    return all(s['key'] in present for s in slots_for(definition, stage=stage) if s.get('required', True))


def file_payload(f):
    return {'id': f.pk, 'slot_key': f.slot_key, 'revision': f.revision,
            'is_current': f.is_current, 'file_name': f.file_name, 'file_size': f.file_size,
            'file_url': f.file.url if f.file else None, 'uploaded_at': f.uploaded_at.isoformat(),
            'status': f.status, 'feedback': f.feedback, 'title_review_context': f.title_review_context,
            'concept_round_id': f.concept_round_id, 'selected_concept_key': f.selected_concept_key,
            'reviewed_at': f.reviewed_at.isoformat() if f.reviewed_at else None}


def snapshot_files(submission):
    files = [file_payload(f) for f in current_files(submission)]
    if not files and submission.file and not submission.files.exists():
        # Older uploads can exist only on the parent record. Preserve that real
        # evidence in a hearing snapshot before the first version row is made.
        return [{'id': None, 'slot_key': 'primary', 'revision': 1,
            'is_current': True, 'file_name': submission.file_name, 'file_size': submission.file_size,
            'file_url': submission.file.url, 'status': submission.status, 'feedback': submission.feedback,
            'uploaded_at': submission.uploaded_at.isoformat(),
            'reviewed_at': submission.reviewed_at.isoformat() if submission.reviewed_at else None}]
    return files


def sync_submission(submission, definition, stage=None):
    files = current_files(submission)
    latest = max(files, key=lambda f: (f.uploaded_at, f.pk), default=None)
    for name, default in [('file', None), ('file_name', ''), ('file_size', ''),
                          ('extracted_text', ''), ('topics', []), ('summary', ''),
                          ('category', ''), ('category_confidence', None), ('classification', {})]:
        setattr(submission, name, getattr(latest, name) if latest else default)
    if definition.get('file_policy'):
        submission.status = ('accepted' if completeness(submission, definition, accepted=True, stage=stage)
                             else 'rejected' if any(f.status == 'rejected' for f in files) else 'pending')
        submission.feedback = '\n'.join(f'{f.file_name}: {f.feedback}' for f in files if f.status == 'rejected' and f.feedback)
    submission.save()


def store_revision(submission, definition, *, file, file_name, file_size, slot_key='', file_id=None,
                   preserve_approval=False, stage=None):
    from .timing import validate_material_file
    from django.core.files.base import ContentFile
    from defensys_backend.file_cleanup import replacement_file_name
    policy = definition.get('file_policy') or {}
    mode = policy.get('mode', 'single')
    files = current_files(submission)
    previous = next((f for f in files if f.pk == file_id), None) if file_id else None
    if file_id and previous is None:
        raise ValueError('The current file was not found. Refresh the submission.')
    key = previous.slot_key if previous else slot_key
    if mode == 'single':
        key = 'primary'
    elif mode == 'multiple':
        key = key or uuid4().hex
        if not previous and not any(f.slot_key == key for f in files) and len(files) >= policy.get('max_files', 10):
            raise ValueError('This deliverable has reached its file limit.')
    else:
        configured = {s['key']: s for s in slots_for(definition, stage=stage)}
        if key not in configured:
            raise ValueError('Choose the document this upload belongs to.')
        definition = {**definition, 'file_format': configured[key].get('file_format', definition.get('file_format', 'any'))}
    if file is not None and policy:
        validate_material_file(definition, file_name, file)
    if policy and file is None:
        raise ValueError('Choose a file before submitting.')
    old = [f for f in files if f.slot_key == key]
    if policy and any(f.status == 'accepted' for f in old) and not preserve_approval:
        raise PermissionError('Request corrections for this document before replacing an accepted file.')
    revision = max((f.revision for f in submission.files.all() if f.slot_key == key), default=0) + 1
    submission.files.filter(slot_key=key, is_current=True).update(is_current=False)
    submission._prefetched_objects_cache = {}
    if preserve_approval and old:
        # Administrative approved-file correction keeps the public archive entry ID.
        # Preserve the original stored bytes in a separate historical revision.
        row = old[0]
        archive = DeliverableSubmissionFile(submission=submission, slot_key=key, is_current=False,
            title_review_context=row.title_review_context,
            concept_round_id=row.concept_round_id, selected_concept_key=row.selected_concept_key,
            revision=row.revision, file=row.file, file_name=row.file_name, file_size=row.file_size,
            status=row.status, feedback=row.feedback, reviewed_at=row.reviewed_at, reviewed_by=row.reviewed_by,
            extracted_text=row.extracted_text, topics=row.topics, summary=row.summary,
            category=row.category, category_confidence=row.category_confidence, classification=row.classification)
        archive.save()
        # auto_now_add applies to the copy; its evidence belongs to the original
        # upload, not the date on which an administrator replaced the file.
        DeliverableSubmissionFile.objects.filter(pk=archive.pk).update(uploaded_at=row.uploaded_at)
        row.is_current, row.revision, row.uploaded_at = True, revision, timezone.now()
        row.file_name, row.file_size = file_name.strip(), (file_size or '').strip()
        row.extracted_text, row.topics, row.summary = '', [], ''
        row.category, row.category_confidence, row.classification = '', None, {}
    else:
        row = DeliverableSubmissionFile(submission=submission, slot_key=key, revision=revision,
            file_name=file_name.strip(), file_size=(file_size or '').strip(),
            status='accepted' if preserve_approval else 'pending')
    if file is not None:
        row.file = ContentFile(file.read(), name=replacement_file_name(file_name.strip()))
    from defense.document_policy import is_approved_concept
    from .concepts import enabled
    if is_approved_concept(definition) and enabled(stage):
        from .concepts import latest_round
        hearing = latest_round(submission.team, stage)
        selected = next((c['key'] for c in hearing.concepts if c.get('decision') in ('approved', 'approved_with_revisions')), '') if hearing else ''
        if not hearing or not hearing.schedule_id or not selected:
            raise ValidationError('The chair must record the selected concept before uploading its final paper.')
        row.concept_round, row.selected_concept_key = hearing, selected
    if mode == 'concepts' and definition.get('type') != 'post':
        from repository.title_workflow import team_guard
        row.title_review_context = team_guard(submission.team, stage, key.split(':')[0])
    row.save()
    return row


def review_files(submission, definition, status, feedback, reviewer, *, file_id=None, stage=None):
    files = current_files(submission)
    targets = [f for f in files if f.pk == file_id] if file_id else files
    if file_id and not targets:
        raise ValueError('The current document was not found. Refresh before reviewing.')
    if status == 'rejected' and not feedback.strip():
        raise ValueError('Explain what needs to be corrected.')
    if status == 'accepted' and not file_id and definition.get('file_policy'):
        if not completeness(submission, definition, stage=stage):
            raise ValueError('Upload all required documents and resolve corrections before accepting the group.')
    if status == 'accepted' and (definition.get('file_policy') or {}).get('mode') == 'concepts' and definition.get('type') != 'post':
        from repository.title_workflow import team_guard, file_acceptance
        for f in targets:
            file_acceptance(f, team_guard(submission.team, stage, f.slot_key.split(':')[0], accepting=True))
    for f in targets:
        f.status, f.feedback, f.reviewed_by, f.reviewed_at = status, feedback.strip(), reviewer, timezone.now()
        f.save(update_fields=['status', 'feedback', 'reviewed_by', 'reviewed_at'])
    submission._prefetched_objects_cache = {}
