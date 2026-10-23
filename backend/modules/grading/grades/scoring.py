"""Authoritative rubric scoring and immutable evaluation weight snapshots."""

from decimal import Decimal, InvalidOperation

from django.core.exceptions import ValidationError


def evaluation_percentage(rows, *, rounded=True):
    """Rows are (earned, maximum, weight). Null weights preserve pre-weighting records."""
    rows = list(rows)
    if not rows:
        return None
    if any(weight is None for _, _, weight in rows):
        maximum = sum((maximum for _, maximum, _ in rows), Decimal('0'))
        if maximum <= 0:
            return None
        value = sum((earned for earned, _, _ in rows), Decimal('0')) / maximum * 100
        return value.quantize(Decimal('0.01')) if rounded else value
    weight_total = sum((weight for _, _, weight in rows), Decimal('0'))
    if weight_total <= 0 or any(maximum <= 0 or weight <= 0 for _, maximum, weight in rows):
        raise ValidationError('The assigned rubric contains invalid criterion weights or maximum scores.')
    # Normalizing also supports old equal unit-weight rubrics and target-specific previews.
    total = sum((earned / maximum * weight for earned, maximum, weight in rows), Decimal('0'))
    value = total / weight_total * 100
    return value.quantize(Decimal('0.01')) if rounded else value


def rubric_score_rows(rubric, submitted, *, target_type=None, name_key='criterion_name'):
    """Resolve every score against the assigned rubric; ignore client maxima/weights/totals."""
    criteria = list(rubric.criteria.all())
    if target_type is not None:
        criteria = [criterion for criterion in criteria if criterion.target_type == target_type]
    if not criteria:
        raise ValidationError({'criteria_scores': 'No criteria are configured for this scoring target.'})
    if not isinstance(submitted, list) or not submitted:
        raise ValidationError({'criteria_scores': 'Score every criterion in the assigned rubric.'})
    by_id = {criterion.pk: criterion for criterion in criteria}
    by_name = {criterion.name: criterion for criterion in criteria}
    scores = {}
    for item in submitted:
        if not isinstance(item, dict):
            raise ValidationError({'criteria_scores': 'Each criterion score must be an object.'})
        criterion_id = item.get('criterion_id')
        name = item.get(name_key)
        if criterion_id is not None:
            try:
                criterion = by_id[int(criterion_id)]
            except (ValueError, TypeError, KeyError):
                raise ValidationError({'criteria_scores': 'Use only criteria from the assigned rubric.'})
            if name is not None and name != criterion.name:
                raise ValidationError({'criteria_scores': 'The criterion ID and name do not match.'})
        else:
            if not isinstance(name, str):
                raise ValidationError({'criteria_scores': 'A criterion ID or name is required.'})
            criterion = by_name.get(name)
            if criterion is None:
                raise ValidationError({'criteria_scores': 'Use only criteria from the assigned rubric.'})
        if criterion.pk in scores:
            raise ValidationError({'criteria_scores': 'Duplicate rubric criteria are not allowed.'})
        try:
            score = Decimal(str(item.get('score')))
        except (InvalidOperation, ValueError, TypeError):
            raise ValidationError({'score': 'Score must be numeric.'})
        maximum = Decimal(criterion.max_score)
        if not score.is_finite() or score < 0 or score > maximum:
            raise ValidationError({'score': f'Score must be between 0 and {maximum}.'})
        scores[criterion.pk] = score.quantize(Decimal('0.01'))
    if set(scores) != set(by_id):
        raise ValidationError({'criteria_scores': 'Submitted criteria must exactly match the assigned rubric.'})
    rows = [
        {'criterion': criterion, 'score': scores[criterion.pk],
         'max_score': Decimal(criterion.max_score), 'weight': criterion.weight}
        for criterion in criteria
    ]
    evaluation_percentage((row['score'], row['max_score'], row['weight']) for row in rows)
    return rows


def rubric_rows_percentage(rows):
    return evaluation_percentage((row['score'], row['max_score'], row['weight']) for row in rows)


def panelist_overall_percentage(rows, *, maximum_attr):
    """Average each student's team + individual assessment without duplicating team weights."""
    rows = list(rows)
    if not rows:
        return None
    student_id = lambda row: row.student_id if maximum_attr == 'max_score' else row.submission.student_id
    percentage = lambda selected: evaluation_percentage(
        (row.score, getattr(row, maximum_attr), row.weight_snapshot) for row in selected
    )
    if any(row.weight_snapshot is None for row in rows):
        return percentage(rows)
    students = {student_id(row) for row in rows if student_id(row) is not None}
    if not students:
        return percentage(rows)
    shared = [row for row in rows if student_id(row) is None]
    values = [percentage(shared + [row for row in rows if student_id(row) == student]) for student in students]
    return (sum(values, Decimal('0')) / len(values)).quantize(Decimal('0.01'))
