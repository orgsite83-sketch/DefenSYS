from repository.vault.models import VaultEntry

STATUS_OPTIONS = [
    {'value': '', 'label': 'All Statuses'},
    {'value': VaultEntry.STATUS_APPROVED, 'label': 'Approved'},
    {'value': VaultEntry.STATUS_NEEDS_REVISION, 'label': 'Needs Revision'},
    {'value': 'Pre-Defense', 'label': 'Pre-Defense'},
    {'value': 'Vault Submission', 'label': 'Vault Submission'},
    {'value': 'Missing required', 'label': 'Missing required'},
    {'value': 'Locked', 'label': 'Locked'},
]

TYPE_OPTIONS = [
    {'value': '', 'label': 'All Types'},
    {'value': VaultEntry.TYPE_CAPSTONE, 'label': 'Capstone'},
    {'value': VaultEntry.TYPE_PIT, 'label': 'PIT'},
]

SUBMISSION_KIND_OPTIONS = [
    {'value': '', 'label': 'All kinds'},
    {'value': 'pre', 'label': 'Pre-defense'},
    {'value': 'vault', 'label': 'Digital vault'},
    {'value': 'archive', 'label': 'Archive PDF'},
]

DEFAULT_AUDIT_PAGE_LIMIT = 100
MAX_AUDIT_PAGE_LIMIT = 500
