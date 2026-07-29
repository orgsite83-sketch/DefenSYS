from repository.archive.models import ArchiveEntry

STATUS_OPTIONS = [
    {'value': '', 'label': 'All Statuses'},
    {'value': ArchiveEntry.STATUS_APPROVED, 'label': 'Approved'},
    {'value': ArchiveEntry.STATUS_NEEDS_REVISION, 'label': 'Needs Revision'},
    {'value': 'Pre-Defense', 'label': 'Pre-Defense'},
    {'value': 'Post-Defense', 'label': 'Post-Defense'},
    {'value': 'Missing required', 'label': 'Missing required'},
    {'value': 'Locked', 'label': 'Locked'},
]

TYPE_OPTIONS = [
    {'value': '', 'label': 'All Types'},
    {'value': ArchiveEntry.TYPE_CAPSTONE, 'label': 'Capstone'},
    {'value': ArchiveEntry.TYPE_PIT, 'label': 'PIT'},
]

SUBMISSION_KIND_OPTIONS = [
    {'value': '', 'label': 'All kinds'},
    {'value': 'pre', 'label': 'Pre-defense'},
    {'value': 'post', 'label': 'Repository'},
]

DEFAULT_AUDIT_PAGE_LIMIT = 100
MAX_AUDIT_PAGE_LIMIT = 500
