from academic_period_management.models import SchoolYear
from defense.stages.models import DefenseStage
from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import display_name
from repository.entry_payloads import ml_fields_from

from django.db.models import Avg, Count
from .ml_search import filter_and_rank_entries
from .models import ArchiveEntry, RepositoryReview, UserBookShelf



CAPSTONE_VISIBLE_IDS = ['D4.1', 'D10', 'D17', 'D18', 'D19']
DEFAULT_YEAR_LEVELS = ['1st Year', '2nd Year', '3rd Year', '4th Year']

TYPE_OPTIONS = [
    {'value': '', 'label': 'All Types'},
    {'value': ArchiveEntry.TYPE_CAPSTONE, 'label': 'Capstone'},
    {'value': ArchiveEntry.TYPE_PIT, 'label': 'PIT'},
]


def active_defense_stage_options():
    return list(
        DefenseStage.objects.filter(is_active=True)
        .order_by('display_order', 'label')
        .values_list('label', flat=True)
    )


def pit_visible_deliverables_queryset():
    from defense.scheduler.models import PitEventDeliverable
    restricted_ids = PitEventDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return (
        DeliverableSubmission.objects.select_related(
            'team',
            'team__semester',
            'team__semester__school_year',
            'uploaded_by',
        )
        .prefetch_related('files')
        .filter(
            deliverable_type=DeliverableSubmission.TYPE_POST,
            team__level__icontains='PIT',
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )
        .exclude(
            deliverable_id__in=restricted_ids,
        )
        .order_by('-uploaded_at', 'file_name')
    )


def capstone_visible_queryset():
    from defense.stages.models import StageDeliverable
    restricted_ids = StageDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return (
        DeliverableSubmission.objects.select_related(
            'team',
            'team__semester',
            'team__semester__school_year',
            'uploaded_by',
        )
        .prefetch_related('files')
        .filter(
            deliverable_type=DeliverableSubmission.TYPE_POST,
            team__level__icontains='Capstone',
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )
        .exclude(
            deliverable_id__in=restricted_ids,
        )
        .order_by('-uploaded_at', 'file_name')
    )


def capstone_restricted_queryset():
    from defense.stages.models import StageDeliverable
    restricted_ids = StageDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return DeliverableSubmission.objects.prefetch_related('files').filter(
        deliverable_type=DeliverableSubmission.TYPE_POST,
        deliverable_id__in=restricted_ids,
        team__level__icontains='Capstone',
        status=DeliverableSubmission.STATUS_ACCEPTED,
    )


def pit_restricted_queryset():
    from defense.scheduler.models import PitEventDeliverable
    restricted_ids = PitEventDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)
    return DeliverableSubmission.objects.prefetch_related('files').filter(
        deliverable_type=DeliverableSubmission.TYPE_POST,
        deliverable_id__in=restricted_ids,
        team__level__icontains='PIT',
        status=DeliverableSubmission.STATUS_ACCEPTED,
    )


def pit_queryset():
    return ArchiveEntry.objects.select_related('team', 'uploaded_by').filter(
        entry_type=ArchiveEntry.TYPE_PIT,
    )


def visible_archive_entries_count():
    return pit_queryset().count() + capstone_visible_queryset().count() + pit_visible_deliverables_queryset().count()


def capstone_visible_entries_count():
    return capstone_visible_queryset().count()


def pit_archive_entries_count():
    return pit_queryset().count() + pit_visible_deliverables_queryset().count()


def restricted_archive_entries_count():
    return capstone_restricted_queryset().count() + pit_restricted_queryset().count()


