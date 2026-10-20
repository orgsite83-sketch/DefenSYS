"""One post-defense gate and version-bound final evidence for concept hearings."""
from defense.document_policy import is_approved_concept
from defensys_backend.read_projection import read_memoize


@read_memoize(copy=True)
def post_defense_state(team, stage):
    from . import concepts
    if not concepts.enabled(stage):
        return None
    current = concepts.latest_round(team, stage)
    if not current or not current.schedule_id:
        return {'unlocked': False, 'reason': 'Complete the current concept hearing before submitting final papers.'}
    if current.section_round_id:
        return shared_post_defense_state(current.section_round, stage)
    else:
        reason = assessment_blocker(current)
        if reason:
            return {'unlocked': False, 'reason': reason}
    return {'unlocked': True, 'reason': ''}


@read_memoize(copy=True)
def shared_post_defense_state(shared, stage):
    from . import concepts
    from repository.section_concepts.services import active_links
    if not shared.selected_key or shared.verdict not in ('approved', 'approved_with_revisions'):
        return {'unlocked': False, 'reason': 'The chair must select the shared section system.'}
    participants = [(link.team, concepts.latest_round(link.team, stage)) for link in active_links(shared.project)]
    if not participants:
        return {'unlocked': False, 'reason': 'The section hearing has no current participating teams.'}
    for participant, hearing in participants:
        if not hearing or hearing.section_round_id != shared.pk:
            return {'unlocked': False, 'reason': f'{participant.name}: complete the current module hearing.'}
        reason = assessment_blocker(hearing, selected_key=shared.selected_key)
        if reason:
            return {'unlocked': False, 'reason': f'{participant.name}: {reason}'}
    return {'unlocked': True, 'reason': ''}


def assessment_blocker(current, *, selected_key=None):
    if not current.schedule_id or current.schedule.status in ('cancelled', 'archived'):
        return 'Complete the current defense attempt before final-paper submission.'
    if current.verdict not in ('approved', 'approved_with_revisions'):
        return 'The chair must record an approval or revision outcome for the current module/concept.'
    selected = [c for c in current.concepts if c.get('decision') in ('approved', 'approved_with_revisions')]
    if len(selected) != 1 or (selected_key and selected[0]['key'] != selected_key):
        return 'The module outcome must match the selected section system.'
    grade = current.schedule.grade_records.first()
    if not grade or grade.project_version != current.project_version:
        return 'The current defense assessment is unavailable.'
    from grading.grades.services import team_grading_readiness
    if not team_grading_readiness(grade, grade.semester, grade.scope)['panel_complete']:
        return 'Every assigned panel evaluation must be submitted.'
    return ''


def final_paper_complete(team, stage, *, required=False):
    """Only the selected hearing's approved final file can satisfy this purpose."""
    from . import concepts
    from .services import get_deliverable_definitions_for_team, submissions_for
    from .documents import current_files
    definitions = [d for d in get_deliverable_definitions_for_team(team, stage.label) if is_approved_concept(d)]
    if not definitions:
        return not required  # Historical, locked definitions are not silently rewritten.
    current = concepts.latest_round(team, stage)
    if not current or not current.schedule_id:
        return False
    selected = next((c['key'] for c in current.concepts if c.get('decision') in ('approved', 'approved_with_revisions')), '')
    submissions = submissions_for(team, stage.label)
    return bool(selected) and all(any(
        f.file and f.status == 'accepted' and f.concept_round_id == current.pk and f.selected_concept_key == selected
        for f in current_files(submissions.get(d['id']))) for d in definitions)


def shared_final_complete(round):
    return bool(round.selected_key and round.systems.filter(key=round.selected_key,
        papers__purpose='final', papers__is_current=True, papers__status='accepted').exists())
