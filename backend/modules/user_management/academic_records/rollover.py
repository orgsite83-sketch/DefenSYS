from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Case, IntegerField, Q, Value, When
from rest_framework.exceptions import ValidationError

from academic_period_management.capstone_mode import sync_capstone_flags_after_rollover
from academic_period_management.models import Semester
from academic_period_management.services import active_semester
from student_teams.models import StudentTeam

from .models import StudentAcademicRecord


YEAR_LEVELS = [
    StudentAcademicRecord.FIRST_YEAR,
    StudentAcademicRecord.SECOND_YEAR,
    StudentAcademicRecord.THIRD_YEAR,
    StudentAcademicRecord.FOURTH_YEAR,
]


def next_academic_step(year_level, semester_label):
    if semester_label == Semester.FIRST:
        return year_level, Semester.SECOND

    try:
        index = YEAR_LEVELS.index(year_level)
    except ValueError:
        return year_level, Semester.FIRST

    if index >= len(YEAR_LEVELS) - 1:
        return year_level, Semester.FIRST

    return YEAR_LEVELS[index + 1], Semester.FIRST


TERM_ORDER = {Semester.FIRST: 1, Semester.SECOND: 2, Semester.SUMMER: 3}


def semester_key(semester):
    return semester.school_year.label, TERM_ORDER[semester.label]


def clean_spaces(value):
    return ' '.join((value or '').strip().split())


def normalize_year_level(value):
    value = clean_spaces(value)
    for number, year in enumerate(YEAR_LEVELS, start=1):
        if value.casefold() in (str(number), year.casefold(), year.split()[0].casefold()):
            return year
    return value


def latest_records_by_student(student_ids=None):
    records = (
        StudentAcademicRecord.objects.select_related('student', 'semester', 'semester__school_year')
        .annotate(term_order=Case(
            *[When(semester__label=label, then=Value(rank)) for label, rank in TERM_ORDER.items()],
            output_field=IntegerField(), default=Value(0),
        ))
        .order_by('student_id', '-semester__school_year__label', '-term_order', '-created_at', '-id')
    )
    if student_ids is not None:
        records = records.filter(student_id__in=student_ids)
    latest = {}
    for record in records:
        latest.setdefault(record.student_id, record)
    return list(latest.values())


def next_rollover_semester(record):
    year_level, semester_label = next_academic_step(record.year_level, record.semester.label)
    school_year_label = record.semester.school_year.label
    if record.semester.label != Semester.FIRST:
        start, end = map(int, school_year_label.split('-'))
        school_year_label = f'{start + 1}-{end + 1}'
    semester = Semester.objects.select_related('school_year').filter(
        school_year__label=school_year_label, label=semester_label,
    ).first()
    return year_level, semester_label, semester


def advance_capstone_teams(target, selected_sources):
    """Carry selected, fully enrolled rosters forward one school year only."""
    if target.label != Semester.FIRST or not selected_sources:
        return 0
    selection = Q(pk__in=[])
    for source_id, student_ids in selected_sources.items():
        selection |= Q(semester_id=source_id) & (
            Q(leader_id__in=student_ids) | Q(memberships__student_id__in=student_ids))
    start, end = map(int, target.school_year.label.split('-'))
    previous_year = f'{start - 1}-{end - 1}'
    teams = (
        StudentTeam.objects.select_for_update(of=('self',))
        .filter(level__in=[StudentTeam.LEVEL_3_CAPSTONE, StudentTeam.LEVEL_4_CAPSTONE],
                semester__label=Semester.SECOND, semester__school_year__label=previous_year)
        .filter(selection)
        .select_related('semester').prefetch_related('memberships').order_by('pk')
    )
    enrolled = set(StudentAcademicRecord.objects.filter(
        semester=target, year_level=StudentAcademicRecord.FOURTH_YEAR,
    ).values_list('student_id', flat=True))
    updates = 0
    seen = set()
    for team in teams:
        if team.pk in seen:
            continue
        seen.add(team.pk)
        roster = {membership.student_id for membership in team.memberships.all()} | {team.leader_id}
        if not roster.issubset(enrolled):
            continue
        from student_teams.capstone_lifecycle import continue_enrolled_normal_team
        updates += int(continue_enrolled_normal_team(team, target))
    sync_capstone_flags_after_rollover(target, updates)
    return updates


