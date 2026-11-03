"""Student progress includes decisions, never confidential assessment values."""


def student_assessment_payload(value, actor):
    """Return a detached public projection without altering saved snapshots.

    Apply only to assessment/concept payloads, not peer-evaluation input forms.
    Faculty and administrative grading retain their full existing payloads.
    """
    if getattr(actor, 'role', None) != 'student':
        return value

    private = {
        'score', 'scores', 'final_grade', 'student_scores', 'student_grades', 'peerScore',
        'students', 'peer_per_student', 'breakdowns', 'criterion_scores',
        'qualifies', 'ranking', 'rank', 'assessments', 'outcome_rule', 'peer_rating_evidence',
    }

    def public(item):
        if isinstance(item, dict):
            return {key: public(child) for key, child in item.items()
                    if key not in private and not key.endswith(('_score', '_scores', '_grade'))}
        if isinstance(item, (list, tuple)):
            return [public(child) for child in item]
        return item

    return public(value)
