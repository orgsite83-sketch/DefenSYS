"""Deterministic import-name comparison; never modify account or uploaded names."""
import re
import unicodedata
from collections import defaultdict
from dataclasses import dataclass
from functools import lru_cache
from defensys_backend.person_names import name_encoding_issue


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
        text = re.sub(r'\s*-\s*', '-', unicodedata.normalize('NFC', value or '').strip())
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
        self.profiles = defaultdict(list)
        self.families = defaultdict(set)
        self.damaged = []
        for user in self.users:
            if name_encoding_issue(user.first_name) or name_encoding_issue(user.last_name):
                self.damaged.append(user)
                continue
            given, family, suffix = names.account_parts(user.first_name, user.last_name)
            if given and family:
                self.profiles[(given[0], family)].append((user, given, suffix))
                self.families[family[0]].add(family)
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

    @staticmethod
    def given_compatible(uploaded, stored):
        if not uploaded or not stored or uploaded[0] != stored[0] or is_initial(uploaded[0]):
            return False
        @lru_cache(None)
        def align(i, j):
            if i == len(uploaded) and j == len(stored):
                return True
            if i < len(uploaded) and j < len(stored):
                a, b = uploaded[i], stored[j]
                if is_initial(a) and is_initial(b) and a != b:
                    return False
                if (a == b or is_initial(a) and b.startswith(a) or is_initial(b) and a.startswith(b)) and align(i + 1, j + 1):
                    return True
            return (i < len(uploaded) and is_initial(uploaded[i]) and align(i + 1, j)
                    or j < len(stored) and is_initial(stored[j]) and align(i, j + 1))
        return align(1, 1)

    def _resolve(self, raw, role):
        if not raw:
            return NameResolution('empty')
        user = self.usernames.get(raw.casefold())
        if user and self.scoped([user], role):
            return NameResolution('matched', user, kind='id')
        if name_encoding_issue(raw):
            return NameResolution('encoding_problem')

        # Repair only a separator immediately after a complete known surname.
        if ',' not in raw and '.' in raw:
            normalized = comparison_text(raw)
            first = normalized.split()[0]
            families = self.families.get(first, set()) | self.families.get(first.rstrip('.'), set())
            interpretations, uncertain = {}, False
            for family in families:
                prefix = ' '.join(family) + '.'
                if not normalized.startswith(prefix + ' '):
                    continue
                result = self._resolve(' '.join(family) + ', ' + normalized[len(prefix):].strip(), role)
                candidates = (result.user,) if result.user else result.matches
                for candidate in candidates:
                    interpretations[candidate.username] = candidate
                uncertain |= result.status not in ('matched', 'not_found')
            if interpretations:
                if len(interpretations) == 1 and not uncertain:
                    return NameResolution('matched', next(iter(interpretations.values())), kind='surname_separator')
                return NameResolution('ambiguous', matches=tuple(interpretations.values()), kind='surname_separator')

        body, suffix = self.names._components(raw)
        compatible, potential, suffix_variants, detail_kinds = {}, {}, {}, set()
        expanded, omitted = False, False
        for boundary in range(1, len(body)):
            given, family = body[:boundary], body[boundary:]
            for candidate, stored, stored_suffix in self.profiles.get((given[0], family), ()):
                if not self.scoped([candidate], role):
                    continue
                agrees = self.given_compatible(given, stored)
                if stored_suffix == suffix:
                    potential[candidate.username] = candidate
                    conflict = len(given) == len(stored) and any(is_initial(a) and is_initial(b) and a != b
                        for a, b in zip(given[1:], stored[1:]))
                    detail_kinds.add('middle_initial_conflict' if conflict else 'middle_initial_details')
                    if agrees:
                        compatible[candidate.username] = candidate
                        expanded |= len(given) == len(stored) and given != stored
                        omitted |= len(given) != len(stored)
                elif agrees:
                    suffix_variants[candidate.username] = candidate
        if compatible:
            # Unspecified middle information/suffix cannot select among accounts.
            no_middle = any(len(body[:b]) == 1 and self.profiles.get((body[0], body[b:]))
                            for b in range(1, len(body)))
            candidates = dict(compatible)
            if no_middle or omitted:
                candidates.update(potential)
            if not suffix:
                candidates.update(suffix_variants)
            if len(candidates) > 1:
                return NameResolution('ambiguous', matches=tuple(candidates.values()), kind='name_details')
            candidate = next(iter(compatible.values()))
            exact = candidate in self.full_matches(raw, role)
            return NameResolution('matched', candidate,
                kind='full_name' if exact else 'middle_initial_expanded' if expanded else 'omitted_initial')
        matches = self.full_matches(raw, role)
        if matches:
            return self.result(matches, 'full_name')
        if suffix_variants:
            return NameResolution('selection_required', matches=tuple(suffix_variants.values()), kind='suffix_difference')
        if potential:
            kind = 'middle_initial_conflict' if detail_kinds == {'middle_initial_conflict'} else 'middle_initial_details'
            return NameResolution('selection_required', matches=tuple(potential.values()), kind=kind)

        words = self.names.key(raw).split()
        if len(words) >= 2 and is_initial(words[0]):
            matches = self.scoped(self.initials.get((' '.join(words[1:]), words[0]), ()), role)
            if matches:
                return self.result(matches, 'initial')
        if ',' not in raw and len(words) >= 2 and is_initial(words[-1]):
            matches = self.scoped(self.initials.get((' '.join(words[:-1]), words[-1]), ()), role)
            if matches:
                return self.result(matches, 'initial')
        matches = self.scoped(self.surnames.get(self.names.key(raw), ()), role)
        if matches:
            return self.result(matches, 'surname')

        # Review-only surname variants and damaged names never bind identities.
        for boundary in range(1, len(body)):
            given, family = body[:boundary], ' '.join(body[boundary:])
            for (first, registered_family), profiles in self.profiles.items():
                if first != given[0]:
                    continue
                registered = ' '.join(registered_family)
                fold = lambda text: ''.join(c for c in unicodedata.normalize('NFD', text) if not unicodedata.combining(c))
                variant = (family.endswith('-' + registered) or registered.endswith('-' + family)
                           or fold(family) == fold(registered))
                if variant:
                    candidates = tuple(u for u, stored, sf in profiles
                        if sf == suffix and self.scoped([u], role) and self.given_compatible(given, stored))
                    if candidates:
                        return NameResolution('selection_required', matches=candidates, kind='surname_variant')
            for candidate in self.scoped(self.damaged, role):
                stored, registered_family, sf = self.names.account_parts(candidate.first_name, candidate.last_name)
                pattern = re.escape(' '.join(registered_family)).replace('\ufffd', '.')
                if self.given_compatible(given, stored) and sf == suffix and re.fullmatch(pattern, family):
                    return NameResolution('encoding_problem')
        return NameResolution('not_found')

    @staticmethod
    def result(matches, kind):
        return (NameResolution('matched', matches[0], kind=kind) if len(matches) == 1
                else NameResolution('ambiguous', matches=matches, kind=kind))


