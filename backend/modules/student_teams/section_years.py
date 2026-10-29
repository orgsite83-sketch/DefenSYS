"""Validate recognized BSIT section years without changing PIT assignment rules."""
import re


BSIT_SECTION = re.compile(r'^BSIT\s*[- ]?\s*([1-4])\s*([A-Z]+)$', re.IGNORECASE)
YEAR_NUMBERS = {'1st Year': '1', '2nd Year': '2', '3rd Year': '3', '4th Year': '4'}


def capstone_section_issue(section, year_level):
    match = BSIT_SECTION.fullmatch((section or '').strip())
    expected = YEAR_NUMBERS.get(year_level)
    if match and expected and match[1] != expected:
        message = f'{year_level} Capstone must use a matching section, such as BSIT-{expected}{match[2].upper()}.'
        if year_level == '4th Year' and match[1] == '3':
            message += ' Third-year sections in first semester belong to PIT.'
        return message
    return ''


def enrollment_section_issue(section, year_level, semester):
    # The Capstone 2 exception must never change PIT section assignment policy.
    if semester and semester.label == '1st Semester' and year_level == '4th Year':
        return capstone_section_issue(section, year_level)
    return ''


def capstone_year_issue(year_level, semester):
    if semester and semester.label == '1st Semester' and year_level != '4th Year':
        return 'Capstone 2 teams must be fourth year. Third-year first-semester teams belong to PIT.'
    return ''
