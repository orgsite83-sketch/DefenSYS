"""Prepare and run resumable PIT/Capstone file uploads through the regular API.

Run --help or read execution/UPLOAD_DELIVERABLES.md. The simple command uses
student leaders automatically; --dry-run previews without uploading, like the
evaluation tools. Advanced prepare/run commands remain available separately.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timezone
import getpass
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import re
import sys
import unicodedata
from urllib.parse import urlsplit

import requests


API = '/api/repository/deliverables/'
ROOT = Path(__file__).resolve().parents[1]
# Keep in sync with repository.deliverables.timing.validate_material_file.
FORMATS = {'pdf': {'.pdf'}, 'document': {'.doc', '.docx', '.pdf'},
           'presentation': {'.ppt', '.pptx', '.pdf'}, 'spreadsheet': {'.xls', '.xlsx', '.csv'},
           'image': {'.png', '.jpg', '.jpeg', '.svg'}, 'video': {'.mp4', '.mov', '.webm'},
           'archive': {'.zip', '.rar', '.7z'}, 'audio': {'.mp3', '.wav', '.aac'}}


class UploadError(Exception):
    """A readable configuration, API, or upload error."""


class ApiError(UploadError):
    def __init__(self, status, detail):
        self.status = status
        super().__init__(f'HTTP {status}: {detail}')


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def file_digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def server_url(value):
    parsed = urlsplit(value)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/')):
        raise UploadError('Base URL must be a server origin, such as http://127.0.0.1:8000.')
    return value.rstrip('/')


def component(value):
    """Make configured IDs usable as Windows folder/file names."""
    result = re.sub(r'[^A-Za-z0-9_.-]', '__', str(value)).strip('. ')
    if not result or result.upper().split('.')[0] in {'CON', 'PRN', 'AUX', 'NUL',
            *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}:
        result = '_' + result
    return result


def local_file(root, relative):
    if not isinstance(relative, str) or not relative.strip():
        raise UploadError('No file mapped. Place a file in the expected folder and prepare a new plan, or edit file in the plan.')
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise UploadError('File path must stay inside files_root.')
    if not path.is_file():
        raise UploadError(f'File not found: {relative}')
    if path.stat().st_size == 0:
        raise UploadError(f'File is empty: {relative}')
    return path


def definition_fingerprint(row):
    return digest({key: row.get(key) for key in (
        'id', 'label', 'type', 'required', 'file_format', 'file_policy', 'document_slots',
        'requirement_timing', 'verdict_condition', 'is_defense_material', 'is_waived')})


def requirement_rows(team, stage):
    selected = team.get('selected_stage') or {}
    if selected.get('stage_label') != stage:
        raise UploadError('The server selected a different event/stage. Prepare the plan again.')
    return [row for group in ('pre', 'post') for row in selected.get(group, [])
            if row.get('source') != 'defense_minutes' and row.get('type') in ('pre', 'post')]


def repository_file_name(row, item, path):
    """Use the API's recommendation like the student Rename action; keep local files intact."""
    suggested = (row.get('suggested_file_name') or '').strip()
    if row.get('type') != 'post' or not suggested:
        return path.name
    # The screen keeps the selected file's actual extension. The API already
    # resolves all archive-template variables; do not recreate that logic here.
    recommended = Path(suggested)
    if recommended.name != suggested or '\\' in suggested:
        raise UploadError('The API recommended an invalid filename.')
    base = recommended.stem if recommended.suffix else suggested
    extension = path.suffix or recommended.suffix
    if (row.get('file_policy') or {}).get('mode', 'single') != 'single':
        base += '_' + component(item['slot_key'])
    return base + extension


class ApiClient:
    def __init__(self, base_url, *, session=None, timeout=90):
        self.base_url = server_url(base_url)
        self.session = session or requests.Session()
        self.timeout = timeout

    def request(self, method, path, **kwargs):
        try:
            response = self.session.request(method, self.base_url + path,
                timeout=self.timeout, allow_redirects=False, **kwargs)
        except requests.RequestException as error:
            # Never replay a POST: the server may already have saved the file.
            raise UploadError(f'{method} connection failed ({type(error).__name__}). '
                              'Rerun to check server state before uploading again.') from error
        if not 200 <= response.status_code < 300:
            try:
                detail = json.dumps(response.json(), ensure_ascii=False)[:700]
            except (ValueError, TypeError):
                detail = 'Non-JSON response; check the API URL and server log.'
            raise ApiError(response.status_code, detail)
        try:
            return response.json()
        except ValueError as error:
            raise UploadError('The server returned invalid JSON. Check its log before rerunning.') from error

    def authenticate(self, *, username=None, token_env='DEFENSYS_UPLOAD_TOKEN'):
        if username:
            password = getpass.getpass(f'Password for {username}: ')
            payload = self.request('POST', '/api/login/', json={'username': username, 'password': password})
            token = payload.get('access')
            if not token:
                raise UploadError('Login did not return an access token.')
        else:
            token = os.environ.get(token_env, '').strip()
            if not token:
                raise UploadError(f'Use --username to sign in, or set {token_env} to an access token.')
        self.session.headers.update({'Authorization': f'Bearer {token}'})

    def close(self):
        self.session.close()

    def teams(self, *, scope, stage, team_id=None):
        params = {'scope': scope, 'stage_label': stage}
        if team_id is not None:
            params['team_id'] = team_id
        payload = self.request('GET', API, params=params)
        if payload.get('selected_stage') != stage:
            raise UploadError(f'The event/stage {stage!r} is not available to this account.')
        return payload

    def team(self, plan, team_id):
        payload = self.teams(scope=plan['scope'], stage=plan['stage'], team_id=team_id)
        if (payload.get('active_semester') or {}).get('id') != plan['semester_id']:
            raise UploadError('The active semester changed. Prepare a new plan.')
        matches = [team for team in payload.get('teams', []) if team.get('id') == team_id]
        if len(matches) != 1:
            raise UploadError('Team is not available in this account, scope, or event roster.')
        return matches[0]

    def upload(self, plan, item, path):
        filename = item.get('repository_file_name', path.name)
        fields = {'team_id': str(item['team_id']), 'stage_label': plan['stage'],
                  'deliverable_id': item['deliverable_id'], 'slot_key': item['slot_key'],
                  'file_name': filename, 'file_size': f'{path.stat().st_size} B'}
        with path.open('rb') as stream:
            return self.request('POST', API + 'upload/', data=fields,
                params={'scope': plan['scope'], 'stage_label': plan['stage'], 'response_mode': 'team'},
                files={'file': (filename, stream, mimetypes.guess_type(path.name)[0] or 'application/octet-stream')})


