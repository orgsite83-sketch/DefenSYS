"""Configuration-driven panel qualification, independent of academic role weights.

Only new hearings with a configured cutoff opt into this policy. Older hearings
keep their original assessment model; never invent per-concept historical grades.
"""
from decimal import Decimal

from django.core.exceptions import ValidationError
from defensys_backend.read_projection import read_memoize


def capture_policy(schedule):
    if schedule.scope != 'capstone' or not schedule.defense_stage_id:
        return {}
    from .services import weights_for_schedule
    stage = schedule.defense_stage
    rubric = schedule.rubric
    return {
        'version': 1 if stage.qualifying_score is not None else 0,
        'repeat_files_version': 1,
        'automatic_outcomes': bool(stage.qualifying_score is not None),
        'qualifying_score': str(stage.qualifying_score) if stage.qualifying_score is not None else None,
        'score_carryover': (stage.score_carryover if stage.qualifying_score is not None else
            stage.concept_config.get('score_carryover', 'reassess') if stage.concept_config.get('enabled') else 'retain'),
        'per_concept': bool(stage.qualifying_score is not None and stage.concept_config.get('enabled')),
        'rubric_id': rubric.pk if rubric else None,
        'target_type': rubric.target_type if rubric else 'team',
        'weights': weights_for_schedule(schedule),
        'criteria': [{'id': c.pk, 'name': c.name, 'max_score': str(c.max_score),
                      'weight': str(c.weight) if c.weight is not None else None,
                      'target_type': c.target_type} for c in rubric.criteria.all()] if rubric else [],
    }


def policy_for(schedule):
    return (schedule.assessment_policy or {}) if schedule else {}


def automatic_outcomes(schedule):
    return bool(policy_for(schedule).get('version') == 1 and policy_for(schedule).get('automatic_outcomes'))


@read_memoize(copy=True)
def hearing_concepts(schedule):
    if not policy_for(schedule).get('per_concept'):
        return []
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=schedule.pk).first()
    return hearing.concepts if hearing else []


def concept_keys(schedule):
    return [c['key'] for c in hearing_concepts(schedule)] if policy_for(schedule).get('per_concept') else ['']


def _mean(values):
    return sum(values, Decimal('0')) / len(values) if values else None


@read_memoize(copy=True)
def panel_assessments(grade):
    """Per-concept/team/member panel percentages, using immutable criterion scores.

    For Both, combine the team and member criteria within each evaluator before
    averaging evaluators and members. Never average differently weighted blocks.
    """
    schedule = grade.schedule
    policy = policy_for(schedule)
    target = policy.get('target_type') or (schedule.rubric.target_type if schedule.rubric_id else 'team')
    members = list(grade.team.memberships.values_list('student_id', flat=True))
    rows = list(grade.panelist_submissions.filter(schedule=schedule, is_void=False).prefetch_related('criterion_scores'))
    from .scoring import evaluation_percentage
    def panelist_percentage_from_criterion_scores(scores):
        return evaluation_percentage(((s.score, s.max_score_snapshot, s.weight_snapshot) for s in scores), rounded=False)
    result = {}
    for key in concept_keys(schedule):
        group = [s for s in rows if s.concept_key == key]
        identities = {(s.panelist_id, s.guest_code_id) for s in group}
        students = {}
        if target == 'team':
            values = [panelist_percentage_from_criterion_scores(s.criterion_scores.all())
                      for s in group if s.student_id is None]
            score = _mean([v for v in values if v is not None])
            students = {sid: score for sid in members}
        else:
            for sid in members:
                values = []
                for pid, gid in identities:
                    relevant = [s for s in group if (s.panelist_id, s.guest_code_id) == (pid, gid)
                                and (s.student_id == sid or (target == 'both' and s.student_id is None))]
                    pct = panelist_percentage_from_criterion_scores(
                        [c for s in relevant for c in s.criterion_scores.all()])
                    if pct is not None:
                        values.append(pct)
                students[sid] = _mean(values)
            score = _mean([v for v in students.values() if v is not None])
        result[key] = {'score': score, 'students': students}
    return result


@read_memoize
def selected_key(schedule):
    if not policy_for(schedule).get('per_concept'):
        return ''
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule_id=schedule.pk).first()
    return next((c['key'] for c in hearing.concepts if c.get('decision') in
                 ('approved', 'approved_with_revisions')), None) if hearing else None


