"""Read-only current formation gaps, using the same roster and placement rules."""
from collections import Counter

from academic_period_management.capstone_mode import capstone_operating_mode
from . import formation
from .participation import roster_issues
from .team_levels import is_pit_scope


def assignment_students(semester, *, scope='capstone', year=None):
    if semester is None:
        return [], 'unavailable'
    if scope == 'capstone':
        if not capstone_operating_mode(semester)['can_create_capstone_teams']:
            return [], 'not_applicable'
        # Admin forms Capstone teams by importing the official roster. This is
        # its canonical unassigned pool, not the instructor-only generator.
        rows = [s for s in formation.roster(semester, '3rd Year Capstone', '3rd Year', None,
                                           generation=False) if s['eligible']]
        blocked = roster_issues([s['id'] for s in rows], semester) if rows else {}
        rows = [s for s in rows if s['id'] not in blocked]
    else:
        if not year or not is_pit_scope(year, semester):
            return [], 'not_applicable'
        rows = [s for s in formation.roster(semester, f'{year} PIT', year, None,
                                           generation=False) if s['eligible']]
    return [s for s in rows if not year or s['year_level'] == year], 'available'


def assignment_summary(semester, enrollment):
    students, state = assignment_students(semester)
    counts = Counter(s['year_level'] for s in students)
    years = []
    for row in enrollment.get('by_year', []):
        year = row['year_level']
        if is_pit_scope(year, semester):
            pit, pit_state = assignment_students(semester, scope='pit', year=year) if row['enrolled'] else ([], 'available')
            years.append({**row, 'team_scope': 'pit', 'without_team': len(pit),
                          'team_state': pit_state, 'can_assign': False})
        else:
            years.append({**row, 'team_scope': 'capstone',
                          'without_team': counts[year] if state == 'available' else None,
                          'team_state': state, 'can_assign': state == 'available' and counts[year] > 0})
    return years