@contextmanager
def local_read_only():
    """No writes or password changes; mirror the trusted local evaluation tools."""
    backend = str(ROOT / 'backend')
    if backend not in sys.path:
        sys.path.insert(0, backend)
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    import django
    from django.apps import apps
    if not apps.ready:
        django.setup()
    from django.db import connection, transaction
    from defensys_backend.db_guard import is_test_database
    with transaction.atomic():
        if not is_test_database(connection.settings_dict['NAME']):
            if connection.vendor != 'postgresql':
                raise UploadError('Student-leader discovery requires PostgreSQL read-only transactions.')
            with connection.cursor() as cursor:
                cursor.execute('SET TRANSACTION READ ONLY')
        yield


def discover_student_teams(*, scope, stage, team_ids=None, year=None):
    """Discover only the selected current-semester cohort and its real leaders."""
    with local_read_only():
        from academic_period_management.models import Semester
        from student_teams.models import StudentTeam
        terms = list(Semester.objects.filter(is_active=True))
        if len(terms) != 1:
            raise UploadError('Exactly one active semester is required for student-leader scanning.')
        term = terms[0]
        teams = StudentTeam.objects.filter(semester=term,
            level__icontains='PIT' if scope == 'pit' else 'Capstone')
        if year:
            teams = teams.filter(year_level=year)
        if team_ids is not None:
            teams = teams.filter(pk__in=team_ids)
        if scope == 'pit':
            from defense.scheduler.models import PitEventGradingConfig
            from student_teams.pit_rosters import filter_teams
            event = PitEventGradingConfig.objects.filter(semester=term, event_name=stage).first()
            if not event or (year and event.year_level != year):
                raise UploadError('PIT event is not configured for the selected active cohort.')
            teams = filter_teams(teams, stage)
        else:
            from defense.stages.models import DefenseStage
            if not DefenseStage.objects.filter(label=stage, is_active=True).exists():
                raise UploadError('Capstone stage is not active.')
        records = []
        for team in teams.select_related('leader').prefetch_related('memberships').order_by('pk'):
            leader = team.leader
            if (not leader or not leader.is_active or leader.role != 'student'
                    or leader.pk not in {member.student_id for member in team.memberships.all()}):
                raise UploadError(f'Team {team.pk} has no active student leader in its membership. Fix the roster first.')
            records.append({'team_id': team.pk, 'leader_id': leader.pk, 'username': leader.username})
        if team_ids is not None and {record['team_id'] for record in records} != set(team_ids):
            raise UploadError('Selected teams are unavailable in the current semester, scope or event roster.')
        return term.pk, records


def student_access_token(record):
    """Short-lived normal access token; no refresh-token rows or credential edits."""
    with local_read_only():
        from django.contrib.auth import get_user_model
        from rest_framework_simplejwt.tokens import AccessToken
        user = get_user_model().objects.filter(pk=record['leader_id'], username=record['username'],
                                               role='student', is_active=True).first()
        if not user:
            raise UploadError('Student leader is no longer active. Prepare a new plan.')
        return str(AccessToken.for_user(user))


