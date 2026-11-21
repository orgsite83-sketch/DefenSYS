"""Export authorized records using the editable team and timetable import layouts."""
from collections import defaultdict
from datetime import datetime, timedelta

from django.contrib.auth import get_user_model
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter
from rest_framework.exceptions import ValidationError

from defensys_backend.person_matching import DEFAULT_PERSON_NAMES, PersonNameIndex
from reports.document_workbooks import unique_sheet_name
from reports.export_formatters import _write_xlsx_signatories, _xlsx_workbook_response


def _references():
    """Use readable names only when the importer resolves the same account."""
    index = PersonNameIndex(get_user_model().objects.only(
        'id', 'username', 'first_name', 'last_name', 'role', 'is_active'), DEFAULT_PERSON_NAMES)

    def reference(person):
        if not person:
            return ''
        if isinstance(person, dict):
            label = person.get('name', '')
            username = person.get('username', '')
            person_id = person.get('student_id') or person.get('id')
        else:
            label, username, person_id = person.get_full_name().strip(), person.username, person.pk
        resolved = index.resolve(label) if label else None
        return label if resolved and resolved.user and resolved.user.pk == person_id else username or label

    return reference


def _context(teams):
    from student_teams.models import SectionAssignment
    from user_management.models import SectionInstructorAssignment
    terms = {team.semester_id for team in teams}
    sections = {team.section for team in teams}
    shared = {(item.semester_id, item.section): item for item in
              SectionAssignment.objects.filter(semester_id__in=terms, section__in=sections)
              .select_related('project_manager')}
    instructors = {(item.semester_id, item.year_level, item.section): item.faculty for item in
                   SectionInstructorAssignment.objects.filter(
                       semester_id__in=terms, section__in=sections, is_active=True).select_related('faculty')}
    return shared, instructors


def _sheet(workbook, label, widths, *, first_column=1, font='Arial'):
    sheet = workbook.create_sheet(unique_sheet_name(workbook, label))
    sheet.sheet_view.showGridLines = True
    sheet.sheet_view.zoomScale = 100
    sheet.sheet_properties.pageSetUpPr.fitToPage = True
    sheet.page_setup.orientation = 'landscape'
    sheet.page_setup.fitToWidth = 1
    sheet.page_setup.fitToHeight = 0
    for column, width in enumerate(widths, first_column):
        sheet.column_dimensions[get_column_letter(column)].width = width
    edge = Side(style='thin', color='000000')

    def cell(row, column, value='', *, centered=False):
        result = sheet.cell(row, column, value)
        # Imported titles and names can begin with '='; they are literal data.
        if isinstance(value, str):
            result.data_type = 's'
        result.font = Font(name=font, size=11, color='000000')
        result.alignment = Alignment(horizontal='center' if centered else 'left',
                                     vertical='center', wrap_text=True)
        result.border = Border(left=edge, right=edge, top=edge, bottom=edge)
        sheet.row_dimensions[row].height = max(sheet.row_dimensions[row].height or 18, 18)
        return result

    return sheet, cell


def _signatures(workbook, include_signatures, signatories, generated_by):
    if include_signatures:
        sheet = workbook.create_sheet('Signatories')
        sheet.column_dimensions['A'].width = 35
        sheet.column_dimensions['B'].width = 35
        sheet.cell(1, 2, '')
        _write_xlsx_signatories(sheet, signatories, generated_by)


