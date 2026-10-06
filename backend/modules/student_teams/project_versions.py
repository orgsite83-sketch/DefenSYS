from django.db import models
from django.db.models import F


class CurrentProjectManager(models.Manager):
    """Keep operational queries on the team's current project; retain old records."""

    def get_queryset(self):
        return super().get_queryset().filter(project_version=F('team__project_version'))