class StudentLeaderBatch:
    """Route each team through its own leader's ordinary student API client."""
    student_leaders = True

    def __init__(self, base_url, *, team_ids=None, year=None):
        self.base_url = server_url(base_url)
        self.team_ids = team_ids
        self.year = year
        self._clients = {}

    def _client(self, record):
        identity = (record['leader_id'], record['username'])
        if identity not in self._clients:
            client = ApiClient(self.base_url)
            client.session.headers.update({'Authorization': f'Bearer {student_access_token(record)}'})
            self._clients[identity] = client
        return self._clients[identity]

    def _record(self, plan, team_id):
        semester_id, records = discover_student_teams(scope=plan['scope'], stage=plan['stage'],
            team_ids=[team_id], year=self.year)
        if semester_id != plan['semester_id']:
            raise UploadError('The active semester changed. Prepare a new plan.')
        record = records[0]
        expected = plan['uploaders'][str(team_id)]
        if expected != {'id': record['leader_id'], 'username': record['username']}:
            raise UploadError('Team leader changed. Prepare a new plan to confirm the new uploader.')
        return record

    def teams(self, *, scope, stage, team_id=None):
        semester_id, records = discover_student_teams(scope=scope, stage=stage,
            team_ids=[team_id] if team_id is not None else self.team_ids, year=self.year)
        teams = []
        for record in records:
            payload = self._client(record).teams(scope=scope, stage=stage, team_id=record['team_id'])
            if (payload.get('active_semester') or {}).get('id') != semester_id:
                raise UploadError('Local database and API semesters differ. Check the backend URL.')
            found = [team for team in payload.get('teams', []) if team.get('id') == record['team_id']]
            if len(found) != 1:
                raise UploadError(f'Team {record["team_id"]} is not available through its student leader API.')
            teams.append({**found[0], 'upload_actor': {'id': record['leader_id'], 'username': record['username']}})
        return {'selected_stage': stage, 'active_semester': {'id': semester_id}, 'teams': teams}

    def team(self, plan, team_id):
        return self._client(self._record(plan, team_id)).team(plan, team_id)

    def upload(self, plan, item, path):
        return self._client(self._record(plan, item['team_id'])).upload(plan, item, path)

    def close(self):
        for client in self._clients.values():
            client.close()


def matching_files(root, stem):
    return sorted(path for path in (root / stem.parent).glob(stem.name + '.*') if path.is_file())


def name_key(value):
    """Normalize spelling/case/spacing, without fuzzy or position-based matching."""
    return re.sub(r'[\W_]+', ' ', unicodedata.normalize('NFKC', value).casefold()).strip()


def matching_directories(parent, label):
    if not parent.is_dir():
        return []
    return [path for path in parent.iterdir() if path.is_dir() and name_key(path.name) == name_key(label)]


def team_name_folders(root, teams):
    folders = {}
    counts = Counter(name_key(team.get('name', '')) for team in teams)
    for team in teams:
        matches = matching_directories(root, team.get('name', ''))
        if matches and (counts[name_key(team.get('name', ''))] > 1 or len(matches) > 1):
            raise UploadError(f'Team name {team.get("name")!r} is ambiguous. Use team-ID folders for those teams.')
        folders[team['id']] = matches
    return folders


def named_requirement_files(folders, row, *, slot=None, allow_direct=True):
    """Find labels inside a team folder; optional Pre/Post folders disambiguate."""
    result = []
    for folder in folders:
        bases = ([folder] if allow_direct else []) + matching_directories(folder, row['type'])
        for base in bases:
            groups = matching_directories(base, row['label'])
            mode = (row.get('file_policy') or {}).get('mode', 'single')
            if mode == 'single':
                result.extend(path for path in base.iterdir() if path.is_file()
                              and name_key(path.stem) == name_key(row['label']))
            for group in groups:
                keys = {name_key(slot['key']), name_key(slot.get('label', ''))} if slot else None
                result.extend(path for path in group.iterdir() if path.is_file()
                              and (keys is None or name_key(path.stem) in keys))
    return result


def team_filename_files(root, teams):
    """Match a full team-name prefix, ignoring the remaining filename text."""
    if not root.is_dir():
        raise UploadError('The batch files folder does not exist.')
    by_team = {team['id']: [] for team in teams}
    team_keys = {}
    for team in teams:
        words = name_key(team.get('name', '')).split()
        keys = {''.join(words)} - {''}
        # Demo roster names include "Team AlphaWave" while the samples use
        # "AlphaWave_...". Both forms identify the same team, unless ambiguous.
        if len(words) > 1 and words[0] == 'team':
            keys.add(''.join(words[1:]))
        team_keys[team['id']] = keys
    for path in sorted(root.iterdir()):
        if not path.is_file():
            continue
        # Compact spelling accepts AlphaWave and Alpha Wave. Prefix boundaries
        # prevent Alpha from matching AlphaWave; never use substring/fuzzy matches.
        words = name_key(path.stem).split()
        prefixes = {''.join(words[:end]) for end in range(1, len(words) + 1)}
        # Optional sample-file numbering is decoration, never a team index.
        if len(words) > 1 and words[0].isdigit():
            prefixes.update(''.join(words[1:end]) for end in range(2, len(words) + 1))
        matches = [team for team in teams if team_keys[team['id']] & prefixes]
        if len(matches) > 1:
            labels = ', '.join(f'{team["name"]} (ID {team["id"]})' for team in matches)
            raise UploadError(f'Filename {path.name!r} has an ambiguous team name: {labels}. '
                              'Use team-ID folders without --deliverable for those teams.')
        if matches:
            by_team[matches[0]['id']].append(path)
    return by_team


def selected_requirement(rows, selector, team, timing):
    candidates = [row for row in rows if (timing == 'all' or row['type'] == timing)
                  and (row['id'].casefold() == selector.casefold()
                       or name_key(row['label']) == name_key(selector))]
    if len(candidates) != 1:
        available = ', '.join(f'{row["id"]}: {row["label"]} ({row["type"]})' for row in rows)
        raise UploadError(f'Team {team["id"]}: deliverable {selector!r} must identify exactly one '
                          f'requirement for timing {timing!r}. Available: {available}')
    return candidates