def generate_team_import_xlsx(teams, filename, *, default_scope='capstone',
                              include_signatures=False, signatories=None, generated_by=''):
    """Five import columns, continuous member rows, leader first and real blanks."""
    from repository.section_concepts.redefense_direction import independent_team_ids
    workbook = Workbook()
    workbook.remove(workbook.active)
    reference = _references()
    shared, instructors = _context(teams)
    independent = set(independent_team_ids())
    groups = defaultdict(list)
    for team in teams:
        # Closed term snapshots must never acquire today's section configuration.
        assignment = None if hasattr(team, '_recorded_term') or team.pk in independent else shared.get(
            (team.semester_id, team.section))
        is_shared = bool(assignment and (assignment.system_name or assignment.project_manager_id))
        key = (team.semester_id, team.is_pit, team.section if is_shared else '', is_shared)
        groups[key].append((team, assignment))
    if not groups:
        groups[(None, default_scope == 'pit', '', False)] = []

    for (_, pit, section, is_shared), items in groups.items():
        label = f'{"PIT" if pit else "Capstone"} {section or "Teams"}'
        sheet, cell = _sheet(workbook, label, [28, 60, 18, 30, 30])
        header = 1
        if is_shared:
            assignment = items[0][1]
            cell(1, 1, 'System Name:')
            cell(1, 2, assignment.system_name)
            cell(2, 1, 'Project Manager:')
            cell(2, 2, reference(assignment.project_manager))
            header = 4
        headers = ['Team Name', 'Module' if is_shared else 'PIT Project' if pit else 'Capstone Project',
                   'Section', 'Instructor' if pit else 'Adviser', 'Team Members']
        for column, title in enumerate(headers, 1):
            cell(header, column, title)
        row = header + 1
        for team, _ in items:
            frozen = getattr(team, '_recorded_term', None)
            if frozen:
                snapshot = frozen.snapshot
                members = list(snapshot.get('members', []))
                leader_id = snapshot.get('leader_id')
                members.sort(key=lambda member: member.get('student_id') != leader_id)
                faculty = reference({'id': snapshot.get('adviser_id'),
                                     'name': snapshot.get('adviser_name', ''),
                                     'username': snapshot.get('adviser_username', '')})
            else:
                members_by_id = {membership.student_id: membership.student for membership in team.memberships.all()}
                # Some legacy leaders have no membership row. Keep the leader in the export.
                members_by_id.setdefault(team.leader_id, team.leader)
                members = [members_by_id.pop(team.leader_id), *members_by_id.values()]
                faculty = reference(instructors.get((team.semester_id, team.year_level, team.section))) if pit else reference(team.adviser)
            first = row
            for offset, member in enumerate(members or [None]):
                values = [team.name, team.project_title or '', team.section or '', faculty,
                          reference(member)]
                for column, value in enumerate(values, 1):
                    cell(row, column, value if offset == 0 or column == 5 else '')
                if offset == 0:
                    sheet.row_dimensions[row].height = min(150, max(20, 15 * (1 + len(team.project_title or '') // 55)))
                row += 1
            if row - first > 1:
                sheet.merge_cells(start_row=first, start_column=1, end_row=row - 1, end_column=1)
        sheet.freeze_panes = f'A{header + 1}'
        sheet.print_area = f'A1:E{max(header, row - 1)}'
    _signatures(workbook, include_signatures, signatories, generated_by)
    return _xlsx_workbook_response(workbook, filename)


def generate_schedule_import_xlsx(schedules, filename, *, default_scope='capstone',
                                  include_signatures=False, signatories=None, generated_by=''):
    """The same stage/date/room blocks and role columns as schedule intake."""
    workbook = Workbook()
    workbook.remove(workbook.active)
    reference = _references()
    _, instructors = _context([schedule.team for schedule in schedules])
    groups = defaultdict(list)
    for schedule in schedules:
        stage = schedule.defense_stage.label if schedule.defense_stage else schedule.event_name
        groups[(schedule.semester_id, schedule.scope, stage)].append(schedule)
    if not groups:
        groups[(None, default_scope, '')] = []

    for (_, scope, stage), items in groups.items():
        capstone = scope != 'pit'
        headers = ['#', 'Time', 'Team Name', 'Adviser' if capstone else 'Instructor',
                   'Panel Chair', 'Panel Member 1', 'Panel Member 2', 'Panel Member 3']
        if capstone:
            headers.append('Documenter')
        widths = [6, 27, 30, 28, 26, 26, 26, 26] + ([28] if capstone else [])
        sheet, cell = _sheet(workbook, f'{"Capstone" if capstone else "PIT"} {stage or "Schedule"}',
                             widths, first_column=4, font='Calibri')
        last_column = 3 + len(headers)
        row = 3

        def label(value, *, date_value=False):
            nonlocal row
            for column in range(4, last_column + 1):
                cell(row, column, value if column == 4 else '', centered=True)
            if date_value:
                sheet.cell(row, 4).number_format = 'm/d/yyyy'
            sheet.merge_cells(start_row=row, start_column=4, end_row=row, end_column=last_column)
            row += 1

        blocks = defaultdict(list)
        for schedule in items:
            blocks[(schedule.scheduled_date, schedule.room)].append(schedule)
        if not blocks:
            blocks[(None, '')] = []
        for (day, room), block in blocks.items():
            label(f'Stage: {stage}' if stage else 'Stage:')
            label(day or '', date_value=bool(day))
            label(f'Room: {room}' if room else 'Room:')
            for column, title in enumerate(headers, 4):
                cell(row, column, title)
            header = row
            row += 1
            for number, schedule in enumerate(sorted(block, key=lambda item: (item.start_time, item.pk)), 1):
                assignments = list(schedule.panel_assignments.all())
                chairs = [item for item in assignments if item.is_chair]
                members = [item for item in assignments if not item.is_chair]
                if len(chairs) > 1 or len(members) > 3:
                    raise ValidationError(f'{schedule.team.name} has panel assignments that do not fit the import template. '
                                          'Review the panel chair and members before exporting.')
                start = datetime.combine(schedule.scheduled_date, schedule.start_time)
                end = start + timedelta(minutes=schedule.slot_duration or 60)
                time_slot = f'{start:%I:%M %p} - {end:%I:%M %p}'
                faculty = schedule.team.adviser if capstone else instructors.get(
                    (schedule.semester_id, schedule.team.year_level, schedule.team.section))
                values = [number, time_slot, schedule.team.name, reference(faculty),
                          reference(chairs[0].panelist) if chairs else '',
                          *[reference(member.panelist) for member in members],
                          *[''] * (3 - len(members))]
                if capstone:
                    values.append(reference(schedule.documenter))
                for column, value in enumerate(values, 4):
                    cell(row, column, value)
                sheet.row_dimensions[row].height = 32
                row += 1
            # Merge only equal consecutive staff values, never across day blocks.
            for column in [7, *([12] if capstone else [])]:
                first = header + 1
                while first < row:
                    value = sheet.cell(first, column).value
                    end = first + 1
                    while value and end < row and sheet.cell(end, column).value == value:
                        end += 1
                    if end - first > 1:
                        sheet.merge_cells(start_row=first, start_column=column, end_row=end - 1, end_column=column)
                    first = end
            row += 1
        sheet.freeze_panes = 'D7'
        sheet.print_area = f'D3:{get_column_letter(last_column)}{max(6, row - 2)}'
    _signatures(workbook, include_signatures, signatories, generated_by)
    return _xlsx_workbook_response(workbook, filename)
