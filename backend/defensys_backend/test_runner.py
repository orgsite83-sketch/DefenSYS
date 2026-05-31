"""Django test runner: app API tests only (excludes ad-hoc backend/tests/ scripts)."""

from django.conf import settings
from django.test.runner import DiscoverRunner


class AppOnlyDiscoverRunner(DiscoverRunner):
    """Run module tests under INSTALLED_APPS, not dev scripts in backend/tests/."""

    def setup_test_environment(self, **kwargs):
        super().setup_test_environment(**kwargs)
        # Disable throttling in the test environment
        if hasattr(settings, 'REST_FRAMEWORK'):
            rates = settings.REST_FRAMEWORK.get('DEFAULT_THROTTLE_RATES', {})
            for key in list(rates.keys()):
                rates[key] = None

    def build_suite(self, test_labels=None, **kwargs):
        if not test_labels:
            test_labels = [
                app
                for app in settings.INSTALLED_APPS
                if not app.startswith('django.')
            ]
        return super().build_suite(test_labels, **kwargs)