def selected_document_slots(definitions, selector):
    if selector:
        definitions = [slot for slot in definitions if slot['key'].casefold() == selector.casefold()
                       or name_key(slot.get('label', '')) == name_key(selector)]
    if len(definitions) != 1:
        raise UploadError('Choose exactly one grouped document using --slot with its key or label.')
    return definitions


def requirement_folder(root, row, overrides):
    """A folder selects the requirement; filenames only select the owning team."""
    override = overrides.get(row['id'].casefold())
    if override is not None:
        folder = (root / override).resolve()
        if not folder.is_relative_to(root) or not folder.is_dir():
            raise UploadError(f'Folder for {row["id"]} must exist inside --files.')
    else:
        candidates = [path for path in root.iterdir() if path.is_dir() and
                      (name_key(path.name) == name_key(row['label']) or
                       name_key(path.name).split()[:1] == [name_key(row['id'])])]
        if len(candidates) > 1:
            raise UploadError(f'Multiple folders match {row["id"]}. Use --folder "{row["id"]}=PATH".')
        if not candidates:
            return None
        folder = candidates[0]
    # Existing samples offer PDF and editable variants. For a PDF requirement,
    # its explicit PDF subfolder selects the required format without duplication.
    if not any(path.is_file() for path in folder.iterdir()):
        formats = matching_directories(folder, row.get('file_format', 'any'))
        if len(formats) == 1:
            folder = formats[0]
    return folder


def prepare_plan(client, *, scope, stage, files_root, team_ids=(), all_teams=False,
                 timing='pre', year=None, deliverable=None, slot=None,
                 batch_folders=False, folder_overrides=None):
    slot_selector = slot
    if not all_teams and not team_ids:
        raise UploadError('Select team IDs or explicitly choose all teams.')
    if slot and not deliverable:
        raise UploadError('--slot requires --deliverable.')
    if deliverable is not None and not deliverable.strip():
        raise UploadError('--deliverable must name a configured requirement or its ID.')
    payload = client.teams(scope=scope, stage=stage)
    semester_id = (payload.get('active_semester') or {}).get('id')
    if not semester_id:
        raise UploadError('No active semester is available.')
    teams = payload.get('teams', [])
    if year:
        teams = [team for team in teams if team.get('year_level') == year]
    if not all_teams:
        teams = [team for team in teams if team.get('id') in team_ids]
        if {team['id'] for team in teams} != set(team_ids):
            raise UploadError('One or more selected teams are unavailable in this scope/year/event.')
    if not teams:
        raise UploadError('No matching teams. Check scope, event/stage, year and account access.')
    root = files_root.resolve()
    if batch_folders and not root.is_dir():
        raise UploadError('The batch files folder does not exist.')
    overrides = folder_overrides or {}
    if deliverable and overrides:
        raise UploadError('Use --files for a single --deliverable, or --folder for a multi-deliverable batch.')
    named_folders = team_name_folders(root, teams) if not deliverable else {}
    filename_files = team_filename_files(root, teams) if deliverable else {}
    folder_files = {}
    used_overrides = set()
    def files_in(folder):
        folder = folder.resolve()
        if not folder.is_relative_to(root):
            raise UploadError('Deliverable folders must stay inside --files.')
        if folder not in folder_files:
            folder_files[folder] = team_filename_files(folder, teams)
        return folder_files[folder]
    items = []
    for team in teams:
        rows = requirement_rows(team, stage)
        label_counts = Counter(name_key(row['label']) for row in rows)
        if deliverable:
            rows = selected_requirement(rows, deliverable, team, timing)
        for row in rows:
            if timing != 'all' and row.get('type') != timing:
                continue
            if row.get('is_waived'):
                continue
            mode = (row.get('file_policy') or {}).get('mode', 'single')
            if slot_selector and mode not in ('named', 'concepts'):
                raise UploadError('--slot is only used for named or concept document groups.')
            prefix = Path(str(team['id'])) / component(row['id'])
            flat_prefix = Path(f'{team["id"]}__{component(row["id"])}')
            folder = requirement_folder(root, row, overrides) if batch_folders and not deliverable else None
            if row['id'].casefold() in overrides:
                used_overrides.add(row['id'].casefold())
            row_files = files_in(folder)[team['id']] if folder else filename_files.get(team['id'], [])
            allow_direct = label_counts[name_key(row['label'])] == 1
            if mode == 'multiple':
                if deliverable or folder:
                    paths = row_files
                else:
                    paths = sorted(path for path in (root / prefix).glob('*') if path.is_file())
                    paths += sorted(path for path in root.glob(str(flat_prefix) + '__*.*') if path.is_file())
                    paths += named_requirement_files(named_folders[team['id']], row, allow_direct=allow_direct)
                paths = sorted(set(paths))
                slots = [(f'auto_{digest(path.name)[:32]}', path.relative_to(root).as_posix(),
                          row.get('file_format', 'any')) for path in paths]
                if not slots:
                    slots = [('attachment-1', '', row.get('file_format', 'any'))]
                expected = (prefix / '<filename>').as_posix()
            else:
                definitions = row.get('document_slots') or []
                if mode == 'single':
                    definitions = [{'key': 'primary', 'file_format': row.get('file_format', 'any')}]
                if not definitions:
                    raise UploadError(f'Team {team["id"]}, {row["id"]}: no document slots returned. Complete concept setup first.')
                if deliverable and mode != 'single':
                    definitions = selected_document_slots(definitions, slot_selector)
                slots = []
                for slot in definitions:
                    stem = prefix if mode == 'single' else prefix / component(slot['key'])
                    flat_stem = flat_prefix if mode == 'single' else Path(f'{flat_prefix}__{component(slot["key"])}')
                    if deliverable:
                        candidates = row_files
                    elif folder:
                        candidates = row_files
                        if mode != 'single':
                            groups = list(set(matching_directories(folder, slot['key']) +
                                matching_directories(folder, component(slot['key'])) +
                                matching_directories(folder, slot.get('label', ''))))
                            if len(groups) > 1:
                                raise UploadError(f'Multiple folders match document {slot["key"]}.')
                            candidates = files_in(groups[0])[team['id']] if groups else (
                                row_files if len(definitions) == 1 else [])
                    else:
                        candidates = matching_files(root, stem) + matching_files(root, flat_stem)
                        candidates += named_requirement_files(named_folders[team['id']], row,
                            slot=slot if mode != 'single' else None, allow_direct=allow_direct)
                    candidates = sorted(set(candidates))
                    relative = candidates[0].relative_to(root).as_posix() if len(candidates) == 1 else ''
                    slots.append((slot['key'], relative, slot.get('file_format', row.get('file_format', 'any'))))
                expected = ''
            for key, relative, file_format in slots:
                hint = expected or ((prefix if mode == 'single' else prefix / component(key)).as_posix() + '.<extension>')
                if deliverable or folder:
                    hint = f'{team.get("name", "Team")}_<any filename>.<extension>'
                items.append({'team_id': team['id'], 'team_name': team.get('name', ''),
                    'project_version': team['project_version'], 'deliverable_id': row['id'],
                    'deliverable_label': row['label'], 'type': row['type'], 'slot_key': key,
                    'file_format': file_format, 'definition_fingerprint': definition_fingerprint(row),
                    'file': relative, 'expected_path': hint,
                    'named_path': f'{team.get("name", "Team")}/{row["label"]}' +
                                  ('.<extension>' if mode == 'single' else '/<document filename>'),
                    'suggested_file_name': row.get('suggested_file_name', ''),
                    'flat_path': (str(flat_prefix) + ('__<filename>' if mode == 'multiple' else
                                  ('' if mode == 'single' else '__' + component(key)) + '.<extension>'))})
    if set(overrides) - used_overrides:
        raise UploadError('Folder mappings do not match selected requirements: ' + ', '.join(sorted(set(overrides) - used_overrides)))
    plan = {'schema_version': 1, 'base_url': client.base_url, 'scope': scope, 'stage': stage,
            'semester_id': semester_id, 'files_root': str(root), 'items': items}
    if deliverable:
        plan.update(deliverable=deliverable, file_matching='team_filename')
    if getattr(client, 'student_leaders', False) is True:
        plan.update(upload_as='student_leaders', uploaders={str(team['id']): team['upload_actor'] for team in teams})
    return plan


