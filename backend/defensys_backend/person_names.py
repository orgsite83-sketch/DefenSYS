"""Lossless official-name splitting shared by account import paths."""
import unicodedata
import re


def name_encoding_issue(value):
    text = str(value or '')
    return '\ufffd' in text or bool(re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', text))


def split_official_person_name(value):
    text = ' '.join(unicodedata.normalize('NFC', value or '').split())
    if not text:
        return '', ''
    if ',' in text:
        surname, given = text.split(',', 1)
        # Additional commas in the given-name portion are separators, not a
        # second surname-first name. Keep initials and generational suffixes.
        return ' '.join(given.replace(',', ' ').split()), surname.strip()
    first, _, rest = text.partition(' ')
    return first, rest