def capstone_entry_payload(submission):
    team = submission.team
    is_pit = team.is_pit if team else False
    entry_type = ArchiveEntry.TYPE_PIT if is_pit else ArchiveEntry.TYPE_CAPSTONE
    viewer_notice = (
        'Read-only PIT archive preview. Audit actions are handled in the Repository Audit phase.'
        if is_pit
        else 'Read-only archive preview. Source downloads are disabled from this public archive.'
    )
    
    files = list(submission.files.all().order_by('uploaded_at'))
    if not files:
        entry_id = f'pit-deliverable-{submission.id}' if is_pit else f'capstone-{submission.id}'
        return [{
            'id': entry_id,
            'source_id': submission.id,
            'file_id': None,
            'type': entry_type,
            'file_name': submission.file_name,
            'file_size': submission.file_size,
            'file_url': submission.file_url,
            'deliverable_id': submission.deliverable_id,
            'deliverable_label': submission.label,
            'team_id': team.id if team else None,
            'team_name': team.name if team else '',
            'project_title': team.project_title if team else '',
            'year_level': team.year_level if team else '',
            'academic_year': team.semester.school_year.label if team and team.semester else '',
            'semester': team.semester.label if team and team.semester else '',
            'stage': submission.stage_label,
            'status': 'Post-Defense' if not is_pit else submission.status,
            'uploaded_by': display_name(submission.uploaded_by) or 'System',
            'uploaded_at': submission.uploaded_at,
            'restricted': False,
            'viewer_notice': viewer_notice,
            'extracted_text': submission.extracted_text or '',
            'topics': submission.topics or [],
            'summary': submission.summary or '',
            'category': submission.category or '',
            'category_confidence': submission.category_confidence,
        }]

    payloads = []
    for f in files:
        entry_id = f'pit-deliverable-{submission.id}-{f.id}' if is_pit else f'capstone-{submission.id}-{f.id}'
        payloads.append({
            'id': entry_id,
            'source_id': submission.id,
            'file_id': f.id,
            'type': entry_type,
            'file_name': f.file_name,
            'file_size': f.file_size,
            'file_url': f.file.url if f.file else None,
            'deliverable_id': submission.deliverable_id,
            'deliverable_label': submission.label,
            'team_id': team.id if team else None,
            'team_name': team.name if team else '',
            'project_title': team.project_title if team else '',
            'year_level': team.year_level if team else '',
            'academic_year': team.semester.school_year.label if team and team.semester else '',
            'semester': team.semester.label if team and team.semester else '',
            'stage': submission.stage_label,
            'status': 'Post-Defense' if not is_pit else submission.status,
            'uploaded_by': display_name(submission.uploaded_by) or 'System',
            'uploaded_at': f.uploaded_at,
            'restricted': False,
            'viewer_notice': viewer_notice,
            'extracted_text': f.extracted_text or '',
            'topics': f.topics or [],
            'summary': f.summary or '',
            'category': f.category or '',
            'category_confidence': f.category_confidence,
        })
    return payloads


def pit_entry_payload(entry):
    return {
        'id': f'pit-{entry.id}',
        'source_id': entry.id,
        'type': ArchiveEntry.TYPE_PIT,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': entry.file_url,  # Add file URL for PIT entries
        'deliverable_id': '',
        'deliverable_label': entry.file_name,
        'team_id': entry.team_id,
        'team_name': entry.team_name or (entry.team.name if entry.team else 'Unmatched'),
        'project_title': entry.metadata.get('project_title', '') if isinstance(entry.metadata, dict) else '',
        'year_level': entry.year_level,
        'academic_year': entry.academic_year,
        'semester': entry.semester_label,
        'stage': entry.stage_label or entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'PIT Lead',
        'uploaded_at': entry.uploaded_at,
        'restricted': False,
        'viewer_notice': 'Read-only PIT archive preview. Audit actions are handled in the Repository Audit phase.',
        **ml_fields_from(entry),
    }


def get_entry_review_stats(target_ids=None):
    qs = RepositoryReview.objects.all()
    if target_ids is not None:
        qs = qs.filter(target_id__in=target_ids)
    
    stats_map = {}
    for row in qs.values('target_id').annotate(
        avg_rating=Avg('rating'),
        total_ratings=Count('id'),
    ):
        target_id = row['target_id']
        stats_map[target_id] = {
            'average_rating': round(row['avg_rating'] or 0.0, 1),
            'ratings_count': row['total_ratings'],
            'reviews_count': 0,
        }
    
    for row in qs.exclude(remark='').values('target_id').annotate(
        total_remarks=Count('id')
    ):
        target_id = row['target_id']
        if target_id in stats_map:
            stats_map[target_id]['reviews_count'] = row['total_remarks']
        else:
            stats_map[target_id] = {
                'average_rating': 0.0,
                'ratings_count': 0,
                'reviews_count': row['total_remarks'],
            }

    return stats_map


def get_user_shelf_map(user, target_ids=None):
    if not user or not getattr(user, 'is_authenticated', False):
        return {}
    qs = UserBookShelf.objects.filter(user=user)
    if target_ids is not None:
        qs = qs.filter(target_id__in=target_ids)
    return {
        item.target_id: {
            'shelf_status': item.status,
            'last_read_page': item.last_read_page,
            'total_pages': item.total_pages,
            'reading_progress': item.progress_percent,
        }
        for item in qs
    }