def validate_plan(plan):
    if not isinstance(plan, dict):
        raise UploadError('Upload plan must be a JSON object.')
    if plan.get('schema_version') != 1 or plan.get('scope') not in ('pit', 'capstone'):
        raise UploadError('Unsupported upload plan.')
    server_url(plan.get('base_url', ''))
    if not isinstance(plan.get('stage'), str) or not plan['stage'].strip():
        raise UploadError('Plan must name an event/stage.')
    if type(plan.get('semester_id')) is not int or plan['semester_id'] <= 0:
        raise UploadError('Plan must identify its semester.')
    if not isinstance(plan.get('files_root'), str) or not Path(plan['files_root']).is_absolute():
        raise UploadError('Plan files_root must be an absolute folder path.')
    if not isinstance(plan.get('items'), list):
        raise UploadError('Plan items must be a list.')
    seen = set()
    file_owners = {}
    for item in plan['items']:
        if not isinstance(item, dict) or any(not isinstance(item.get(key), str) or not item[key]
                for key in ('deliverable_id', 'slot_key', 'definition_fingerprint')):
            raise UploadError('Each item needs a deliverable ID, slot key and definition fingerprint.')
        if (type(item.get('team_id')) is not int or item['team_id'] <= 0
                or type(item.get('project_version')) is not int or item['project_version'] < 1):
            raise UploadError('Each item needs its original team ID and project version.')
        identity = (item['team_id'], item['deliverable_id'], item['slot_key'])
        if identity in seen:
            raise UploadError(f'Duplicate upload target: {identity}')
        seen.add(identity)
        if item.get('file'):
            path = os.path.normcase(str((Path(plan['files_root']) / item['file']).resolve()))
            if path in file_owners and file_owners[path] != item['team_id']:
                raise UploadError('Each team must have its own file; the same file is mapped to different teams.')
            file_owners[path] = item['team_id']
    if plan.get('upload_as', 'signed_in') not in ('signed_in', 'student_leaders'):
        raise UploadError('Unsupported upload identity mode.')
    if plan.get('upload_as') == 'student_leaders':
        for item in plan['items']:
            actor = plan.get('uploaders', {}).get(str(item['team_id']), {})
            if type(actor.get('id')) is not int or not isinstance(actor.get('username'), str) or not actor['username']:
                raise UploadError('Student-leader plans must identify the uploader for every team.')