@transaction.atomic
def confirm_rollover(actions, default_semester):
    """Validate and save the whole batch together, including accounts and teams."""
    list(Semester.objects.select_for_update().order_by('pk'))
    User = get_user_model()
    records = {record.pk: record for record in StudentAcademicRecord.objects.filter(
        pk__in=[item['record_id'] for item in actions if item.get('record_id')],
    ).select_related('student', 'semester__school_year')}
    # Serialize retries for existing students before checking target duplicates.
    users = list(User.objects.select_for_update().filter(
        Q(pk__in=[record.student_id for record in records.values()]) |
        Q(username__in=[item['username'] for item in actions if item.get('username')]),
    ).order_by('pk'))
    users_by_name = {user.username: user for user in users}
    records = {record.pk: record for record in StudentAcademicRecord.objects.select_for_update(of=('self',))
               .filter(pk__in=records).select_related('student', 'semester__school_year').order_by('pk')}
    latest = {record.student_id: record for record in latest_records_by_student([user.pk for user in users])}
    target_ids_by_row = []
    for item in actions:
        if 'target_semester_id' in item:
            target_ids_by_row.append(item['target_semester_id'])
            continue
        source = records.get(item.get('record_id'))
        user = users_by_name.get(item.get('username'))
        source = source or (latest.get(user.pk) if user else None)
        if source and item['action'] not in ('drop', 'create'):
            next_target = next_rollover_semester(source)[2]
            target_ids_by_row.append(next_target.pk if next_target else None)
        else:
            target_ids_by_row.append(default_semester.pk)
    targets = {semester.pk: semester for semester in Semester.objects.select_for_update(of=('self',)).filter(
        pk__in=target_ids_by_row,
    ).select_related('school_year').order_by('pk')}
    created, skipped = [], []
    selected_by_target = {}
    seen = set()

    for index, item in enumerate(actions):
        def invalid(message):
            raise ValidationError({'actions': {index: message}})

        action = item['action']
        if action == 'drop':
            skipped.append({'record_id': item.get('record_id'), 'username': item.get('username'), 'reason': 'dropped'})
            continue
        target_id = target_ids_by_row[index]
        if target_id is None:
            invalid('Target semester is not configured. Refresh the rollover preview.')
        target = targets.get(target_id)
        if target is None:
            invalid('Target semester does not exist. Refresh the rollover preview.')
        record = records.get(item.get('record_id'))
        if item.get('record_id') and record is None:
            invalid('Source academic record does not exist. Refresh the rollover preview.')
        username = clean_spaces(item.get('username'))
        if record and username and username != record.student.username:
            invalid('Student ID does not match the source academic record.')
        user = users_by_name.get(record.student.username if record else username)
        if user and (user.role != 'student' or not user.is_active):
            invalid('Rollover requires an active student account.')
        if user is None and action != 'create':
            invalid('Student does not exist. Use Create for a new student.')
        if user and record is None:
            record = latest.get(user.pk)
        identity = user.username if user else username
        if identity in seen:
            invalid('Student appears more than once in the rollover batch.')
        seen.add(identity)
        if user and StudentAcademicRecord.objects.filter(student=user, semester=target).exists():
            skipped.append({'username': user.username, 'reason': 'duplicate'})
            continue
        if record:
            if semester_key(target) <= semester_key(record.semester):
                invalid('Target semester must be after the source academic period.')
            if latest[user.pk].pk != record.pk:
                invalid('Student has a newer academic record. Refresh the rollover preview.')
        if action == 'retain':
            if record is None:
                invalid('Retain requires an existing academic record.')
            target_year, target_section = record.year_level, record.section
        else:
            target_year = normalize_year_level(item.get('year_level'))
            if not target_year:
                if record:
                    target_year, _, expected_target = next_rollover_semester(record)
                    if expected_target is None or expected_target.pk != target.pk:
                        invalid('Specify the official enrollment year level for this target semester.')
                else:
                    target_year = YEAR_LEVELS[0]
            target_section = clean_spaces(item.get('section')) if 'section' in item else (record.section if record else '')
        if target_year not in YEAR_LEVELS:
            invalid('Year level must be 1st Year, 2nd Year, 3rd Year or 4th Year.')
        if user is None:
            if not username or not (clean_spaces(item.get('first_name')) or clean_spaces(item.get('last_name'))):
                invalid('New students require a student ID and name.')
            user = User.objects.create_user(
                username=username, password=username,
                first_name=clean_spaces(item.get('first_name')), last_name=clean_spaces(item.get('last_name')),
                email=clean_spaces(item.get('email')), role='student',
            )
            users_by_name[username] = user
        created.append(StudentAcademicRecord.objects.create(
            student=user, semester=target, year_level=target_year, section=target_section,
            action=StudentAcademicRecord.ACTION_MANUAL if action == 'create' else action,
            rolled_from=record,
        ))
        if record:
            selected_by_target.setdefault(target.pk, {}).setdefault(record.semester_id, set()).add(user.pk)

    team_updates = sum(advance_capstone_teams(targets[target_id], student_ids)
                       for target_id, student_ids in sorted(selected_by_target.items()))
    return created, skipped, team_updates