def get_user_review_map(user, target_ids=None):
    if not user or not getattr(user, 'is_authenticated', False):
        return {}
    qs = RepositoryReview.objects.filter(user=user)
    if target_ids is not None:
        qs = qs.filter(target_id__in=target_ids)
    return {
        item.target_id: {
            'user_rating': item.rating,
            'user_remark': item.remark,
        }
        for item in qs
    }


def all_visible_entries(user=None):
    submissions = list(capstone_visible_queryset()) + list(pit_visible_deliverables_queryset())
    submission_keys = {(s.team_id, s.stage_label) for s in submissions if s.team_id and s.stage_label}

    pit_entries = []
    for entry in pit_queryset():
        if entry.team_id and entry.stage_label and (entry.team_id, entry.stage_label) in submission_keys:
            continue
        pit_entries.append(entry)

    entries = [pit_entry_payload(entry) for entry in pit_entries]
    for submission in submissions:
        entries.extend(capstone_entry_payload(submission))
    
    # Enrich with review & shelf metadata
    review_stats = get_entry_review_stats()
    shelf_map = get_user_shelf_map(user)
    user_reviews = get_user_review_map(user)

    for entry in entries:
        tid = entry.get('id', '')
        stats = review_stats.get(tid, {})
        entry['average_rating'] = stats.get('average_rating', 0.0)
        entry['ratings_count'] = stats.get('ratings_count', 0)
        entry['reviews_count'] = stats.get('reviews_count', 0)
        
        user_rev = user_reviews.get(tid, {})
        entry['user_rating'] = user_rev.get('user_rating')
        entry['user_remark'] = user_rev.get('user_remark')
        
        shelf_info = shelf_map.get(tid, {})
        entry['shelf_status'] = shelf_info.get('shelf_status')
        entry['last_read_page'] = shelf_info.get('last_read_page', 1)
        entry['total_pages'] = shelf_info.get('total_pages', 1)
        entry['reading_progress'] = shelf_info.get('reading_progress', 0.0)

    return sorted(entries, key=lambda item: item.get('uploaded_at'), reverse=True)


def search_archive_payload(request):
    user = getattr(request, 'user', None)
    entries = all_visible_entries(user=user)
    filtered, suggestions = filter_and_rank_entries(entries, request.query_params)
    return {
        'entries': filtered,
        'suggestions': suggestions,
        'counts': counts_payload(entries, filtered),
        'filters': {
            'search': request.query_params.get('search', ''),
            'type': request.query_params.get('type', ''),
            'year_level': request.query_params.get('year_level', ''),
            'stage': request.query_params.get('stage', ''),
            'academic_year': request.query_params.get('academic_year', ''),
        },
    }


def options_payload(entries):
    year_levels = sorted({entry['year_level'] for entry in entries if entry.get('year_level')})
    stages = sorted({entry['stage'] for entry in entries if entry.get('stage')})
    academic_years = {entry['academic_year'] for entry in entries if entry.get('academic_year')}
    academic_years.update(SchoolYear.objects.values_list('label', flat=True))
    return {
        'type_options': TYPE_OPTIONS,
        'year_levels': sorted(set(DEFAULT_YEAR_LEVELS + year_levels)),
        'stage_options': sorted(set(active_defense_stage_options() + stages)),
        'academic_years': sorted(academic_years, reverse=True),
    }


def counts_payload(entries, filtered_entries):
    return {
        'total': len(entries),
        'filtered': len(filtered_entries),
        'capstone': sum(1 for entry in entries if entry['type'] == ArchiveEntry.TYPE_CAPSTONE),
        'pit': sum(1 for entry in entries if entry['type'] == ArchiveEntry.TYPE_PIT),
        'restricted': restricted_archive_entries_count(),
    }


def project_archive_payload(request):
    user = getattr(request, 'user', None)
    entries = all_visible_entries(user=user)
    
    filtered_entries, suggestions = filter_and_rank_entries(entries, request.query_params)
    
    from defense.stages.models import StageDeliverable
    from defense.scheduler.models import PitEventDeliverable
    restricted_ids = list(StageDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True)) + \
                     list(PitEventDeliverable.objects.filter(is_restricted=True).values_list('deliverable_id', flat=True))
                     
    return {
        'entries': filtered_entries,
        'suggestions': suggestions,
        'counts': counts_payload(entries, filtered_entries),
        'options': options_payload(entries),
        'filters': {
            'search': request.query_params.get('search', ''),
            'type': request.query_params.get('type', ''),
            'year_level': request.query_params.get('year_level', ''),
            'stage': request.query_params.get('stage', ''),
            'academic_year': request.query_params.get('academic_year', ''),
        },
        'restricted_deliverable_ids': restricted_ids,
        'notice': 'Repository is read-only. Restricted deliverables are intentionally hidden.',
    }


