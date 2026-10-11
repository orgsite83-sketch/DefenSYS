"""Readable audit references, with immutable labels and batched legacy lookups.

Raw snapshots remain the evidence. Labels are saved separately when an event is
captured; older events can use current records, explicitly marked as such.
"""

from collections import defaultdict
from types import SimpleNamespace

from django.apps import apps
from django.core.exceptions import ValidationError
from django.utils.dateparse import parse_date, parse_time


REFERENCE_MODELS = {
    'semester': 'Semester', 'active_semester': 'Semester',
    'target_semester': 'Semester', 'from_semester': 'Semester',
    'to_semester': 'Semester', 'school_year': 'SchoolYear',
    'team': 'StudentTeam', 'selected_team': 'StudentTeam',
    'schedule': 'DefenseSchedule', 'defense_schedule': 'DefenseSchedule',
    'stage': 'DefenseStage', 'defense_stage': 'DefenseStage',
    'previous_stage': 'DefenseStage', 'reset_stage': 'DefenseStage',
    'rubric': 'Rubric', 'panel_rubric': 'Rubric', 'adviser_rubric': 'Rubric',
    'peer_rubric': 'Rubric', 'assigned_adviser_rubric': 'Rubric',
    'selected_rubric': 'Rubric', 'criterion': 'RubricCriterion',
    'external_evaluator': 'ExternalEvaluator',
    'submitted_external_evaluator': 'ExternalEvaluator',
    'guest_code': 'GuestPanelistCode', 'code': 'GuestPanelistCode',
    'grade': 'TeamGrade', 'team_grade': 'TeamGrade',
    'minutes': 'DefenseMinutes', 'retained_revision': 'DefenseMinutesRevision',
    'entry': 'ArchiveEntry', 'submission': 'DeliverableSubmission',
    'document': 'TeamDocument', 'primary_document': 'TeamDocument',
    'pit_event_config': 'PitEventGradingConfig', 'pit_event': 'PitEventGradingConfig',
    'correction': 'GradeCorrection', 'void_submission': 'PanelistGradeSubmission',
}
USER_REFERENCES = {
    'user', 'actor', 'student', 'member', 'enrolled_student', 'faculty',
    'leader', 'adviser', 'team_adviser', 'panelist', 'submitted_panelist',
    'chair_panelist', 'chair', 'documenter', 'instructor', 'project_manager',
    'assigned_by', 'requested_by', 'uploaded_by', 'created_by', 'reviewed_by',
    'adviser_signed_by', 'documenter_signed_by', 'chairman_signed_by',
    'original_requester',
}
LABEL_RELATIONS = {
    'Semester': ('school_year',),
    'DefenseSchedule': ('team', 'defense_stage'),
    'TeamGrade': ('team',), 'StudentStageGrade': ('student', 'team_grade__team'),
    'TeamMembership': ('student', 'team'), 'TeamStageProgress': ('team',),
    'RubricCriterion': ('rubric',), 'DeliverableSubmission': ('team',),
    'DefenseMinutesRevision': ('minutes',),
    'StageGradingConfig': ('defense_stage', 'semester__school_year'),
    'PitEventGradingConfig': ('semester__school_year',),
    'GradeCorrection': ('grade__team',),
    'PanelistGradeSubmission': ('panelist', 'student', 'team_grade__team'),
}


def _reference_base(key):
    return key[:-4] if key.endswith('_ids') else key[:-3] if key.endswith('_id') else key


