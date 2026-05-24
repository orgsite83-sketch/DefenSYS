import logging

from rest_framework.views import exception_handler

logger = logging.getLogger('defensys.authz')


def defensys_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is not None and response.status_code == 403:
        request = context.get('request')
        view = context.get('view')
        user = getattr(request, 'user', None) if request else None
        user_id = user.id if user and user.is_authenticated else None
        logger.warning(
            'Authorization denied user_id=%s method=%s path=%s view=%s',
            user_id,
            getattr(request, 'method', ''),
            getattr(request, 'path', ''),
            view.__class__.__name__ if view else '',
        )
    return response
