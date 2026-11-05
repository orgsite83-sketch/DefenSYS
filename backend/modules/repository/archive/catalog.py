"""Bounded catalog responses: stream one project's source data at a time.

The existing taxonomy/search and visibility rules remain authoritative. Full
text is never retained for the entire catalog or sent in card responses.
"""
import heapq
import hashlib
import json
from itertools import groupby

from django.conf import settings
from django.core.serializers.json import DjangoJSONEncoder
from django.db.models import Case, CharField, Exists, OuterRef, Prefetch, Value, When
from django.db.models.functions import Cast, Coalesce, Concat, MD5
from rest_framework.exceptions import NotFound, ValidationError

from defensys_backend.media_sessions import grant_cache
from repository.deliverables.models import DeliverableSubmissionFile
from repository.deliverables.services import definition_for
from .library import enrich_library_entry
from .public_taxonomy import VERSION, enrich_public_tags
from .ml_search import filter_and_rank_entries
from .services import (capstone_visible_queryset, pit_visible_deliverables_queryset,
                       pit_queryset, capstone_entry_payload, pit_entry_payload,
                       get_entry_review_stats, get_user_review_map, get_user_shelf_map)


def _key(queryset, kind=None):
    text = CharField()
    if kind:
        year = Coalesce('archive_semester__school_year__label', 'team__semester__school_year__label', Value(''), output_field=text)
        semester = Coalesce('archive_semester__label', 'team__semester__label', Value(''), output_field=text)
        prefix = Value(kind)
    else:
        year, semester, prefix = 'academic_year', 'semester_label', 'entry_type'
    key = Concat(prefix, Value(':'), Cast('team_id', text), Value(':'),
                 Cast('project_version', text), Value(':'), year, Value(':'), semester,
                 output_field=text)
    if not kind:
        key = Case(When(team_id__isnull=True, then=Concat(Value('entry:pit-'), Cast('pk', text))),
                   default=key, output_field=text)
    return queryset.annotate(_catalog_key=key)


def visible_projects(project_key=None):
    submissions = [capstone_visible_queryset(), pit_visible_deliverables_queryset()]
    legacy = pit_queryset().alias(
        _capstone=Exists(submissions[0].filter(team_id=OuterRef('team_id'), stage_label=OuterRef('stage_label'))),
        _pit=Exists(submissions[1].filter(team_id=OuterRef('team_id'), stage_label=OuterRef('stage_label'))),
    ).filter(_capstone=False, _pit=False)

    def stream(queryset, kind):
        queryset = _key(queryset, kind)
        # Hash text in PostgreSQL without copying entire manuscripts to Python
        # on a warm read. Changed text invalidates the cached project metadata.
        queryset = queryset.annotate(_catalog_text_hash=MD5('extracted_text')).defer('extracted_text')
        if kind:
            queryset = queryset.prefetch_related(None).prefetch_related(Prefetch('files',
                queryset=DeliverableSubmissionFile.objects.filter(is_current=True).annotate(
                    _catalog_text_hash=MD5('extracted_text')).defer('extracted_text')))
        if project_key is not None:
            queryset = queryset.filter(_catalog_key=project_key)
        for source in queryset.order_by('_catalog_key', 'pk').iterator(chunk_size=64):
            yield source._catalog_key, kind, source

    streams = [stream(submissions[0], 'capstone'), stream(submissions[1], 'pit'), stream(legacy, None)]
    merged = heapq.merge(*streams, key=lambda item: item[0])
    for key, rows in groupby(merged, key=lambda item: item[0]):
        sources = list(rows)
        fingerprint = []
        def fields(model):
            return {name: value for name, value in vars(model).items() if name != '_state' and name != '_prefetched_objects_cache'}
        for _, kind, source in sources:
            team = source.team
            context = [fields(source), fields(team) if team else None]
            if source.uploaded_by:
                context.append([source.uploaded_by.first_name, source.uploaded_by.last_name, source.uploaded_by.username])
            if kind:
                context += [[fields(file) for file in source.files.all()],
                            definition_for(team, source.stage_label, source.deliverable_id) or {}]
                semester = source.archive_semester or (team.semester if team else None)
                context.append([semester.label, semester.school_year.label] if semester else None)
            fingerprint.append(context)
        digest = hashlib.sha256(json.dumps([settings.SECRET_KEY, VERSION, fingerprint],
            cls=DjangoJSONEncoder, sort_keys=True).encode()).hexdigest()
        cache = grant_cache()
        cache_key = 'repository-project-v1:' + digest
        entries = cache.get(cache_key)
        if entries is not None:
            yield key, entries
            continue
        entries = [entry for _, kind, source in sources for entry in (
            capstone_entry_payload(source) if kind else [pit_entry_payload(source)])]
        for entry in entries:
            enrich_library_entry(entry)
        entries.sort(key=lambda item: (item['uploaded_at'], item['id']), reverse=True)
        if entries:
            enrich_public_tags(entries)
            entries = [_clean(entry) for entry in entries]
            cache.set(cache_key, entries, 3600)
            yield key, entries


