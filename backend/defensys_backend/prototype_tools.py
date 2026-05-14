from django.conf import settings
from django.http import Http404


def require_prototype_tools():
    if not getattr(settings, 'ENABLE_PROTOTYPE_TOOLS', False):
        raise Http404()
