"""Pin event membership on its first durable activity, never on a GET."""
from django.db.models.signals import pre_save
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
