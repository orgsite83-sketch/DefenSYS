"""Backfill evidenced intakes only. Old authorizations never create participations.

Uses historical migration models exclusively; no runtime policy imports or credentials writes.
"""
from django.db import migrations
from django.utils import timezone


def backfill(apps, schema_editor):
    Team = apps.get_model('student_teams', 'StudentTeam')
    Journey = apps.get_model('student_teams', 'HistoricalCapstoneJourney')
    Recovery = apps.get_model('student_teams', 'HistoricalCapstoneRecovery')
    Term = apps.get_model('academic_period_management', 'Semester')
    Recorded = apps.get_model('student_teams', 'TeamTermParticipation')
    Membership = apps.get_model('student_teams', 'TeamMembership')
    Participation = apps.get_model('student_teams', 'StudentCapstoneParticipation')
    Placement = apps.get_model('student_teams', 'StudentCapstonePlacement')
    Grade = apps.get_model('grading', 'TeamGrade')
    db = schema_editor.connection.alias
    now = timezone.now()
    terms = {t.pk: t for t in Term.objects.using(db).select_related('school_year')}
    journeys = {j.team_id: j for j in Journey.objects.using(db).all()}
    def key(term):
        return term.school_year.label, {'1st Semester': 1, '2nd Semester': 2, 'Summer': 3}[term.label]
    entries = []
    for team in Team.objects.using(db).filter(level__icontains='Capstone'):
        records = list(Recorded.objects.using(db).filter(team_id=team.pk).order_by('pk'))
        journey = journeys.get(team.pk)
        intake = terms.get(journey.intake_semester_id) if journey else None
        if not intake:
            candidates = [terms[r.semester_id] for r in records if not r.is_extended and terms[r.semester_id].label == '2nd Semester']
            if terms[team.semester_id].label == '2nd Semester' and team.capstone_phase != 'extended':
                candidates.append(terms[team.semester_id])
            intake = min(candidates, key=key) if candidates else None
        entries.append((team, records, intake))
    entries.sort(key=lambda entry: (key(entry[2] or terms[entry[0].semester_id]), key(terms[entry[0].semester_id]), entry[0].pk))
    for team, records, intake in entries:
        review = 'Retired Extended/replacement context requires an audited participation review.' if team.capstone_phase == 'extended' or team.project_version != 1 else ''
        if Recovery.objects.using(db).filter(team_id=team.pk, consumed_at__isnull=False).exists():
            review = 'Academic work under a consumed historical recovery grant requires an audited participation review.'
        if not intake:
            review = 'Original Capstone intake cannot be established from recorded history.'
        Team.objects.using(db).filter(pk=team.pk).update(intake_semester_id=intake.pk if intake else None,
            participation_review_reason=review)
        if not intake:
            continue
        latest = {}
        for grade in Grade.objects.using(db).filter(team_id=team.pk, scope='capstone', project_version=team.project_version).order_by('updated_at', 'pk'):
            substantive = bool(grade.status == 'published' or grade.verdict or grade.schedule_id
                or any(value is not None for value in (grade.panel_score, grade.adviser_score, grade.peer_score)))
            if substantive or grade.defense_stage_id not in latest:
                latest[grade.defense_stage_id] = grade
        failed = any(g.status == 'published' and (g.verdict in ('failed', 'project_rejected') or (g.outcome_metadata or {}).get('closure', {}).get('failed')) for g in latest.values())
        failed = failed or any(r.outcome == 'failed' and r.closed_at for r in records)
        state = 'needs_review' if review else 'failed' if failed else 'completed' if any(r.outcome == 'completed' and r.closed_at for r in records) else 'active'
        members = set(Membership.objects.using(db).filter(team_id=team.pk).values_list('student_id', flat=True)) | {team.leader_id}
        historical_members = set()
        for record in records:
            historical_members.update((record.snapshot or {}).get('member_ids', []))
        for student_id in sorted(members | historical_members):
            previous = Participation.objects.using(db).filter(student_id=student_id).order_by('-number').first()
            row, created = Participation.objects.using(db).get_or_create(student_id=student_id, intake_semester_id=intake.pk,
                defaults={'number': previous.number + 1 if previous else 1, 'previous_id': previous.pk if previous else None, 'state': state})
            existing = Placement.objects.using(db).filter(participation_id=row.pk, ended_at__isnull=True).first()
            if existing and existing.team_id != team.pk:
                Participation.objects.using(db).filter(pk=row.pk).update(state='needs_review')
                Placement.objects.using(db).filter(pk=existing.pk).update(ended_at=now)
            Placement.objects.using(db).get_or_create(participation_id=row.pk, team_id=team.pk,
                defaults={'ended_at': now if state != 'active' or student_id not in members or existing else None,
                    'snapshot': {'team_name': team.name, 'project_title': team.project_title, 'semester_id': team.semester_id,
                                 'migration': '0020_backfill_capstone_participation'}})


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0019_student_capstone_participation'), ('grading', '0025_automatic_outcome_metadata')]
    operations = [migrations.RunPython(backfill, migrations.RunPython.noop)]
