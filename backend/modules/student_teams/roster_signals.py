"""Pin event membership on its first durable activity, never on a GET."""
from django.db.models.signals import pre_save, post_save, pre_delete
from django.dispatch import receiver


@receiver(pre_save, sender='repository.ConceptRound')
@receiver(pre_save, sender='repository.DeliverableSubmission')
@receiver(pre_save, sender='defense.DefenseSchedule')
@receiver(pre_save, sender='grading.TeamGrade')
def pin_event_roster(sender, instance, raw=False, **kwargs):
    if raw or not getattr(instance, 'team_id', None):
        return
    if sender._meta.model_name == 'conceptround':
        if not any(c.get('title', '').strip() for c in (instance.concepts or [])):
            return
    elif not instance._state.adding:
        return
    team = instance.team
    if not team.is_pit:
        return
    from defense.scheduler.models import PitEventGradingConfig
    from .pit_rosters import pin
    event = getattr(instance, 'pit_event_config', None)
    if not event:
        label = getattr(instance, 'event_name', '') or getattr(instance, 'stage_label', '')
        event = PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
            year_level=team.year_level, event_name__iexact=label).first()
    if event:
        pin(team, event)


@receiver(post_save, sender='student_teams.StudentTeam')
def capture_capstone_intake(sender, instance, created=False, raw=False, **kwargs):
    if raw or not created or not instance.is_capstone:
        return
    from .capstone_lifecycle import capture_participation
    capture_participation(instance)


@receiver(pre_delete, sender='student_teams.StudentTeam')
def preserve_closed_capstone_terms(sender, instance, **kwargs):
    from django.db.models.deletion import ProtectedError
    closed = list(instance.term_participations.filter(closed_at__isnull=False))
    if closed:
        raise ProtectedError('Closed Capstone term records must be preserved.', closed)


@receiver(pre_save, sender='grading.TeamGrade')
@receiver(pre_save, sender='defense.DefenseSchedule')
def pin_capstone_requirements(sender, instance, raw=False, **kwargs):
    if raw or not instance._state.adding or not getattr(instance, 'team_id', None):
        return
    team = instance.team
    if not team.is_capstone:
        return
    from .models import TeamTermParticipation
    if instance.semester_id != team.semester_id:
        if TeamTermParticipation.objects.filter(team=team, semester_id=instance.semester_id, closed_at__isnull=False).exists():
            from django.core.exceptions import ValidationError
            raise ValidationError('A new assessment cannot be inserted into a closed term. Use the historical correction process.')
        return
    from .capstone_lifecycle import capture_participation
    capture_participation(team)
