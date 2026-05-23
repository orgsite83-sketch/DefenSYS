"""Resolve uploaded file URLs for API responses (local, presigned S3, or authenticated proxy)."""

from django.conf import settings
from django.urls import reverse


def resolve_uploaded_file_url(request, file_field):
    """
    Return a client-fetchable URL for an uploaded file.

    - S3: django-storages presigned URL via storage.url()
    - DEBUG + local disk: absolute /media/ URL
    - Production + local disk: authenticated API proxy
    """
    if not file_field:
        return ''

    storage = file_field.storage
    if getattr(settings, 'USE_S3', False):
        return storage.url(file_field.name)

    relative = storage.url(file_field.name)
    if settings.DEBUG:
        if request is not None:
            return request.build_absolute_uri(relative)
        return relative

    if request is not None:
        return request.build_absolute_uri(
            reverse('media_file_serve', kwargs={'file_path': file_field.name})
        )
    return reverse('media_file_serve', kwargs={'file_path': file_field.name})