def _record_label(record):
    kind = record.__class__.__name__
    if kind == 'User':
        return record.get_full_name().strip() or record.username
    if kind == 'Semester':
        return record.display_name
    if kind == 'DefenseSchedule':
        return (f'{record.team.name} / {record.stage_label} / '
                f'{record.scheduled_date:%b %d, %Y} {record.start_time:%I:%M %p}')
    if kind == 'TeamMembership':
        return f'{_record_label(record.student)} / {record.team.name}'
    if kind in ('TeamGrade', 'TeamStageProgress', 'DeliverableSubmission'):
        return ' / '.join(str(value) for value in (
            record.team.name, getattr(record, 'stage_label', ''), getattr(record, 'label', ''),
        ) if value)
    if kind == 'GuestPanelistCode':
        # An audit label must not disclose a live access code.
        return record.guest_name or 'Guest invitation'
    if kind == 'DefenseMinutesRevision':
        return f'{_record_label(record.minutes)} / retained signed version'
    if kind == 'DefenseMinutes':
        return f'{record.team_name} / {record.defense_stage_label} / minutes'
    if kind == 'RubricCriterion':
        return f'{record.name} / {record.rubric.name}'
    if kind in ('StageGradingConfig', 'PitEventGradingConfig'):
        stage = record.defense_stage.label if kind == 'StageGradingConfig' else record.event_name
        return f'{stage} / {record.semester.display_name} / grading settings'
    if kind == 'GradeCorrection':
        return f'{_record_label(record.grade)} / grade correction'
    if kind == 'PanelistGradeSubmission':
        evaluator = _record_label(record.panelist) if record.panelist else record.guest_name or 'Guest evaluator'
        return f'{evaluator} / {_record_label(record.team_grade)} / evaluation'
    for field in ('name', 'label', 'title', 'file_name', 'project_title', 'event_name'):
        value = getattr(record, field, None)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


