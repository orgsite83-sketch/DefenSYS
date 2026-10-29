"""Shared pre-defense requirement, schedule lookup and file validation helpers."""
from defensys_backend.read_projection import read_memoize

def scheduling_requirement(definition):
    return definition.get('type') == 'pre' and definition.get('required')


@read_memoize(bypass_if=('lock',))
def stage_schedule(team, stage_label, *, active_only=False, lock=False):
    from defense.scheduler.models import DefenseSchedule

    schedules = DefenseSchedule.objects.filter(
        team=team, semester_id=team.semester_id, project_version=team.project_version,
        scope='capstone' if team.is_capstone else 'pit',
        status__in=['scheduled'] if active_only else ['scheduled', 'done', 'archived'],
    ).select_related('team', 'defense_stage', 'semester')
    if team.is_capstone:
        schedules = schedules.filter(defense_stage__label=stage_label)
    else:
        schedules = schedules.filter(event_name__iexact=stage_label)
    if lock:
        schedules = schedules.select_for_update(of=('self',))
    return schedules.order_by('-scheduled_date', '-start_time', '-pk').first()

def validate_material_file(definition, file_name, file):
    from pathlib import PurePath

    if file is None or not file.size:
        raise ValueError('Choose a nonempty file for this defense requirement.')
    formats = {
        'pdf': {'.pdf'}, 'presentation': {'.pptx', '.ppt', '.pdf'},
        'document': {'.docx', '.doc', '.pdf'}, 'spreadsheet': {'.xlsx', '.xls', '.csv'},
        'video': {'.mp4', '.mov', '.webm'}, 'image': {'.png', '.jpg', '.jpeg', '.svg'},
        'archive': {'.zip', '.rar', '.7z'}, 'audio': {'.mp3', '.wav', '.aac'},
    }
    extensions = formats.get(definition.get('file_format'))
    if extensions and (PurePath(file_name).suffix.lower() not in extensions or
                       PurePath(file.name).suffix.lower() not in extensions):
        raise ValueError('This deliverable requires a file in its configured format.')