def recompute_configured_panel(grade):
    """An unselected concept never contributes to the official academic grade."""
    from .models import StudentStageGrade
    from .peer_eval import recalculate_student_grade
    assessments = panel_assessments(grade)
    assessment = assessments.get(selected_key(grade.schedule), {})
    score = assessment.get('score')
    grade.panel_score = score.quantize(Decimal('.01')) if score is not None else None
    grade.save()
    for member in grade.team.memberships.all():
        student, _ = StudentStageGrade.objects.get_or_create(team_grade=grade, student_id=member.student_id)
        value = assessment.get('students', {}).get(member.student_id)
        student.panel_score = value.quantize(Decimal('.01')) if value is not None else None
        if grade.attempt_count <= 1 or student.adviser_score is None:
            student.adviser_score = grade.adviser_score
        student.save()
        recalculate_student_grade(student)
    return grade.panel_score


@read_memoize(copy=True)
def outcome_payload(grade):
    policy = policy_for(grade.schedule)
    if policy.get('version') != 1:
        return None
    from .corrections import evaluator_completion
    completion = evaluator_completion(grade)
    complete = bool(completion['required'] and completion['submitted'] == completion['required'])
    cutoff = Decimal(policy['qualifying_score'])
    assessments = panel_assessments(grade)
    concepts = {c['key']: c for c in hearing_concepts(grade.schedule)}
    results = [{'key': key, 'title': concepts.get(key, {}).get('title', ''),
                'score': float(value['score']) if value['score'] is not None else None,
                'qualifies': bool(complete and value['score'] is not None and value['score'] >= cutoff)}
               for key, value in assessments.items()]
    qualifies = any(r['qualifies'] for r in results)
    blocker = ''
    shared_redefense = False
    if policy.get('per_concept'):
        from repository.deliverables.models import ConceptRound
        hearing = ConceptRound.objects.filter(schedule_id=grade.schedule_id).select_related('section_round').first()
        if hearing and hearing.section_round_id:
            section = hearing.section_round
            if section.verdict == 'for_redefense':
                qualifies = False
                shared_redefense = True
                blocker = 'The shared system requires another hearing.'
            elif not section.selected_key:
                blocker = 'The section panel chair must select the shared system before recording the module outcome.'
            else:
                qualifies = any(r['qualifies'] for r in results if r['key'] == section.selected_key)
    available = complete and (not blocker or shared_redefense)
    from hashlib import sha256
    import json
    from defense.scheduler.panelist_evaluation import evaluation_context
    roster = [sorted((row.panelist_id, row.is_chair) for row in grade.schedule.panel_assignments.all()),
              sorted(str(row.pk) for row in grade.schedule.guest_invitations.all() if row.is_active),
              sorted(str(row.pk) for row in grade.schedule.guest_panelist_codes.all() if row.is_active)]
    review_token = sha256(json.dumps([grade.pk, grade.schedule_id, grade.project_version,
        str(grade.updated_at), evaluation_context(grade.schedule, grade), roster,
        complete, results, blocker], sort_keys=True).encode()).hexdigest()
    return {'qualifying_score': float(cutoff), 'per_concept': bool(policy.get('per_concept')),
            'automatic': automatic_outcomes(grade.schedule), 'review_token': review_token,
            'panel_complete': complete, 'assessments': results,
            'reason': blocker,
            'outcome': ('approved' if qualifies else 'for_redefense') if available else 'pending',
            'allowed_verdicts': (['approved', 'approved_with_revisions'] if qualifies else ['for_redefense']) if available else []}


def validate_outcome(grade, verdict, decisions=None):
    result = outcome_payload(grade)
    if result is None:
        return
    if not result['panel_complete']:
        raise ValidationError('Every required panel evaluation must be complete before recording the outcome.')
    if verdict not in result['allowed_verdicts']:
        raise ValidationError(result['reason'] or 'The defense outcome must follow the configured panel qualifying score.')
    if result['per_concept']:
        if not isinstance(decisions, list) or any(not isinstance(d, dict) for d in decisions):
            raise ValidationError('Record a decision for each assessed concept.')
        qualified = {r['key'] for r in result['assessments'] if r['qualifies']}
        selected = [d.get('key') for d in (decisions or []) if d.get('decision') in ('approved', 'approved_with_revisions')]
        if any(key not in qualified for key in selected):
            raise ValidationError('Select a concept whose panel assessment meets the qualifying score.')
