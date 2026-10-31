from django.apps import AppConfig


class DefenseConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'defense'
    label = 'defense'
    verbose_name = 'Defense'

    def ready(self):
        from . import template_files  # noqa: F401 - register attachment cleanup
