"""Inspect PIT test-import teams; delete only explicit, unused imported team IDs.

Preview is PostgreSQL read-only. Apply requires the db_guard opt-in, exact database
name, IDs, reason and a new recovery file under .tmp. Students are never deleted.
"""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def inspect(team):
    related = {}
    for relation in team._meta.related_objects:
        if relation.one_to_many or relation.one_to_one:
            count = relation.related_model._base_manager.filter(**{relation.field.attname: team.pk}).count()
            if count:
                related[relation.related_model._meta.label] = count
    return {'id': team.pk, 'name': team.name, 'semester_id': team.semester_id,
        'section': team.section, 'level': team.level, 'created_at': team.created_at.isoformat(),
        'event': team.current_defense_stage or '', 'concept_assignment': team.concept_assignment,
        'related': related}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', type=int, nargs='+')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--database-name')
    parser.add_argument('--backup-path')
    parser.add_argument('--reason')
    args = parser.parse_args()
    import django
    django.setup()
    from django.core import serializers
    from django.db import connection, transaction
    from defensys_backend.db_guard import assert_safe_for_orm_writes, current_database_name
    from student_teams.models import StudentTeam, TeamMembership, TeamAdviserAssignment
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    if args.apply:
        assert_safe_for_orm_writes()
        if args.database_name != current_database_name() or not args.ids or not args.backup_path or not args.reason:
            parser.error('Apply requires the exact database name, reviewed IDs, backup path and reason.')
    with transaction.atomic():
        if not args.apply:
            if connection.vendor != 'postgresql':
                parser.error('Preview requires PostgreSQL read-only enforcement.')
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
        query = StudentTeam.objects.filter(semester__is_active=True, level='3rd Year PIT').order_by('pk')
        if args.ids:
            query = query.filter(pk__in=args.ids)
        if args.apply:
            query = query.select_for_update()
        teams = list(query)
        rows = [inspect(t) for t in teams]
        if not args.apply:
            print(json.dumps({'database': current_database_name(), 'teams': rows}, indent=2))
            return
        if {t.pk for t in teams} != set(args.ids):
            parser.error('Some reviewed team IDs are missing or outside the active Third Year PIT scope.')
        allowed = {'student_teams.TeamMembership', 'student_teams.TeamAdviserAssignment'}
        for team, row in zip(teams, rows):
            if (team.current_defense_stage or team.project_version != 1 or
                    team.concept_assignment.get('mode') != 'assigned' or
                    not team.name.startswith('Team ') or set(row['related']) - allowed):
                parser.error(f'Team {team.pk} has workflow activity or is not an unused test-import candidate.')
        backup = Path(args.backup_path).resolve()
        if not backup.is_relative_to((ROOT / '.tmp').resolve()):
            parser.error('Recovery file must be inside .tmp.')
        backup.parent.mkdir(parents=True, exist_ok=True)
        objects = [*teams, *TeamMembership.objects.filter(team_id__in=args.ids),
                   *TeamAdviserAssignment.objects.filter(team_id__in=args.ids)]
        payload = {'reason': args.reason, 'review': rows,
                   'objects': json.loads(serializers.serialize('json', objects))}
        with backup.open('x', encoding='utf-8') as handle:
            json.dump(payload, handle, indent=2)
        for team, row in zip(teams, rows):
            team_id = team.pk
            team.delete()
            log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
                action='team.delete', target=team, target_type='StudentTeam', target_id=team_id,
                old_values=row, new_values={'deleted': True, 'test_import_cleanup': True},
                reason=args.reason, strict=True)
        print(json.dumps({'deleted_count': len(teams), 'team_ids': args.ids, 'backup': str(backup)}))


if __name__ == '__main__':
    main()