class AuditReferenceResolver:
    """Fetch each referenced model once for an entire audit page or export."""

    def __init__(self, logs, *, target=None, target_id=None):
        self.models = {m.__name__.lower(): m for m in apps.get_models()}
        self.labels = {}
        wanted = defaultdict(set)
        for log in logs:
            model = self.model(log.target_type)
            saved = getattr(log, 'reference_labels', None) or {}
            if model and not saved.get('target'):
                self._collect_id(wanted, model, log.target_id)
            for side in ('old_values', 'new_values'):
                for path, key, value, parent in self.references(getattr(log, side), log):
                    ref_model = self.reference_model(key, log)
                    recorded = saved.get(side, {}).get(path, {})
                    for item in value if isinstance(value, list) else [value]:
                        if str(item) not in recorded and not self.companion_label(key, item, value, parent):
                            self._collect_id(wanted, ref_model, item)
        if target is not None:
            model = type(target)
            identity = target_id or getattr(target, 'pk', None)
            if identity:
                self.labels[(model, str(identity))] = _record_label(target)
                wanted[model].discard(self.valid_id(model, identity))
        for model, ids in wanted.items():
            if not ids:
                continue
            queryset = model.objects.filter(pk__in=ids)
            relations = LABEL_RELATIONS.get(model.__name__, ())
            if relations:
                queryset = queryset.select_related(*relations)
            for record in queryset:
                self.labels[(model, str(record.pk))] = _record_label(record)

    def model(self, name):
        return self.models.get((name or '').lower())

    def reference_model(self, key, log):
        base = _reference_base(key)
        if base == 'evaluator':
            name = 'ExternalEvaluator' if log.category == 'guest_access' or log.action.startswith('external_') else 'User'
            return self.model(name)
        if base in USER_REFERENCES:
            return self.model('User')
        if base in REFERENCE_MODELS:
            return self.model(REFERENCE_MODELS[base])
        # Follow real FK names for less common resources without guessing by ID.
        target_model = self.model(log.target_type)
        if target_model:
            for field in target_model._meta.fields:
                if field.is_relation and key in (field.name, field.attname):
                    return field.related_model
        return None

    @staticmethod
    def valid_id(model, value):
        if model is None or value is None or isinstance(value, (bool, float, dict, list)):
            return None
        try:
            result = model._meta.pk.to_python(value)
            if isinstance(result, int) and not 0 < result <= 2**63 - 1:
                return None
            return result
        except (ValueError, TypeError, ValidationError):
            return None

    def _collect_id(self, wanted, model, value):
        pk = self.valid_id(model, value)
        if pk is not None:
            wanted[model].add(pk)

    def references(self, values, log, prefix=''):
        if isinstance(values, dict):
            for key, value in values.items():
                path = f'{prefix}/{key}'
                model = self.reference_model(key, log)
                items = value if isinstance(value, list) else [value]
                if model and any(self.valid_id(model, item) is not None for item in items):
                    yield path, key, value, values
                elif isinstance(value, (dict, list)):
                    yield from self.references(value, log, path)
        elif isinstance(values, list):
            for index, value in enumerate(values):
                yield from self.references(value, log, f'{prefix}/{index}')

    @staticmethod
    def companion_label(key, item, value, parent):
        base = _reference_base(key)
        if base in ('schedule', 'defense_schedule') and not isinstance(value, list):
            # A reschedule is logged after saving. The old snapshot's date and
            # time describe the old schedule more accurately than a live lookup.
            team = parent.get('team_name')
            stage = parent.get('stage_label')
            day = parent.get('scheduled_date')
            start = parent.get('start_time')
            if all(isinstance(part, str) and part for part in (team, stage, day, start)):
                try:
                    day, start = parse_date(day), parse_time(start)
                except ValueError:
                    day = start = None
                if day and start:
                    return f'{team} / {stage} / {day:%b %d, %Y} {start:%I:%M %p}'
        candidates = [f'{base}_name', f'{base}_label', base]
        if base in ('stage', 'defense_stage'):
            candidates += ['stage_label', 'defense_stage_label']
        if base == 'chair_panelist':
            candidates += ['chair_name']
        if base == 'active_semester':
            candidates += ['active_semester']
        if isinstance(value, list):
            names = parent.get(f'{base}_names')
            if isinstance(names, list) and len(names) == len(value):
                label = names[value.index(item)]
                return label.strip() if isinstance(label, str) and label.strip() else None
            return None
        for candidate in candidates:
            label = parent.get(candidate)
            if candidate != key and isinstance(label, str) and label.strip() and not label.strip().isdigit():
                return label.strip()
        return None

    def capture(self, log):
        result = {'target': self.labels.get((self.model(log.target_type), str(log.target_id)))}
        for side in ('old_values', 'new_values'):
            result[side] = {}
            for path, key, value, parent in self.references(getattr(log, side), log):
                model = self.reference_model(key, log)
                result[side][path] = {
                    str(item): self.companion_label(key, item, value, parent) or self.labels.get((model, str(item)))
                    for item in (value if isinstance(value, list) else [value])
                    if self.valid_id(model, item) is not None
                }
        return result

    def display_values(self, log, side):
        values = getattr(log, side)
        saved = (getattr(log, 'reference_labels', None) or {}).get(side, {})
        replacements = {}
        for path, key, value, parent in self.references(values, log):
            model = self.reference_model(key, log)
            labels = saved.get(path, {})

            def render(item):
                if self.valid_id(model, item) is None:
                    return item
                identity = str(item)
                companion = self.companion_label(key, item, value, parent)
                label = labels.get(identity) if identity in labels else companion or self.labels.get((model, identity))
                if not label:
                    return f'Unavailable {model._meta.verbose_name} (ID: {identity})'
                current = '; current record' if identity not in labels and not companion else ''
                return f'{label} (ID: {identity}{current})'

            replacements[path] = [render(item) for item in value] if isinstance(value, list) else render(value)

        def transform(value, path=''):
            if path in replacements:
                return replacements[path]
            if isinstance(value, dict):
                return {key: transform(item, f'{path}/{key}') for key, item in value.items()}
            if isinstance(value, list):
                return [transform(item, f'{path}/{index}') for index, item in enumerate(value)]
            return value

        return transform(values)

    def target_label(self, log):
        saved = (getattr(log, 'reference_labels', None) or {}).get('target')
        # Prefer names already recorded in legacy snapshots to today's name.
        label = saved
        for values in (log.new_values, log.old_values):
            if label or not isinstance(values, dict):
                continue
            for key in ('name', 'full_name', 'title', 'file_name', 'guest_name', 'team_name', 'username', 'label'):
                candidate = values.get(key)
                if isinstance(candidate, str) and candidate.strip():
                    label = candidate.strip()
                    break
        current = False
        if not label:
            label = self.labels.get((self.model(log.target_type), str(log.target_id)))
            current = bool(label)
        identity = f'{log.target_type or "Resource"} #{log.target_id}' if log.target_id else log.target_type or 'System resource'
        return f'{label} ({identity}{"; current record" if current else ""})' if label else identity


def capture_audit_references(*, target, target_type, target_id, category, action, old_values, new_values):
    log = SimpleNamespace(target_type=target_type, target_id=target_id, category=category,
                          action=action, old_values=old_values, new_values=new_values)
    return AuditReferenceResolver([log], target=target, target_id=target_id).capture(log)
