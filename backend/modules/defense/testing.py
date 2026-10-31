"""Explicit test fixtures, independent of application database migrations."""

from django.core.management import call_command


def seed_stage_fixtures():
    """Opt a test's setup into sample stages; the command enforces test_* DBs."""
    call_command('seed_defense_stages', verbosity=0)