def inspect_item(plan, item, team):
    if team.get('semester_id') != plan['semester_id'] or team.get('project_version') != item['project_version']:
        raise UploadError('Team semester or project version changed. Prepare a new plan.')
    level = team.get('level', '').lower()
    expected_scope = 'pit' if 'pit' in level else 'capstone' if 'capstone' in level else None
    if expected_scope != plan['scope']:
        raise UploadError('Team scope differs from the plan.')
    rows = [row for row in requirement_rows(team, plan['stage']) if row['id'] == item['deliverable_id']]
    if len(rows) != 1 or definition_fingerprint(rows[0]) != item['definition_fingerprint']:
        raise UploadError('Requirement or document slots changed. Prepare a new plan.')
    row = rows[0]
    mode = (row.get('file_policy') or {}).get('mode', 'single')
    if mode not in ('single', 'multiple', 'named', 'concepts'):
        raise UploadError('Unsupported document mode.')
    if mode == 'single' and item['slot_key'] != 'primary':
        raise UploadError('Single-file requirements use the primary slot.')
    if mode in ('named', 'concepts') and item['slot_key'] not in {slot['key'] for slot in row.get('document_slots', [])}:
        raise UploadError('Unknown document slot. Prepare a new plan.')
    submission = row.get('submission') or {}
    current = submission.get('files') or []
    if any(file.get('slot_key') == item['slot_key'] for file in current):
        return 'skip', 'Target slot already has a file; it will be preserved.', None
    if mode == 'single' and (submission.get('file_url') or submission.get('file_name') or row.get('uploaded')):
        return 'skip', 'Existing submission will be preserved.', None
    if row.get('can_upload') is not True or row.get('is_waived'):
        raise UploadError('Server does not allow uploading now (permission, timing, waiver or workflow lock).')
    path = local_file(Path(plan['files_root']), item.get('file'))
    file_format = row.get('file_format') or 'any'
    if mode in ('named', 'concepts'):
        file_format = next(slot.get('file_format') or file_format for slot in row['document_slots'] if slot['key'] == item['slot_key'])
    allowed = FORMATS.get(file_format, {'.' + file_format})
    if file_format not in ('any', '', None) and path.suffix.lower() not in allowed:
        raise UploadError(f'Expected {file_format}, got {path.suffix or "a file without an extension"}.')
    if mode == 'multiple':
        # A previous/manual upload with another key is never silently duplicated.
        names = {path.name, repository_file_name(row, item, path)}
        if any(file.get('file_name') in names for file in current):
            return 'skip', 'An attachment with this filename already exists; it will be preserved.', None
        if len(current) >= (row.get('file_policy') or {}).get('max_files', 10):
            raise UploadError('Attachment limit reached.')
    return 'ready', 'File mapped and upload permitted.', path


def run_plan(client, plan, *, apply=False, journal=None):
    validate_plan(plan)
    if client.base_url != plan['base_url']:
        raise UploadError('Client server differs from the prepared plan.')
    if plan.get('upload_as') == 'student_leaders' and getattr(client, 'student_leaders', False) is not True:
        raise UploadError('This plan must run through its student leaders, not a staff account.')
    results = []
    cached_teams = {}
    for item in plan['items']:
        stop = False
        result = {key: item.get(key) for key in ('team_id', 'deliverable_id', 'slot_key', 'file')}
        if plan.get('upload_as') == 'student_leaders':
            result['uploader'] = plan['uploaders'][str(item['team_id'])]
        try:
            # Live runs refresh before every upload, including successive document slots.
            if apply or item['team_id'] not in cached_teams:
                cached_teams[item['team_id']] = client.team(plan, item['team_id'])
            status, detail, path = inspect_item(plan, item, cached_teams[item['team_id']])
            result.update(status=status, detail=detail)
            if status == 'ready':
                result['detail'] += f' Source: {item["file"]}.'
                result['sha256'] = file_digest(path)
                row = next(row for row in requirement_rows(cached_teams[item['team_id']], plan['stage'])
                           if row['id'] == item['deliverable_id'])
                filename = repository_file_name(row, item, path)
                upload_item = item
                if row['type'] == 'post' and row.get('suggested_file_name'):
                    result['recommended_name'] = row['suggested_file_name']
                    result['repository_file_name'] = filename
                    result['detail'] += f' Repository filename: {filename}.'
                    upload_item = {**item, 'repository_file_name': filename}
                if apply:
                    response = client.upload(plan, upload_item, path)
                    if not response.get('submission_id'):
                        raise UploadError('Upload response had no submission ID. Rerun to check server state.')
                    result.update(status='uploaded', detail='Upload saved by the server.', submission_id=response['submission_id'])
        except (UploadError, OSError) as error:
            result.update(status='blocked', detail=str(error))
            stop = isinstance(error, ApiError) and error.status in (401, 429)
        result['time'] = datetime.now(timezone.utc).isoformat()
        result['plan_context'] = {key: plan[key] for key in ('base_url', 'scope', 'stage', 'semester_id')}
        results.append(result)
        print(f'[{result["status"].upper()}] Team {item["team_id"]} / {item["deliverable_id"]} / '
              f'{item["slot_key"]}: {result["detail"]}')
        if journal:
            journal.write(json.dumps(result, ensure_ascii=False) + '\n')
            journal.flush()
            os.fsync(journal.fileno())
        if stop:
            print(f'Stopping after authentication/rate-limit error; {len(plan["items"]) - len(results)} targets unprocessed.')
            break
    print('Summary: ' + json.dumps(dict(Counter(row['status'] for row in results))))
    return 2 if any(row['status'] == 'blocked' for row in results) else 0


