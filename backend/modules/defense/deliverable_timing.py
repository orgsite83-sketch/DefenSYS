"""Shared configuration for Capstone and PIT submission deadlines."""


TIMING_SCHEDULING = 'scheduling'
TIMING_DEFENSE = 'defense'
TIMING_CHOICES = (
    (TIMING_SCHEDULING, 'Before endorsement / scheduling'),
    (TIMING_DEFENSE, 'Before scheduled defense'),
)


def validate_timing(data):
    """Validate nested checklist data before any configuration is written."""
    from rest_framework import serializers
    timing = serializers.ChoiceField(choices=TIMING_CHOICES).run_validation(
        data.get('requirement_timing', TIMING_SCHEDULING))
    hours = serializers.IntegerField(min_value=0, max_value=720).run_validation(
        data.get('deadline_hours_before', 24))
    if data.get('deliverable_type', 'pre') != 'pre' and timing == TIMING_DEFENSE:
        raise serializers.ValidationError('Only pre-defense deliverables can use a defense deadline.')
    # Retain validation for legacy payloads, but all new configuration follows
    # the same faculty-review gate. Old schedule deadlines live on the hearing.
    return {'requirement_timing': TIMING_SCHEDULING, 'deadline_hours_before': 24,
            'verdict_condition': 'all_pass'}
