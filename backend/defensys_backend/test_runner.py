"""Django test runner: app API tests only (excludes ad-hoc backend/tests/ scripts)."""

from django.conf import settings
from django.test.runner import DiscoverRunner


class AppOnlyDiscoverRunner(DiscoverRunner):
    """Run module tests under INSTALLED_APPS, not dev scripts in backend/tests/."""

    def build_suite(self, test_labels=None, **kwargs):
        if not test_labels:
            test_labels = [
                app
                for app in settings.INSTALLED_APPS
                if not app.startswith('django.')
            ]
        return super().build_suite(test_labels, **kwargs)
