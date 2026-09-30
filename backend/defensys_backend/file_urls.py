"""Resolve private uploaded files to the authenticated media proxy."""

from django.urls import reverse


def resolve_uploaded_file_url(request, file_field):
    """
    Return a client-fetchable URL for an uploaded file.

    Use the same authenticated proxy in development and production.
    """
    if not file_field:
        return ''

    if request is not None:
        return request.build_absolute_uri(
            reverse('media_file_serve', kwargs={'file_path': file_field.name})
        )
    return reverse('media_file_serve', kwargs={'file_path': file_field.name})
