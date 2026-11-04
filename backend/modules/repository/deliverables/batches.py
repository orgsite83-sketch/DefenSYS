"""Read-only batch boundaries over authorized Capstone teams."""
from rest_framework.exceptions import ValidationError
from defensys_backend.read_projection import read_memoize


@read_memoize
def batch_for(team):
    from student_teams.participation import intake_for
    return intake_for(team)


@read_memoize
def participation_status(team):
    from student_teams.participation import closed_failure
    from student_teams.capstone_lifecycle import project_outcome
    if closed_failure(team):
        return 'failed'
    closed = team.term_participations.filter(project_version=team.project_version,
        closed_at__isnull=False, outcome='completed').exists()
    if closed:
        return 'completed'
    outcome = project_outcome(team)[0]
    if outcome in ('completed', 'failed'):
        return outcome
    return 'ongoing'


def batch_options(teams):
    from student_teams.participation import term_key
    intakes = {}
    unknown = False
    for team in teams:
        intake = batch_for(team)
        if intake:
            intakes[intake.pk] = intake
        else:
            unknown = True
    options = [{'value': str(term.pk), 'label': term.display_name}
        for term in sorted(intakes.values(), key=term_key, reverse=True)]
    if unknown:
        options.append({'value': 'unassigned', 'label': 'Intake needs review'})
    return options


def filter_batches(request, queryset):
    batch = request.query_params.get('batch_id', '').strip()
    participation = request.query_params.get('participation', '').strip()
    if not batch and not participation:
        return queryset
    if participation not in ('', 'all', 'ongoing', 'completed', 'failed'):
        raise ValidationError({'participation': 'Choose ongoing, completed, failed, or all.'})
    if batch and batch != 'unassigned' and (not batch.isdecimal() or int(batch) < 1):
        raise ValidationError({'batch_id': 'Choose a valid Capstone intake.'})
    ids = []
    for team in queryset:
        # PIT has its own event/semester boundaries.
        if team.is_pit:
            ids.append(team.pk)
            continue
        intake = batch_for(team)
        if batch and (str(intake.pk) if intake else 'unassigned') != batch:
            continue
        if participation not in ('', 'all') and participation_status(team) != participation:
            continue
        ids.append(team.pk)
    return queryset.filter(pk__in=ids)
