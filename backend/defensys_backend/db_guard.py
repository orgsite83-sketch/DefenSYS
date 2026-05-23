"""
Guard ad-hoc scripts so ORM writes target the isolated test database, not defensys_db.

Use bootstrap_test_db_script() at the top of backend/tests/*.py helpers that mutate data.
For regression checks, prefer: python manage.py test <app>.tests
"""

from __future__ import annotations

import os

from django.conf import settings
from django.db import connections


ALLOW_DEV_DB_ENV = 'DEFENSYS_ALLOW_DEV_DB'


def is_test_database(name: str | None) -> bool:
    return bool(name and name.startswith('test_'))


def current_database_name() -> str:
    return connections['default'].settings_dict['NAME']


def dev_database_name() -> str:
    return os.environ.get('POSTGRES_DB', 'defensys_db')


def test_database_name() -> str:
    test_cfg = settings.DATABASES['default'].get('TEST') or {}
    configured = test_cfg.get('NAME')
    if configured:
        return configured
    return f'test_{dev_database_name()}'


def allow_dev_database_writes() -> bool:
    return os.environ.get(ALLOW_DEV_DB_ENV, '').strip().lower() in (
        '1',
        'true',
        'yes',
        'on',
    )


def assert_safe_for_orm_writes() -> None:
    """Raise if the active connection is not a test_* database."""
    name = current_database_name()
    if is_test_database(name) or allow_dev_database_writes():
        return
    raise RuntimeError(
        f'Refusing ORM writes on dev database "{name}". '
        'Use "python manage.py test ..." or call bootstrap_test_db_script() first. '
        f'To intentionally use dev DB: set {ALLOW_DEV_DB_ENV}=1.'
    )


def warn_if_not_test_database(action: str = 'read') -> None:
    name = current_database_name()
    if is_test_database(name) or allow_dev_database_writes():
        return
    print(
        f'WARNING: {action} on dev database "{name}". '
        f'Prefer bootstrap_test_db_script() or manage.py test.'
    )


def enforce_test_database(verbosity: int = 0, *, keepdb: bool = True) -> str:
    """
    Point the default connection at the test database and ensure it exists.

    Must be called after django.setup().
    Returns the test database name in use.
    """
    test_name = test_database_name()
    default_cfg = settings.DATABASES['default']
    default_cfg['NAME'] = test_name
    connections.databases['default']['NAME'] = test_name

    connection = connections['default']
    connection.close()

    connection.creation.create_test_db(
        verbosity=verbosity,
        autoclobber=False,
        keepdb=keepdb,
        serialize=False,
    )
    connection.close()

    print(f'db_guard: using test database "{test_name}" (keepdb={keepdb})')
    return test_name


def bootstrap_test_db_script(
    *,
    settings_module: str = 'defensys_backend.settings',
    verbosity: int = 0,
    keepdb: bool = True,
) -> str:
    """
    django.setup() + enforce test DB + assert writes are allowed.

    Call once at module import or main() before any ORM access.
    """
    import django

    os.environ.setdefault('DJANGO_SETTINGS_MODULE', settings_module)
    if not settings.configured:
        django.setup()

    test_name = enforce_test_database(verbosity=verbosity, keepdb=keepdb)
    assert_safe_for_orm_writes()
    return test_name
