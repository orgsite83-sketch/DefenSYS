"""Delete retired repository files only after their database changes commit."""
import logging
from uuid import uuid4
from pathlib import Path

from django.db import transaction

logger = logging.getLogger(__name__)


def replacement_file_name(name):
    # Unique keys also protect installations whose storage overwrites existing keys.
    return f'{uuid4().hex}_{Path(name).name}'


def delete_repository_file_on_commit(field_file):
    if not field_file:
        return
    storage, name = field_file.storage, field_file.name

    def cleanup():
        from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
        from repository.archive.models import ArchiveEntry

        # Legacy parents and child rows can point to the same physical object.
        if any(model.objects.filter(file=name).exists() for model in (
            DeliverableSubmission, DeliverableSubmissionFile, ArchiveEntry,
        )):
            return
        try:
            storage.delete(name)
        except Exception:
            logger.exception('Could not remove retired repository file %s', name)

    transaction.on_commit(cleanup, robust=True)