@contextmanager
def apply_lock(manifest):
    lock = manifest.with_suffix(manifest.suffix + '.lock')
    try:
        stream = lock.open('x', encoding='utf-8')
    except FileExistsError as error:
        raise UploadError(f'Another run owns {lock.name}. If its process has stopped, remove that lock before rerunning.') from error
    try:
        with stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        lock.unlink()


def manifest_main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare', help='Read configured requirements and create an editable JSON plan.')
    prepare.add_argument('--base-url', default='http://127.0.0.1:8000')
    prepare.add_argument('--scope', choices=['pit', 'capstone'], required=True)
    prepare.add_argument('--stage', required=True, help='Exact PIT event or Capstone stage name.')
    targets = prepare.add_mutually_exclusive_group(required=True)
    targets.add_argument('--team-id', type=int, nargs='+')
    targets.add_argument('--all-teams', action='store_true', help='All teams visible to the signed-in account in this context.')
    prepare.add_argument('--year', help='Optional exact year level, e.g. "1st Year".')
    prepare.add_argument('--timing', choices=['pre', 'post', 'all'], default='pre')
    prepare.add_argument('--deliverable', help='Select one requirement by label or ID; match flat filenames by team name only.')
    prepare.add_argument('--slot', help='With --deliverable, select one named/concept document by key or label.')
    prepare.add_argument('--files-root', type=Path, required=True)
    prepare.add_argument('--student-leaders', action='store_true',
        help='Demo automation: discover local teams and upload through each real student leader account.')
    run = commands.add_parser('run', help='Preview a plan; add --apply to upload.')
    run.add_argument('--apply', action='store_true')
    run.add_argument('--journal', type=Path, help='Append-only JSONL progress log (default under .tmp/).')
    for command in (prepare, run):
        command.add_argument('--manifest', type=Path, required=True)
        command.add_argument('--username', help='Sign in normally; password is prompted, never saved.')
        command.add_argument('--token-env', default='DEFENSYS_UPLOAD_TOKEN', help='Environment variable containing an existing access token.')
    args = parser.parse_args(argv)
    try:
        manifest = args.manifest.resolve()
        plan = None
        if args.command == 'run':
            plan = json.loads(manifest.read_text(encoding='utf-8-sig'))
            validate_plan(plan)
        elif manifest.exists():
            raise UploadError('Manifest already exists. Use a new filename to preserve your mappings.')
        student_mode = plan.get('upload_as') == 'student_leaders' if plan else args.student_leaders
        if student_mode and args.username:
            raise UploadError('Student-leader mode uses the local demo accounts; omit --username.')
        if student_mode:
            client = StudentLeaderBatch(plan['base_url'] if plan else args.base_url,
                team_ids=sorted({item['team_id'] for item in plan['items']}) if plan else args.team_id,
                year=None if plan else args.year)
        else:
            client = ApiClient(plan['base_url'] if plan else args.base_url)
        try:
            if not student_mode:
                client.authenticate(username=args.username, token_env=args.token_env)
            if args.command == 'prepare':
                plan = prepare_plan(client, scope=args.scope, stage=args.stage, files_root=args.files_root,
                    team_ids=args.team_id or (), all_teams=args.all_teams, timing=args.timing, year=args.year,
                    deliverable=args.deliverable, slot=args.slot)
                validate_plan(plan)
                manifest.parent.mkdir(parents=True, exist_ok=True)
                with manifest.open('x', encoding='utf-8') as stream:
                    stream.write(json.dumps(plan, indent=2, ensure_ascii=False) + '\n')
                print(f'Prepared {len(plan["items"])} targets: {manifest}')
                if student_mode:
                    print(f'Student leaders: {len(plan["uploaders"])} teams; uploads will be attributed to those students.')
                print('Fill blank file mappings; then use run to preview. No files were uploaded.')
                return 0
            journal_path = args.journal or ROOT / '.tmp' / f'{manifest.stem}.upload-results.jsonl'
            journal_path = journal_path.resolve()
            if journal_path == manifest:
                raise UploadError('The progress log cannot overwrite the manifest.')
            journal_path.parent.mkdir(parents=True, exist_ok=True)
            if args.apply:
                with apply_lock(manifest), journal_path.open('a', encoding='utf-8') as journal:
                    return run_plan(client, plan, apply=True, journal=journal)
            with journal_path.open('a', encoding='utf-8') as journal:
                print('PREVIEW: no files will be uploaded. Add --apply to upload ready items.')
                return run_plan(client, plan, journal=journal)
        finally:
            client.close()
    except (UploadError, OSError, ValueError, TypeError, KeyError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('Stopped. Check saved progress and server state before rerunning.', file=sys.stderr)
        return 130


def year_label(value):
    compact = ''.join(name_key(value).split())
    labels = {'1': '1st Year', '2': '2nd Year', '3': '3rd Year', '4': '4th Year'}
    for number, label in labels.items():
        if compact in (number, ''.join(label.lower().split()), label.split()[0]):
            return label
    raise argparse.ArgumentTypeError('Use a year number from 1 to 4, or a label such as "1st Year".')


def batch_stage(scope, year, stage):
    if stage and stage.strip():
        return stage.strip()
    with local_read_only():
        if scope == 'pit':
            from defense.scheduler.models import PitEventGradingConfig
            events = PitEventGradingConfig.objects.filter(semester__is_active=True)
            if year:
                events = events.filter(year_level=year)
            choices = list(events.values_list('event_name', flat=True))
        else:
            from defense.stages.models import DefenseStage
            choices = list(DefenseStage.objects.filter(is_active=True).values_list('label', flat=True))
    if len(choices) != 1:
        raise UploadError('Choose --stage explicitly. Available events/stages: ' + (', '.join(choices) or 'none'))
    return choices[0]


def simple_main(argv):
    parser = argparse.ArgumentParser(
        description='Upload team deliverables as their student leaders. Add --dry-run to preview.',
        epilog='Advanced saved-plan commands are still available: prepare --help or run --help.')
    targets = parser.add_mutually_exclusive_group(required=True)
    targets.add_argument('--all-teams', action='store_true', help='Process every team in the selected event/stage.')
    targets.add_argument('--team-id', type=int, nargs='+', help='Process only these team IDs.')
    parser.add_argument('--scope', choices=['pit', 'capstone'], default='pit', help='Default: pit.')
    parser.add_argument('--year', type=year_label, help='Year number, e.g. --year 1.')
    parser.add_argument('--stage', help='Event/stage name; optional when exactly one is available.')
    parser.add_argument('--files', '--files-root', dest='files_root', type=Path, required=True,
                        help='Folder containing one deliverable, or subfolders for all selected deliverables.')
    parser.add_argument('--deliverable', help='Upload one configured requirement by label or ID.')
    parser.add_argument('--slot', help='With --deliverable, choose one grouped document by key or label.')
    parser.add_argument('--timing', choices=['pre', 'post', 'all'], default='pre', help='Default: pre.')
    parser.add_argument('--folder', action='append', default=[], metavar='ID=PATH',
                        help='Optional folder override relative to --files, e.g. "D1=Concept Paper/PDF".')
    parser.add_argument('--dry-run', action='store_true', help='Preview without uploading. Otherwise ready files are uploaded.')
    parser.add_argument('--base-url', default='http://127.0.0.1:8000')
    args = parser.parse_args(argv)
    client = None
    try:
        overrides = {}
        for mapping in args.folder:
            key, separator, path = mapping.partition('=')
            key = key.strip().casefold()
            if not separator or not key or not path.strip() or key in overrides:
                raise UploadError('Each --folder must be a unique ID=PATH mapping.')
            overrides[key] = path.strip()
        stage = batch_stage(args.scope, args.year, args.stage)
        client = StudentLeaderBatch(args.base_url, team_ids=args.team_id, year=args.year)
        print(f'Mode: {"DRY RUN (no uploads)" if args.dry_run else "LIVE UPLOAD"}')
        print(f'{args.scope.upper()} / {stage} / {args.year or "selected cohort"} / {args.timing}')
        plan = prepare_plan(client, scope=args.scope, stage=stage, files_root=args.files_root,
            team_ids=args.team_id or (), all_teams=args.all_teams, timing=args.timing, year=args.year,
            deliverable=args.deliverable, slot=args.slot, batch_folders=True, folder_overrides=overrides)
        validate_plan(plan)
        print(f'{len(plan["items"])} documents across {len(plan["uploaders"])} student leaders.')
        # No user-managed manifest: keep the same validation, live refresh and
        # resumability as the saved-plan workflow, using server state on each run.
        log_key = digest(plan)[:16]
        log_root = ROOT / '.tmp'
        log_root.mkdir(parents=True, exist_ok=True)
        journal_path = log_root / f'deliverable-uploads-{log_key}.jsonl'
        if args.dry_run:
            with journal_path.open('a', encoding='utf-8') as journal:
                return run_plan(client, plan, journal=journal)
        with apply_lock(log_root / f'deliverable-uploads-{log_key}.json'), journal_path.open('a', encoding='utf-8') as journal:
            return run_plan(client, plan, apply=True, journal=journal)
    except (UploadError, OSError, ValueError, TypeError, KeyError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('Stopped. Rerun to check server state before uploading again.', file=sys.stderr)
        return 130
    finally:
        if client:
            client.close()


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments and arguments[0] in ('prepare', 'run'):
        return manifest_main(arguments)
    return simple_main(arguments)


if __name__ == '__main__':
    raise SystemExit(main())
