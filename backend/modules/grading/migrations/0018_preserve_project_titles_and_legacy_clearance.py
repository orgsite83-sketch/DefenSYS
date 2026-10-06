from django.db import migrations
from django.db.models import OuterRef, Subquery, F


def preserve_existing_assessments(apps, schema_editor):
    team = apps.get_model('student_teams', 'StudentTeam')
    grade = apps.get_model('grading', 'TeamGrade')
    schedule = apps.get_model('defense', 'DefenseSchedule')
    history = apps.get_model('grading', 'GradeAttemptHistory')
    progress = apps.get_model('student_teams', 'TeamStageProgress')
    title = team.objects.filter(pk=OuterRef('team_id')).values('project_title')[:1]
    grade.objects.filter(project_title_snapshot='').update(project_title_snapshot=Subquery(title))
    schedule.objects.filter(project_title_snapshot='').update(project_title_snapshot=Subquery(title))
    history.objects.filter(project_title='').update(project_title=Subquery(
        grade.objects.filter(pk=OuterRef('team_grade_id')).values('project_title_snapshot')[:1]))
    # Preserve already-finalized historical approvals; new revision outcomes need explicit clearance.
    grade.objects.filter(status='published', verdict='approved_with_revisions').update(
        revisions_cleared_at=F('updated_at'), revisions_cleared_by_id=F('published_by_id'),
        clearance_remarks='Stage finalized before explicit revision clearance was introduced.')
    progress.objects.filter(grade__verdict='for_redefense').exclude(status='archived').update(status='for_redefense')
    progress.objects.filter(grade__verdict='approved_with_revisions', grade__revisions_cleared_at__isnull=True).exclude(status='archived').update(status='revisions_pending')
    progress.objects.filter(status='passed', grade__status='pending').exclude(grade__verdict__in=['for_redefense', 'approved_with_revisions']).update(status='grading')


class Migration(migrations.Migration):
    dependencies = [
        ('grading', '0017_remove_teamgrade_unique_capstone_grade_per_team_stage_and_more'),
        ('student_teams', '0009_teamrecoveryauthorization_and_more'),
        ('defense', '0030_defenseschedule_project_title_snapshot_and_more'),
        ('repository', '0014_remove_deliverablesubmission_unique_deliverable_submission_per_team_stage_and_more'),
    ]
    operations = [migrations.RunPython(preserve_existing_assessments, migrations.RunPython.noop)]
