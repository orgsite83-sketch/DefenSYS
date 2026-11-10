"""Deterministic import-name comparison; never modify account or uploaded names."""
import re
import unicodedata
from collections import defaultdict
from dataclasses import dataclass


IDENTITY_SUFFIX = re.compile(r'(?:^|[\s,])(?P<suffix>jr\.?|sr\.?|ii|iii|iv|v)$', re.I)


def comparison_text(value):
    return ' '.join(unicodedata.normalize('NFC', value or '').split()).casefold()


def is_initial(word):
    return len(word) == 1 and word.isalpha()


class PersonNames:
    def __init__(self, prefixes, suffixes):
        self.prefix = re.compile(r'^(?:' + '|'.join(prefixes) + r')\b[\s.]*', re.I)
        # Generational suffixes identify people; academic credentials do not.
        self.suffix = re.compile(r'(?:[\s,.]+)(?:' + '|'.join(suffixes) + r')\.?$', re.I)
        self.credential = re.compile(r'^(?:' + '|'.join(suffixes) + r')\.?$', re.I)

    def clean(self, value):
        text = unicodedata.normalize('NFC', value or '').strip()
        identity = ''

        def strip_titles(part):
            nonlocal identity
            previous = None
            while part and previous != part:
                previous = part
                match = IDENTITY_SUFFIX.search(part)
                if match:
                    identity = match['suffix'].rstrip('.').casefold()
                    part = part[:match.start()].strip()
                part = self.suffix.sub('', part).strip()
                part = self.prefix.sub('', part).strip()
            return part

        # Strip credentials around the whole name, then handle Last, First.
        text = strip_titles(text)
        parts = []
        for part in text.split(','):
            part = part.strip()
            if not part or self.credential.fullmatch(part):
                continue
            part = strip_titles(part)
            if part:
                parts.append(part)
        if len(parts) == 2:
            text = f'{parts[1]} {parts[0]}'
        else:
            text = ' '.join(parts)
        return f'{text} {identity}'.strip()

    def key(self, value):
        words = comparison_text(self.clean(value)).split()
        return ' '.join(w[:-1] if len(w) == 2 and w[0].isalpha() and w[1] == '.' else w
                        for w in words)


@dataclass(frozen=True)
class NameResolution:
    status: str
    user: object = None
    matches: tuple = ()
    kind: str = ''


class PersonNameIndex:
    """One projection/index per request; retain inactive accounts for ambiguity."""
    def __init__(self, users, names):
        self.users = list(users)
        self.names = names
        self.usernames = {u.username.casefold(): u for u in self.users}
        self.full_names = defaultdict(list)
        self.surnames = defaultdict(list)
        self.initials = defaultdict(list)
        self.middle_keys = defaultdict(list)
        self.results = {}
        for user in self.users:
            full = names.key(f'{user.first_name} {user.last_name}')
            last = names.key(user.last_name)
            first = names.key(user.first_name)
            self.full_names[full].append(user)
            self.surnames[last].append(user)
            if first:
                self.initials[(last, first[0])].append(user)
            if first and last:
                given = first.split()
                # Only standalone middle initials may be omitted for suggestions.
                base = ' '.join([given[0]] + [w for w in given[1:] if not is_initial(w)])
                self.middle_keys[(base, last)].append(user)

    @staticmethod
    def roles(role):
        return tuple(sorted(role)) if isinstance(role, (list, tuple, set)) else (role,) if role else ()

    def scoped(self, users, role):
        roles = self.roles(role)
        return tuple(u for u in users if not roles or u.role in roles)

    def full_matches(self, value, role=None):
        return self.scoped(self.full_names.get(self.names.key(value), ()), role)

    def resolve(self, value, role=None):
        raw = (value or '').strip()
        cache_key = (raw, self.roles(role))
        if cache_key in self.results:
            return self.results[cache_key]
        result = self._resolve(raw, role)
        self.results[cache_key] = result
        return result

    def _resolve(self, raw, role):
        if not raw:
            return NameResolution('empty')
        user = self.usernames.get(raw.casefold())
        if user and self.scoped([user], role):
            return NameResolution('matched', user, kind='id')
        matches = self.full_matches(raw, role)
        if matches:
            return self.result(matches, 'full_name')

        key = self.names.key(raw)
        words = key.split()
        # Last, J. is reordered by the same canonicalizer as complete names.
        if len(words) >= 2 and len(words[0]) == 1 and words[0].isalpha():
            matches = self.scoped(self.initials.get((' '.join(words[1:]), words[0]), ()), role)
            if matches:
                return self.result(matches, 'initial')
        if ',' not in raw and len(words) >= 2 and len(words[-1]) == 1 and words[-1].isalpha():
            matches = self.scoped(self.initials.get((' '.join(words[:-1]), words[-1]), ()), role)
            if matches:
                return self.result(matches, 'initial')
        matches = self.scoped(self.surnames.get(key, ()), role)
        if matches:
            return self.result(matches, 'surname')

        # Suggestions are a separate outcome, never an automatic identity match.
        # Enumerate token boundaries rather than guessing the last word is a surname.
        for boundary in range(1, len(words)):
            given, last = words[:boundary], ' '.join(words[boundary:])
            base = ' '.join([given[0]] + [w for w in given[1:] if not is_initial(w)])
            for candidate in self.scoped(self.middle_keys.get((base, last), ()), role):
                stored_given = self.names.key(candidate.first_name).split()
                uploaded_initials = [w for w in given[1:] if is_initial(w)]
                stored_initials = [w for w in stored_given[1:] if is_initial(w)]
                if bool(uploaded_initials) != bool(stored_initials):
                    return NameResolution('selection_required')
        return NameResolution('not_found')

    @staticmethod
    def result(matches, kind):
        return (NameResolution('matched', matches[0], kind=kind) if len(matches) == 1
                else NameResolution('ambiguous', matches=matches, kind=kind))
