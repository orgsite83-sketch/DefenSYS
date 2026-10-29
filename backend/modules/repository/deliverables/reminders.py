"""Read-only requirement state for reminders sent from the deliverables matrix."""

from .concepts import stage_for
from .documents import completeness
from .services import get_deliverable_definitions_for_team, submissions_for


def requirement_reminder_state(team, stage_label, deliverable_id):
    definition = next((item for item in get_deliverable_definitions_for_team(team, stage_label)
                       if item['id'] == deliverable_id and item['type'] in ('pre', 'post')), None)
    if definition is None:
        return None
    submission = submissions_for(team, stage_label).get(deliverable_id)
    complete = completeness(submission, definition, stage=stage_for(team, stage_label))
    return {
        'label': definition['label'],
        'complete': complete and submission is not None and submission.status != 'rejected',
    }
