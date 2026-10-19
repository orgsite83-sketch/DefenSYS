"""Read-only folder projections for the project archive browser."""

import base64
import json


GROUP_BY_CHOICES = {'team', 'stage', 'deliverable'}


def _encode_path(path):
    raw = json.dumps(path, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    return base64.urlsafe_b64encode(raw).decode('ascii').rstrip('=')


def _decode_path(value):
    if not value:
        return []
    try:
        raw = base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
        path = json.loads(raw)
        if isinstance(path, list) and 1 <= len(path) <= 5 and all(isinstance(item, str) for item in path):
            return path
    except (ValueError, UnicodeDecodeError, TypeError):
        pass
    return None


def academic_term_folder_key(academic_year, semester):
    return _encode_path([
        json.dumps(['academic_year', academic_year]),
        json.dumps(['semester', semester]),
    ])


def _file_entries(entries):
    return [entry for entry in entries if entry.get('has_file') and not entry.get('is_missing')]


def _event_cohort_key(entry):
    track = entry.get('type') or 'capstone'
    year = entry.get('academic_year') or ''
    semester = entry.get('semester') or ''
    year_level = entry.get('year_level') or ''
    stage = (entry.get('stage') or entry.get('course_code') or '').strip().lower()
    return (track, year, semester, year_level, stage)


def _known_pit_event_ids(entries):
    mapping = {}
    for entry in entries:
        track = entry.get('type') or 'capstone'
        event_id = entry.get('pit_event_config_id')
        if track == 'pit' and event_id:
            key = _event_cohort_key(entry)
            mapping.setdefault(key, event_id)
    return mapping


def _segments(entry, group_by, known_event_ids=None):
    track = entry.get('type') or 'capstone'
    year = entry.get('academic_year') or 'Unknown academic year'
    semester = entry.get('semester') or 'Unknown semester'
    year_level = entry.get('year_level') or 'Unknown year level'
    stage = entry.get('stage') or entry.get('course_code') or 'Unassigned stage/event'
    event_id = entry.get('pit_event_config_id')
    if not event_id and track == 'pit' and known_event_ids:
        event_id = known_event_ids.get(_event_cohort_key(entry))
    stage_id = f'event:{event_id}' if track == 'pit' and event_id else f'label:{stage}'
    team_id = entry.get('team_id')
    team_name = entry.get('team_name') or 'Unmatched records'
    team_key = f'id:{team_id}' if team_id else f'name:{team_name}'
    # The common hierarchy keeps every browsing mode inside its academic context.
    # Include the track in stage keys so similarly named PIT/Capstone records stay separate.
    parents = [
        (json.dumps(['academic_year', year]), year, 'Academic period'),
        (json.dumps(['semester', semester]), semester, 'Semester'),
        (json.dumps(['year_level', year_level]), year_level, 'Year level'),
        (json.dumps(['stage', track, stage_id]), stage,
         'PIT event' if track == 'pit' else 'Capstone stage'),
    ]
    if group_by == 'stage':
        return parents
    if group_by == 'team':
        return parents + [(json.dumps(['team', team_key]), team_name, year_level)]
    deliverable_id = entry.get('deliverable_id') or 'archive-files'
    deliverable_label = entry.get('deliverable_label') or 'Archive files'
    if deliverable_id == 'archive-files':
        deliverable_label = 'Archive files'
    return parents + [
        (json.dumps(['deliverable', deliverable_id]), deliverable_label, stage),
    ]


def entries_in_folder(entries, group_by='team', folder_key=''):
    """Return the records under a folder, including records in child folders."""
    group_by = group_by if group_by in GROUP_BY_CHOICES else 'team'
    path = _decode_path(folder_key)
    if path is None:
        path = []
    if not path:
        return entries
    candidates = entries if group_by == 'deliverable' else _file_entries(entries)
    known = _known_pit_event_ids(candidates)
    return [
        entry for entry in candidates
        if [segment[0] for segment in _segments(entry, group_by, known)[:len(path)]] == path
    ]


def archive_folder_payload(entries, group_by='team', folder_key=''):
    group_by = group_by if group_by in GROUP_BY_CHOICES else 'team'
    selected_path = _decode_path(folder_key)
    if selected_path is None:
        selected_path = []
    candidates = entries if group_by == 'deliverable' else _file_entries(entries)
    known = _known_pit_event_ids(candidates)
    indexed = [(entry, _segments(entry, group_by, known)) for entry in candidates]
    matching = [
        (entry, segments) for entry, segments in indexed
        if [segment[0] for segment in segments[:len(selected_path)]] == selected_path
    ]
    depth = len(selected_path)
    breadcrumbs = []
    if matching:
        for index in range(depth):
            segments = matching[0][1]
            breadcrumbs.append({
                'title': segments[index][1],
                'key': _encode_path(selected_path[:index + 1]),
            })
    else:
        # Empty terms still need a route back to the academic-period directory.
        for index, dimension in enumerate(('academic_year', 'semester', 'year_level')):
            if index >= depth:
                break
            try:
                segment = json.loads(selected_path[index])
            except (ValueError, TypeError):
                break
            if (not isinstance(segment, list) or len(segment) != 2
                    or segment[0] != dimension or not isinstance(segment[1], str)):
                break
            breadcrumbs.append({
                'title': segment[1],
                'key': _encode_path(selected_path[:index + 1]),
            })
    is_leaf = bool(matching) and depth >= len(matching[0][1])
    folders = {}
    if not is_leaf:
        for entry, segments in matching:
            if depth >= len(segments):
                continue
            key, title, subtitle = segments[depth]
            folder = folders.setdefault(key, {
                'key': _encode_path(selected_path + [key]),
                'title': title,
                'subtitle': subtitle,
                'file_count': 0,
                'missing_count': 0,
                'approved_count': 0,
                'needs_revision_count': 0,
            })
            if group_by == 'deliverable' and entry.get('is_missing'):
                folder['title'] = title
            if entry.get('has_file') and not entry.get('is_missing'):
                folder['file_count'] += 1
            elif entry.get('is_missing') or not entry.get('has_file'):
                folder['missing_count'] += 1
            if entry.get('status') == 'Approved':
                folder['approved_count'] += 1
            elif entry.get('status') == 'Needs Revision':
                folder['needs_revision_count'] += 1
    return {
        'group_by': group_by,
        'folder_key': _encode_path(selected_path) if selected_path else '',
        'breadcrumbs': breadcrumbs,
        'folders': sorted(folders.values(), key=lambda item: item['title'].casefold()),
        'is_leaf': is_leaf,
        'entries': [entry for entry, _ in matching] if is_leaf else [],
        'file_count': sum(1 for entry, _ in matching if entry.get('has_file') and not entry.get('is_missing')),
        'missing_count': sum(1 for entry, _ in matching if entry.get('is_missing') or not entry.get('has_file')),
    }
