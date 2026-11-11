"""Assignment-backed duties shared by admin and faculty accounts."""

PIT_YEARS = ('1st Year', '2nd Year', '3rd Year')


def is_institutional_staff(user):
    return bool(user and user.is_authenticated and user.role in ('faculty', 'admin'))


def is_adviser(user, team=None):
    return bool(is_institutional_staff(user) and user.is_adviser
                and getattr(user, '_workspace', '') in ('', 'adviser')
                and (team is None or (team.is_capstone and team.adviser_id == user.pk)))


def is_pit_lead(user):
    return bool(is_institutional_staff(user) and user.is_pit_lead
                and getattr(user, '_workspace', '') in ('', 'pit_lead')
                and user.pit_lead_year in PIT_YEARS)


def pit_teams_for(user, teams):
    if not is_pit_lead(user):
        return teams.none()
    return teams.filter(level__icontains='PIT', year_level=user.pit_lead_year).exclude(
        year_level='3rd Year', semester__label='2nd Semester')
