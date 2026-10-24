"""Reuse pure projections during one GET, never across requests or writes.

Only explicitly decorated domain reads participate. Permission querysets and
write handlers retain their normal behavior. SQL writes and rollbacks discard
all projections before execution, including writes made by GET legacy helpers.
"""
from contextlib import contextmanager
from contextvars import ContextVar
from copy import deepcopy
from functools import wraps
from inspect import signature

from django.conf import settings
from django.db import connection
from django.db.models import Model
from rest_framework.views import APIView

_current = ContextVar('defensys_read_projection', default=None)


def _key(value):
    if isinstance(value, Model):
        if value.pk is None:
            raise TypeError('Unsaved models are not projection keys')
        # Include loaded scalar fields so an unsaved in-memory edit cannot use
        # an earlier projection. Reading deferred fields here would issue SQL.
        fields = tuple((field.attname, _key(value.__dict__[field.attname]))
                       for field in value._meta.concrete_fields if field.attname in value.__dict__)
        return (value._meta.label_lower, value._state.db, value.pk, fields,
                _key(value.__dict__.get('_projection_context')),
                value.__dict__.get('_assessment_semester_id'))
    if isinstance(value, dict):
        return tuple(sorted((key, _key(item)) for key, item in value.items()))
    if isinstance(value, (list, tuple)):
        return tuple(_key(item) for item in value)
    if isinstance(value, (set, frozenset)):
        return frozenset(_key(item) for item in value)
    hash(value)
    return value


@contextmanager
def read_projection():
    if _current.get() is not None or not getattr(settings, 'READ_PROJECTION_CACHE_ENABLED', True):
        yield
        return
    cache = {}
    token = _current.set(cache)

    def invalidate_on_write(execute, sql, params, many, context):
        command = sql.lstrip().split(None, 1)[0].upper() if sql.strip() else ''
        if command in {'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'ALTER', 'DROP',
                       'CREATE', 'TRUNCATE', 'ROLLBACK', 'WITH'}:
            cache.clear()
        return execute(sql, params, many, context)

    try:
        with connection.execute_wrapper(invalidate_on_write):
            yield
    finally:
        _current.reset(token)


def read_memoize(function=None, *, copy=False, bypass_if=()):
    """Memoize an explicit domain read only inside a read_projection scope.

    Copy mutable payloads; model/config lookups retain their prefetched graph.
    Locking variants always execute so write-side row locks cannot be skipped.
    """
    def decorate(fn):
        parameters = signature(fn)

        @wraps(fn)
        def wrapped(*args, **kwargs):
            cache = _current.get()
            if cache is None:
                return fn(*args, **kwargs)
            bound = parameters.bind(*args, **kwargs)
            bound.apply_defaults()
            if any(bound.arguments.get(name) for name in bypass_if):
                return fn(*args, **kwargs)
            try:
                key = (fn, _key(bound.arguments))
            except TypeError:
                return fn(*args, **kwargs)
            if key in cache:
                return deepcopy(cache[key]) if copy else cache[key]
            result = fn(*args, **kwargs)
            cache[key] = deepcopy(result) if copy else result
            return result
        return wrapped
    return decorate(function) if function else decorate


class ReadAPIView(APIView):
    def dispatch(self, request, *args, **kwargs):
        if request.method == 'GET':
            with read_projection():
                return super().dispatch(request, *args, **kwargs)
        return super().dispatch(request, *args, **kwargs)