def _clean(entry):
    # Overview is bounded by enrich_library_entry; original text stays server-side.
    cleaned = {key: value for key, value in entry.items() if key not in ('extracted_text', 'project_entries')}
    cleaned['summary'] = str(cleaned.get('summary') or '')[:3500]
    return cleaned


def deliverable_options(entries):
    result = {}
    for entry in entries:
        key = entry['deliverable_key'] or 'unassigned'
        option = result.setdefault(key, {'key': key, 'label': entry['deliverable_group_label'],
                                         'stage': entry.get('stage', ''), 'count': 0})
        option['count'] += 1
    return qualify_deliverables(sorted(result.values(), key=lambda item: (item['key'] == 'unassigned', item['label'].casefold(), item['key'])))


def qualify_deliverables(options):
    for option in options:
        same_label = [item for item in options if item['label'] == option['label']]
        option['display_label'] = option['label']
        if len(same_label) > 1:
            context = option['stage']
            if sum(item['stage'] == context for item in same_label) > 1 and option['key'] != 'unassigned':
                track, year, semester, stage, event, deliverable_id = json.loads(option['key'])
                context = ' · '.join(str(part) for part in (track, year, semester, stage,
                    f'Event {event}' if event else '', deliverable_id) if part)
            option['display_label'] += ' · ' + context
    return options


def catalog_payload(request):
    try:
        limit = min(60, max(1, int(request.query_params.get('limit', 24))))
        offset = max(0, int(request.query_params.get('offset', 0)))
    except (TypeError, ValueError):
        raise ValidationError('Invalid catalog page.')
    if offset > 5000:
        raise ValidationError('Refine the collection before paging further.')
    params = request.query_params.copy()
    if params.get('search'):
        raise ValidationError('Use the existing search endpoint for full-text search.')
    selected_deliverable = params.get('deliverable', '')
    facets, definitions, years = {group: {} for group in ('subject', 'technology', 'language')}, {}, set()
    total = 0

    def summaries():
        nonlocal total
        for key, entries in visible_projects():
            # Full taxonomy filters still see the full authorized project.
            years.update(entry.get('academic_year', '') for entry in entries if entry.get('academic_year'))
            for group in facets:
                # Each facet counts matching projects while excluding its own selection.
                scoped = params.copy()
                scoped.pop(group, None)
                scoped_entries, _ = filter_and_rank_entries(entries, scoped)
                tags = {tag['id']: tag for entry in scoped_entries
                        for tag in entry.get('library_tags', {}).get(group, [])}
                if scoped_entries and not tags:
                    tags['unspecified'] = {'id': 'unspecified', 'label': 'Not specified'}
                for tag in tags.values():
                    item = facets[group].setdefault(tag['id'], {**tag, 'projects': 0})
                    item['projects'] += 1
            matching, _ = filter_and_rank_entries(entries, params)
            if not matching:
                continue
            options = deliverable_options(entries)
            for item in options:
                facet = definitions.setdefault(item['key'], {**item, 'projects': 0})
                facet['projects'] += 1
            if selected_deliverable and not any(item['key'] == selected_deliverable for item in options):
                continue
            total += 1
            representative = _clean(entries[0])
            representative.update(catalog_summary=True, project_key=key,
                                  available_deliverables=options,
                                  project_output_count=len(entries))
            yield representative

    title_sort = params.get('sort') == 'title'
    def sort_key(item):
        return (item.get('display_title', '').casefold(), item['project_key']) if title_sort else (
            -item['uploaded_at'].timestamp(), item['project_key'])
    selected = heapq.nsmallest(offset + limit, summaries(), key=sort_key)[offset:offset + limit]
    ids = [item['id'] for item in selected]
    reviews = get_entry_review_stats(ids)
    user_reviews = get_user_review_map(request.user, ids)
    shelf = get_user_shelf_map(request.user, ids)
    for entry in selected:
        entry.update(reviews.get(entry['id'], {}), **user_reviews.get(entry['id'], {}))
        entry.update(shelf.get(entry['id'], {}))
    return {'entries': selected, 'catalog': True,
            'pagination': {'offset': offset, 'limit': limit, 'total': total, 'has_more': offset + limit < total},
            'counts': {'total': total, 'filtered': total},
            'options': {'topics': sorted(facets['subject'].values(), key=lambda x: x['label']),
                        'facets': {group: sorted(items.values(), key=lambda x: x['label']) for group, items in facets.items()},
                        'years': sorted(years, reverse=True),
                        'deliverables': qualify_deliverables(sorted(definitions.values(), key=lambda x: (x['label'], x['key'])))}}


def project_payload(request):
    key = request.query_params.get('project_key', '')
    if not key or len(key) > 1024:
        raise NotFound('Project not found.')
    project = next(visible_projects(key), None)
    if project is None:
        raise NotFound('Project not found.')
    _, entries = project
    return {'project_key': key, 'entries': [_clean(entry) for entry in entries],
            'deliverables': deliverable_options(entries)}