def get_reviews_payload_for_target(target_id, user=None):
    reviews = list(RepositoryReview.objects.filter(target_id=target_id).order_by('-created_at'))
    
    total_ratings = len(reviews)
    avg_rating = round(sum(r.rating for r in reviews) / total_ratings, 1) if total_ratings > 0 else 0.0
    
    distribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0}
    for r in reviews:
        if r.rating in distribution:
            distribution[r.rating] += 1
            
    user_review = None
    if user and getattr(user, 'is_authenticated', False):
        for r in reviews:
            if r.user_id == user.id:
                user_review = {
                    'id': r.id,
                    'rating': r.rating,
                    'remark': r.remark,
                    'user_name': r.user_name,
                    'user_role': r.user_role,
                    'created_at': r.created_at.isoformat(),
                    'updated_at': r.updated_at.isoformat(),
                }
                break

    reviews_list = [
        {
            'id': r.id,
            'user_id': r.user_id,
            'user_name': r.user_name,
            'user_role': r.user_role,
            'rating': r.rating,
            'remark': r.remark,
            'created_at': r.created_at.isoformat(),
            'updated_at': r.updated_at.isoformat(),
            'is_owner': getattr(user, 'is_authenticated', False) and r.user_id == user.id if user else False,
        }
        for r in reviews if r.remark.strip() or r.rating > 0
    ]

    return {
        'target_id': target_id,
        'average_rating': avg_rating,
        'ratings_count': total_ratings,
        'reviews_count': len([r for r in reviews if r.remark.strip()]),
        'distribution': distribution,
        'user_review': user_review,
        'reviews': reviews_list,
    }


def save_user_review(user, target_id, rating, remark=''):
    try:
        rating = int(rating)
    except (ValueError, TypeError):
        rating = 5
    if rating < 1: rating = 1
    if rating > 5: rating = 5
    
    review, _ = RepositoryReview.objects.update_or_create(
        target_id=target_id,
        user=user,
        defaults={
            'rating': rating,
            'remark': str(remark or '').strip(),
        }
    )
    return get_reviews_payload_for_target(target_id, user=user)


def delete_user_review(user, review_id):
    deleted_count, _ = RepositoryReview.objects.filter(id=review_id, user=user).delete()
    return deleted_count > 0


def get_user_shelf_payload(user):
    if not user or not getattr(user, 'is_authenticated', False):
        return {'items': []}
    
    shelf_items = list(UserBookShelf.objects.filter(user=user).order_by('-updated_at'))
    return {
        'items': [
            {
                'id': item.id,
                'target_id': item.target_id,
                'status': item.status,
                'last_read_page': item.last_read_page,
                'total_pages': item.total_pages,
                'progress_percent': item.progress_percent,
                'updated_at': item.updated_at.isoformat(),
            }
            for item in shelf_items
        ]
    }


def update_user_shelf(user, target_id, status=None, last_read_page=None, total_pages=None, progress_percent=None):
    defaults = {}
    if status is not None:
        defaults['status'] = status
    if last_read_page is not None:
        try:
            defaults['last_read_page'] = max(1, int(last_read_page))
        except (ValueError, TypeError):
            pass
    if total_pages is not None:
        try:
            defaults['total_pages'] = max(1, int(total_pages))
        except (ValueError, TypeError):
            pass
    if progress_percent is not None:
        try:
            defaults['progress_percent'] = min(100.0, max(0.0, float(progress_percent)))
        except (ValueError, TypeError):
            pass
    elif 'last_read_page' in defaults and 'total_pages' in defaults and defaults['total_pages'] > 0:
        defaults['progress_percent'] = round((defaults['last_read_page'] / defaults['total_pages']) * 100.0, 1)

    item, _ = UserBookShelf.objects.update_or_create(
        user=user,
        target_id=target_id,
        defaults=defaults,
    )
    return {
        'id': item.id,
        'target_id': item.target_id,
        'status': item.status,
        'last_read_page': item.last_read_page,
        'total_pages': item.total_pages,
        'progress_percent': item.progress_percent,
        'updated_at': item.updated_at.isoformat(),
    }

