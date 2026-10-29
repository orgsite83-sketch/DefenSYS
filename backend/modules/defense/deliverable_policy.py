"""Faculty review defaults and completed hearing exemptions."""
from copy import deepcopy


def faculty_review_definition(definition):
    """Old clients may send retired options; they cannot restore exemptions."""
    return {**definition, 'requirement_timing': 'scheduling',
            'deadline_hours_before': 24, 'verdict_condition': 'all_pass'}


def apply_hearing_policy(definitions, schedule, *, grade=None):
    """Keep completed exemptions attached to their exact hearing.

    Only the data migration populates this snapshot. New schedules always use
    faculty-reviewed requirements; changing a live checklist never rewrites a
    completed hearing's evidence.
    """
    snapshot = getattr(schedule, 'legacy_deliverable_policy', None) or {}
    waived = set()
    if grade and grade.status == 'published' and grade.verdict == 'approved':
        if schedule and grade.schedule_id == schedule.pk:
            waived.update(snapshot.get('waived_ids', []))
        completed = grade.legacy_deliverable_policy or {}
        if completed.get('attempt') == grade.attempt_count:
            waived.update(completed.get('waived_ids', []))
    result = []
    for definition in definitions:
        item = deepcopy(definition)
        if item['id'] in waived:
            item['historical_waiver'] = True
        result.append(item)
    return result
