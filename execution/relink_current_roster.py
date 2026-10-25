"""Review and relink exact, unused PIT roster copies to their original teams.

Preview is PostgreSQL read-only. Apply uses the normal signed roster service,
requires the db_guard opt-in and saves a recovery file. No teams, memberships,
users, files, grades or event records are deleted.
"""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def inspect_relink(term, year, section, event):
    from student_teams.models import StudentTeam
    from student_teams.pit_rosters import resolve
    current = resolve(term.pk, year).get(section, {})
    source = resolve(term.pk, year, event.pk).get(section, {})
    current_ids, source_ids = set(current.get('team_ids', [])), set(source.get('team_ids', []))
    def rows(ids):
        return [{'id': team.pk, 'name': team.name, 'leader_id': team.leader_id,
            'member_ids': sorted(team.memberships.values_list('student_id', flat=True))}
            for team in StudentTeam.objects.filter(pk__in=ids).order_by('pk')]
    current_rows, source_rows = rows(current_ids), rows(source_ids)
    signature = lambda row: (row['leader_id'], tuple(row['member_ids']))
    blockers = []
    if not source_rows or source.get('needs_selection') or current.get('needs_selection'):
        blockers.append('Both rosters must have an unambiguous source selection.')
    if current_ids != source_ids and current_rows and sorted(map(signature, current_rows)) != sorted(map(signature, source_rows)):
        blockers.append('The existing Current roster has different leaders or memberships.')
    retired = current_ids - source_ids
    for team in StudentTeam.objects.filter(pk__in=retired):
        if team.current_defense_stage or team.pit_event_rosters.exists() or team.roster_details.filter(event__isnull=False).exists():
            blockers.append(f'Team {team.pk} has an event assignment; retain and review it separately.')
        for relation in team._meta.related_objects:
            if not (relation.one_to_many or relation.one_to_one):
                continue
            if relation.related_model._meta.label in ('student_teams.TeamMembership', 'student_teams.PITRosterTeamDetails'):
                continue
            if relation.related_model._base_manager.filter(**{relation.field.attname: team.pk}).exists():
                blockers.append(f'Team {team.pk} has {relation.related_model._meta.label} activity.')
    return {'semester_id': term.pk, 'year_level': year, 'section': section,
        'event_id': event.pk, 'event_name': event.event_name, 'current': current_rows,
        'source': source_rows, 'retired_from_current_ids': sorted(retired), 'blockers': blockers}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--year', required=True)
    parser.add_argument('--section', required=True)
    parser.add_argument('--event-id', required=True, type=int)
    parser.add_argument('--actor-id', required=True, type=int)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--backup-path')
    args = parser.parse_args()
    import django
    django.setup()
    from django.contrib.auth import get_user_model
    from django.core import serializers
    from django.db import connection, transaction
    from rest_framework.request import Request
    from rest_framework.test import APIRequestFactory
    from defensys_backend.db_guard import assert_safe_for_orm_writes
    from defense.scheduler.models import PitEventGradingConfig
    from student_teams.term_scope import get_active_semester
    from student_teams.models import StudentTeam, PITSectionRoster, PITEventRoster, PITRosterTeamDetails
    from student_teams import roster_workspace as service
    if args.apply:
        assert_safe_for_orm_writes()
        if not args.backup_path:
            parser.error('Apply requires a new --backup-path inside .tmp.')
    with transaction.atomic():
        if not args.apply:
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
        term = get_active_semester()
        if not term:
            parser.error('No active semester.')
        actor = get_user_model().objects.get(pk=args.actor_id, is_active=True, role='faculty')
        service.require_roster_scope(actor, term, args.year, args.section, 'instructor')
        event = PitEventGradingConfig.objects.get(pk=args.event_id, semester=term, year_level=args.year)
        if args.apply:
            service.lock_cohort(term, args.year)
        review = inspect_relink(term, args.year, args.section, event)
        print(json.dumps(review, indent=2))
        if not args.apply:
            return
        if review['blockers']:
            parser.error('Relink refused: review the reported activity or grouping differences.')
        backup = Path(args.backup_path).resolve()
        if not backup.is_relative_to((ROOT / '.tmp').resolve()):
            parser.error('Recovery file must be inside .tmp.')
        ids = {row['id'] for row in review['current'] + review['source']}
        objects = [*StudentTeam.objects.filter(pk__in=ids),
            *PITSectionRoster.objects.filter(semester=term, year_level=args.year, section=args.section),
            *PITEventRoster.objects.filter(event__semester=term, event__year_level=args.year, section=args.section),
            *PITRosterTeamDetails.objects.filter(team_id__in=ids)]
        backup.parent.mkdir(parents=True, exist_ok=True)
        with backup.open('x', encoding='utf-8') as handle:
            json.dump({'review': review, 'objects': json.loads(serializers.serialize('json', objects))}, handle, indent=2)
        raw_request = APIRequestFactory().post('/api/teams/rosters/apply/')
        request = Request(raw_request)
        request._user = actor
        preview = service.prepare(actor, {'workspace': 'instructor', 'year_level': args.year,
            'section': args.section, 'operation': 'reuse', 'source_event_id': event.pk})
        result = service.apply(request, preview['preview_token'])
        print(json.dumps({'applied': result, 'recovery_file': str(backup)}, indent=2))


if __name__ == '__main__':
    main()
