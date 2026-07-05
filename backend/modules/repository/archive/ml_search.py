"""Shared vault search haystack, ranking, and autocomplete suggestions."""

from typing import Any, Dict, List, Tuple


def entry_haystack(entry: Dict[str, Any]) -> str:
    parts = [
        entry.get('file_name'),
        entry.get('deliverable_id'),
        entry.get('deliverable_label'),
        entry.get('team_name'),
        entry.get('project_title'),
        entry.get('stage'),
        entry.get('course_code'),
        entry.get('uploaded_by'),
        entry.get('extracted_text'),
        entry.get('summary'),
        entry.get('category'),
        entry.get('year_level'),
        entry.get('academic_year'),
    ]
    topics = entry.get('topics') or []
    if topics:
        parts.append(' '.join(str(topic) for topic in topics))
    return ' '.join(str(part) for part in parts if part).lower()


def matches_search(entry: Dict[str, Any], search: str) -> bool:
    if not search:
        return True
    query = search.lower().strip()
    return query in entry_haystack(entry)


def score_entry(entry: Dict[str, Any], search: str) -> float:
    query = (search or '').lower().strip()
    if not query:
        return 0.0

    haystack = entry_haystack(entry)
    words = [word for word in query.split() if len(word) >= 2]
    score = 0.0

    if query in haystack:
        score += 30.0

    for word in words:
        if word in haystack:
            score += 12.0
        if word in (entry.get('file_name') or '').lower():
            score += 8.0
        if word in (entry.get('team_name') or '').lower():
            score += 6.0
        category = (entry.get('category') or '').lower()
        if category and word in category:
            score += 18.0
        for topic in entry.get('topics') or []:
            topic_text = str(topic).lower()
            if word in topic_text:
                score += 14.0
            if topic_text in query or query in topic_text:
                score += 6.0

    return score


def build_suggestions(
    entries: List[Dict[str, Any]],
    search: str,
    *,
    limit: int = 8,
) -> List[Dict[str, Any]]:
    query = (search or '').strip().lower()
    if len(query) < 2:
        return []

    seen = set()
    suggestions: List[Dict[str, Any]] = []

    def add(label: str, suggestion_type: str, entry_id: str):
        key = (suggestion_type, label.lower(), entry_id)
        if key in seen or not label:
            return
        seen.add(key)
        suggestions.append({
            'label': label,
            'type': suggestion_type,
            'entry_id': entry_id,
        })

    ranked = sorted(
        ((score_entry(entry, query), entry) for entry in entries),
        key=lambda item: item[0],
        reverse=True,
    )

    for _score, entry in ranked:
        if len(suggestions) >= limit:
            break
        entry_id = str(entry.get('id') or '')
        category = (entry.get('category') or '').strip()
        if category and query in category.lower():
            add(category, 'category', entry_id)
        for topic in entry.get('topics') or []:
            topic_text = str(topic).strip()
            if topic_text and query in topic_text.lower():
                add(topic_text, 'topic', entry_id)
        team_name = (entry.get('team_name') or '').strip()
        if team_name and query in team_name.lower():
            add(team_name, 'team', entry_id)
        file_name = (entry.get('file_name') or '').strip()
        if file_name and query in file_name.lower():
            add(file_name, 'file', entry_id)

    return suggestions[:limit]


def filter_and_rank_entries(
    entries: List[Dict[str, Any]],
    query_params,
    *,
    extra_filters=None,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Apply standard filters; rank by ML haystack score when search is set."""
    search = (query_params.get('search') if hasattr(query_params, 'get') else '') or ''
    if hasattr(search, 'strip'):
        search = search.strip()
    else:
        search = str(search).strip()

    filtered = []
    for entry in entries:
        if extra_filters and not extra_filters(entry, query_params):
            continue
        if not _apply_standard_filters(entry, query_params):
            continue
        if search and not matches_search(entry, search):
            continue
        filtered.append(entry)

    suggestions = build_suggestions(entries, search) if search else []

    if search:
        filtered.sort(
            key=lambda item: (score_entry(item, search), item.get('uploaded_at')),
            reverse=True,
        )

    return filtered, suggestions


def _apply_standard_filters(entry: Dict[str, Any], query_params) -> bool:
    def get_param(key):
        if hasattr(query_params, 'get'):
            return (query_params.get(key) or '').strip()
        return ''

    entry_type = get_param('type')
    year_level = get_param('year_level')
    academic_year = get_param('academic_year')
    status = get_param('status')
    semester = get_param('semester')
    team_id = get_param('team_id')
    stage = get_param('stage')
    deliverable_id = get_param('deliverable_id')
    submission_kind = get_param('submission_kind')

    if entry_type and entry.get('type') != entry_type:
        return False
    if year_level and entry.get('year_level') != year_level:
        return False
    if academic_year and entry.get('academic_year') != academic_year:
        return False
    if status and entry.get('status') != status:
        return False
    if semester and entry.get('semester') != semester:
        return False
    if team_id and str(entry.get('team_id') or '') != team_id:
        return False
    if stage and entry.get('stage') != stage:
        return False
    if deliverable_id and (entry.get('deliverable_id') or '') != deliverable_id:
        return False
    if submission_kind and entry.get('submission_kind') != submission_kind:
        return False
    return True