PREFIX_PATTERNS = [
    r'associate\s+professor',
    r'assistant\s+professor',
    r'assoc\.?\s*prof\.?',
    r'asst\.?\s*prof\.?',
    r'prof(?:essor)?\.?',
    r'dr\.?',
    r'doctor',
    r'engr\.?',
    r'engineer',
    r'atty\.?',
    r'attorney',
    r'arch(?:itect)?\.?',
    r'dean',
    r'chair(?:person)?',
    r'inst(?:ructor)?\.?',
    r'lect(?:urer)?\.?',
    r'hon(?:orable)?\.?',
    r'rev(?:erend)?\.?',
    r'pastor|pst\.?',
    r'fr\.?|father',
    r'mr\.?',
    r'mrs\.?',
    r'ms\.?',
    r'mx\.?',
    r'sir',
    r'ma[\'\’]?am|mam',
]

SUFFIX_PATTERNS = [
    r'ph\.?d\.?',
    r'd\.?eng\.?',
    r'd\.?i\.?t\.?',
    r'd\.?b\.?a\.?',
    r'ed\.?d\.?',
    r'm\.?d\.?',
    r'j\.?d\.?',
    r'sc\.?d\.?',
    r'm\.?sc\.?',
    r'm\.?s\.?',
    r'm\.?a\.?',
    r'm\.?eng\.?',
    r'm\.?i\.?t\.?',
    r'm\.?s\.?i\.?t\.?',
    r'm\.?b\.?a\.?',
    r'm\.?p\.?a\.?',
    r'm\.?ed\.?',
    r'b\.?sc\.?',
    r'b\.?s\.?',
    r'b\.?a\.?',
    r'b\.?s\.?i\.?t\.?',
    r'p\.?e\.?',
    r'c\.?p\.?a\.?',
    r'rce|ece|ree|rme',
    r'pmp|cisa|cissp',
    r'jr\.?|sr\.?',
    r'ii|iii|iv|v',
]


DEFAULT_PERSON_NAMES = PersonNames(PREFIX_PATTERNS, SUFFIX_PATTERNS[:-2])
