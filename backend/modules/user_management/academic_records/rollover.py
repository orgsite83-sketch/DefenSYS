from academic_period_management.models import Semester

from .models import StudentAcademicRecord


YEAR_LEVELS = [
    StudentAcademicRecord.FIRST_YEAR,
    StudentAcademicRecord.SECOND_YEAR,
    StudentAcademicRecord.THIRD_YEAR,
    StudentAcademicRecord.FOURTH_YEAR,
]


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


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


def latest_records_by_student():
    records = (
        StudentAcademicRecord.objects.select_related('student', 'semester', 'semester__school_year')
        .order_by('student_id', '-created_at', '-id')
    )
    latest = {}
    for record in records:
        latest.setdefault(record.student_id, record)
    return list(latest.values())


def rollover_target_semester(record, target_school_year, action):
    if action == StudentAcademicRecord.ACTION_RETAIN:
        year_level = record.year_level
        semester_label = record.semester.label
    else:
        year_level, semester_label = next_academic_step(record.year_level, record.semester.label)

    if action != StudentAcademicRecord.ACTION_RETAIN and record.semester.label == Semester.FIRST:
        school_year = record.semester.school_year
    else:
        school_year = target_school_year

    semester = Semester.objects.filter(school_year=school_year, label=semester_label).first()
    return year_level, semester_label, semester
