import re
from pathlib import Path

from django.utils import timezone

TYPE_PIT = 'pit'
TYPE_CAPSTONE = 'capstone'

YEAR_LEVEL_SLUGS = {
    '1st Year': '1st-Year',
    '2nd Year': '2nd-Year',
    '3rd Year': '3rd-Year',
    '4th Year': '4th-Year',
}


def slugify_year_level(year_level):
    label = (year_level or '').strip()
    if label in YEAR_LEVEL_SLUGS:
        return YEAR_LEVEL_SLUGS[label]
    cleaned = re.sub(r'[^A-Za-z0-9]+', '-', label).strip('-')
    return cleaned or 'unknown-year'


def slugify_academic_year(academic_year):
    label = (academic_year or '').strip()
    if not label:
        return 'unknown'
    cleaned = re.sub(r'[^A-Za-z0-9-]+', '-', label).strip('-')
    return cleaned or 'unknown'


def vault_entry_upload_to(instance, filename):
    entry_type = getattr(instance, 'entry_type', None) or TYPE_PIT
    if entry_type not in (TYPE_PIT, TYPE_CAPSTONE):
        entry_type = TYPE_PIT

    year_slug = slugify_year_level(getattr(instance, 'year_level', ''))
    academic = slugify_academic_year(getattr(instance, 'academic_year', ''))
    uploaded_at = getattr(instance, 'uploaded_at', None) or timezone.now()
    month = uploaded_at.strftime('%m')
    safe_name = Path(filename).name

    return f'vault_entries/{entry_type}/{year_slug}/{academic}/{month}/{safe_name}'
