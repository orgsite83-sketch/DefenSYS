"""Deterministic import-name comparison; never modify account or uploaded names."""
import re
import unicodedata
from collections import defaultdict
from dataclasses import dataclass


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

    def _components(self, value, *, surname_first=True, surname=False):
        text = unicodedata.normalize('NFC', value or '').strip()
        parts, identities = [], []
        for index, part in enumerate(text.split(',')):
            part = part.strip()
            previous = None
            while part and previous != part:
                previous = part
                part = self.suffix.sub('', part).strip()
                part = self.prefix.sub('', part).strip()
            if not part or self.credential.fullmatch(part):
                continue
            words = part.split()
            kept = []
            for position, word in enumerate(words):
                token = comparison_text(word).rstrip('.')
                roman = token in ('ii', 'iii', 'iv', 'v') and position == len(words) - 1
                # A single V may be a middle initial; a surname field or a
                # complete name supplies the boundary needed to treat it as V.
                roman = roman and (token != 'v' or surname or len(words) >= 3
                                   or surname_first and ',' in text and index == 0)
                if token in ('jr', 'sr') or roman:
                    identities.append(token)
                else:
                    kept.append(word)
            if kept:
                parts.append(' '.join(kept))
        if surname_first and len(parts) > 1:
            parts = parts[1:] + parts[:1]
        words = comparison_text(' '.join(parts)).split()
        words = tuple(w[:-1] if len(w) == 2 and w[0].isalpha() and w[1] == '.' else w
                      for w in words)
        return words, tuple(dict.fromkeys(identities))

    def clean(self, value):
        words, suffix = self._components(value)
        return ' '.join((*words, *suffix))

    def key(self, value):
        return self.clean(value)

    def account_parts(self, first_name, last_name):
        # Stored first/last fields already identify the surname boundary. Never
        # interpret an old embedded comma in first_name as Last, First again.
        given, first_suffix = self._components(first_name, surname_first=False)
        last, last_suffix = self._components(last_name, surname_first=False, surname=True)
        suffix = tuple(dict.fromkeys((*first_suffix, *last_suffix)))
        return given, last, suffix


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
            given, family, suffix = names.account_parts(user.first_name, user.last_name)
            full = ' '.join((*given, *family, *suffix))
            last = ' '.join((*family, *suffix))
            first = ' '.join(given)
            self.full_names[full].append(user)
            self.surnames[last].append(user)
            if first:
                self.initials[(last, first[0])].append(user)
            if first and last:
                base = ' '.join([given[0]] + [w for w in given[1:] if not is_initial(w)])
                self.middle_keys[(base, ' '.join(family), suffix)].append(user)

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
            # A reference with no middle initials also cannot distinguish a
            # blank-initial account from another account in the same name group.
            if len(matches) == 1:
                given, family, suffix = self.names.account_parts(matches[0].first_name, matches[0].last_name)
                if given and not any(is_initial(w) for w in given[1:]):
                    group = self.scoped(self.middle_keys.get((' '.join(given), ' '.join(family), suffix), ()), role)
                    if len(group) > 1:
                        return NameResolution('ambiguous', matches=group, kind='omitted_initial')
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

        # Omitted initials are compatible only when the entire given-name and
        # surname group contains one identity, including inactive duplicates.
        body, suffix = self.names._components(raw)
        groups, compatible, conflicts = {}, {}, []
        for boundary in range(1, len(body)):
            given, last = body[:boundary], ' '.join(body[boundary:])
            if is_initial(given[0]):
                continue
            base = ' '.join([given[0]] + [w for w in given[1:] if not is_initial(w)])
            candidates = self.scoped(self.middle_keys.get((base, last, suffix), ()), role)
            for candidate in candidates:
                groups[candidate.username] = candidate
                stored_given, _, _ = self.names.account_parts(candidate.first_name, candidate.last_name)
                uploaded_initials = tuple(w for w in given[1:] if is_initial(w))
                stored_initials = tuple(w for w in stored_given[1:] if is_initial(w))
                conflicts.append(bool(uploaded_initials and stored_initials and
                    len(uploaded_initials) == len(stored_initials) and uploaded_initials != stored_initials))
                if bool(uploaded_initials) != bool(stored_initials):
                    compatible[candidate.username] = candidate
        if compatible:
            if len(groups) == 1:
                return NameResolution('matched', next(iter(compatible.values())), kind='omitted_initial')
            return NameResolution('ambiguous', matches=tuple(groups.values()), kind='omitted_initial')
        if groups:
            kind = 'middle_initial_conflict' if conflicts and all(conflicts) else 'middle_initial_details'
            return NameResolution('selection_required', kind=kind)
        return NameResolution('not_found')

    @staticmethod
    def result(matches, kind):
        return (NameResolution('matched', matches[0], kind=kind) if len(matches) == 1
                else NameResolution('ambiguous', matches=matches, kind=kind))
