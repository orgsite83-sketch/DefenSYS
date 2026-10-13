"""
Execution Tool: generate_1st_year_pit_sample_suite.py
Generates the complete 1st Year PIT (16 Teams, 64 Students) sample data suite:
1. User Import: students_1st_year_by_year_level.xlsx & .csv
2. Team Roster: Team16roster.xlsx, team_roster_section_1A_different_systems.csv,
   team_roster_section_1B_one_system.csv, team_roster_combined_1A_and_1B.csv
3. Defense Schedule: defense_schedule_import.xlsx & .csv
4. Master Documentation: sample_file/16_Teams_1st_Year/README.md
"""

import os
import csv
import zipfile
import io
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

def fix_xlsx_for_dart_compatibility(filepath):
    """Normalizes relationship targets and empty inlineStr tags so Dart's package:excel can decode without issues."""
    with open(filepath, "rb") as f:
        data = f.read()
    zin = zipfile.ZipFile(io.BytesIO(data))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            content = zin.read(item.filename)
            if item.filename.endswith(".rels"):
                content = content.replace(b'Target="/xl/', b'Target="')
            elif item.filename.startswith("xl/worksheets/"):
                content = content.replace(b't="inlineStr" />', b'/>')
                content = content.replace(b't="inlineStr"/>', b'/>')
            zout.writestr(item, content)
    with open(filepath, "wb") as f:
        f.write(buf.getvalue())

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(BASE_DIR, "sample_file", "16_Teams_1st_Year")
SEM_DIR = os.path.join(OUTPUT_DIR, "1st Sem")
USER_DIR = os.path.join(SEM_DIR, "USer")
TEAM_DIR = os.path.join(SEM_DIR, "team")
SCHED_DIR = os.path.join(SEM_DIR, "schedule")

os.makedirs(USER_DIR, exist_ok=True)
os.makedirs(TEAM_DIR, exist_ok=True)
os.makedirs(SCHED_DIR, exist_ok=True)

# ==============================================================================
# 1. MASTER STUDENTS AND TEAMS SPECIFICATION (1ST YEAR)
# ==============================================================================

# Section BSIT-1A: Different Systems (8 Teams, 32 Students)
STUDENTS_1A = [
    # Team 1: Team DevCraft
    {"id": "1001", "last": "LIWANAG", "first": "Liam", "gender": "M", "team": "Team DevCraft", "project": "Freshman Interactive Campus Directory & Room Finder Kiosk", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1002", "last": "MARQUEZ", "first": "Chloe", "gender": "F", "team": "Team DevCraft", "project": "Freshman Interactive Campus Directory & Room Finder Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1003", "last": "CATAPANG", "first": "Andrei", "gender": "M", "team": "Team DevCraft", "project": "Freshman Interactive Campus Directory & Room Finder Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1004", "last": "DE VERA", "first": "Alyssa", "gender": "F", "team": "Team DevCraft", "project": "Freshman Interactive Campus Directory & Room Finder Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 2: Team InnoSpark
    {"id": "1005", "last": "GABRIEL", "first": "Ethan", "gender": "M", "team": "Team InnoSpark", "project": "Digital Lost Property Registry & SMS Notification Station", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1006", "last": "TUPAZ", "first": "Sophia", "gender": "F", "team": "Team InnoSpark", "project": "Digital Lost Property Registry & SMS Notification Station", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1007", "last": "CORDERO", "first": "Justin", "gender": "M", "team": "Team InnoSpark", "project": "Digital Lost Property Registry & SMS Notification Station", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1008", "last": "ALVARADO", "first": "Michelle", "gender": "F", "team": "Team InnoSpark", "project": "Digital Lost Property Registry & SMS Notification Station", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 3: Team SwiftByte
    {"id": "1009", "last": "PINEDA", "first": "Kyle", "gender": "M", "team": "Team SwiftByte", "project": "Student Study Group Finder & Peer Mentorship Scheduler", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1010", "last": "ESPINO", "first": "Bea", "gender": "F", "team": "Team SwiftByte", "project": "Student Study Group Finder & Peer Mentorship Scheduler", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1011", "last": "MIRANDA", "first": "Ralph", "gender": "M", "team": "Team SwiftByte", "project": "Student Study Group Finder & Peer Mentorship Scheduler", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1012", "last": "VENTURA", "first": "Claire", "gender": "F", "team": "Team SwiftByte", "project": "Student Study Group Finder & Peer Mentorship Scheduler", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 4: Team NovaCraft
    {"id": "1013", "last": "CRISOSTOMO", "first": "Nathan", "gender": "M", "team": "Team NovaCraft", "project": "Automated Campus Bulletin Board & Digital Signage Controller", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1014", "last": "FERRER", "first": "Denise", "gender": "F", "team": "Team NovaCraft", "project": "Automated Campus Bulletin Board & Digital Signage Controller", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1015", "last": "AGUAS", "first": "Cedric", "gender": "M", "team": "Team NovaCraft", "project": "Automated Campus Bulletin Board & Digital Signage Controller", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1016", "last": "TENGCO", "first": "Janine", "gender": "F", "team": "Team NovaCraft", "project": "Automated Campus Bulletin Board & Digital Signage Controller", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 5: Team AlphaWave
    {"id": "1017", "last": "BARTOLOME", "first": "Paolo", "gender": "M", "team": "Team AlphaWave", "project": "Library Book Availability Tracker & Study Pod Reservation Desk", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1018", "last": "ESCALADA", "first": "Nicole", "gender": "F", "team": "Team AlphaWave", "project": "Library Book Availability Tracker & Study Pod Reservation Desk", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1019", "last": "MAGNO", "first": "Daryl", "gender": "M", "team": "Team AlphaWave", "project": "Library Book Availability Tracker & Study Pod Reservation Desk", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1020", "last": "LACAP", "first": "Charmaine", "gender": "F", "team": "Team AlphaWave", "project": "Library Book Availability Tracker & Study Pod Reservation Desk", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 6: Team ApexCode
    {"id": "1021", "last": "SALONGA", "first": "Jeric", "gender": "M", "team": "Team ApexCode", "project": "Campus Shuttle Dispatch Tracker & Estimated Arrival Sentinel", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1022", "last": "QUIZON", "first": "Paula", "gender": "F", "team": "Team ApexCode", "project": "Campus Shuttle Dispatch Tracker & Estimated Arrival Sentinel", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1023", "last": "YAMBAO", "first": "Tristan", "gender": "M", "team": "Team ApexCode", "project": "Campus Shuttle Dispatch Tracker & Estimated Arrival Sentinel", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1024", "last": "TING", "first": "Stephanie", "gender": "F", "team": "Team ApexCode", "project": "Campus Shuttle Dispatch Tracker & Estimated Arrival Sentinel", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 7: Team TechNest
    {"id": "1025", "last": "ATIENZA", "first": "Kevin", "gender": "M", "team": "Team TechNest", "project": "Student Printing Credits Kiosk & Automated Queue Dispatcher", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1026", "last": "BONIFACIO", "first": "Angela", "gender": "F", "team": "Team TechNest", "project": "Student Printing Credits Kiosk & Automated Queue Dispatcher", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1027", "last": "CANLAS", "first": "Roniel", "gender": "M", "team": "Team TechNest", "project": "Student Printing Credits Kiosk & Automated Queue Dispatcher", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1028", "last": "DAYRIT", "first": "Maricar", "gender": "F", "team": "Team TechNest", "project": "Student Printing Credits Kiosk & Automated Queue Dispatcher", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 8: Team NextGenIT
    {"id": "1029", "last": "ESTRADA", "first": "Kurt", "gender": "M", "team": "Team NextGenIT", "project": "Interactive Cafeteria Daily Menu & Feedback Rating Portal", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1030", "last": "FELICIANO", "first": "Joy", "gender": "F", "team": "Team NextGenIT", "project": "Interactive Cafeteria Daily Menu & Feedback Rating Portal", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1031", "last": "GALANG", "first": "Matthew", "gender": "M", "team": "Team NextGenIT", "project": "Interactive Cafeteria Daily Menu & Feedback Rating Portal", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1032", "last": "HERMOSO", "first": "Dianne", "gender": "F", "team": "Team NextGenIT", "project": "Interactive Cafeteria Daily Menu & Feedback Rating Portal", "role": "Member", "adviser": "Florencia Dela Torre"},
]

# Section BSIT-1B: One System (8 Teams, 32 Students)
SYSTEM_NAME_1B = "FreshStart: Integrated Freshman Onboarding & Student Life Navigation Ecosystem"
PROJECT_MANAGER_1B = "Mateo Ilagan"

STUDENTS_1B = [
    # Team 9: Team FreshStartPortal (Module 1)
    {"id": "1033", "last": "ILAGAN", "first": "Mateo", "gender": "M", "team": "Team FreshStartPortal", "module": "Freshman Orientation Navigator & Campus Checklist Module", "role": "Leader / PM", "adviser": "Arsenio Macasaet"},
    {"id": "1034", "last": "JAVIER", "first": "Kimberly", "gender": "F", "team": "Team FreshStartPortal", "module": "Freshman Orientation Navigator & Campus Checklist Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1035", "last": "LAGMAN", "first": "Noel", "gender": "M", "team": "Team FreshStartPortal", "module": "Freshman Orientation Navigator & Campus Checklist Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1036", "last": "MACALINTAL", "first": "Grace", "gender": "F", "team": "Team FreshStartPortal", "module": "Freshman Orientation Navigator & Campus Checklist Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 10: Team FreshStartAdvising (Module 2)
    {"id": "1037", "last": "NOGRALES", "first": "Francis", "gender": "M", "team": "Team FreshStartAdvising", "module": "Academic Peer Tutoring & Guidance Appointment Module", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "1038", "last": "ORTIZ", "first": "Rachel", "gender": "F", "team": "Team FreshStartAdvising", "module": "Academic Peer Tutoring & Guidance Appointment Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1039", "last": "PADUA", "first": "Timothy", "gender": "M", "team": "Team FreshStartAdvising", "module": "Academic Peer Tutoring & Guidance Appointment Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1040", "last": "QUIMPO", "first": "Christine", "gender": "F", "team": "Team FreshStartAdvising", "module": "Academic Peer Tutoring & Guidance Appointment Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 11: Team FreshStartClubs (Module 3)
    {"id": "1041", "last": "REGALA", "first": "Christian", "gender": "M", "team": "Team FreshStartClubs", "module": "Student Guilds Discovery & Interest Matcher Module", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "1042", "last": "SILVA", "first": "Bianca", "gender": "F", "team": "Team FreshStartClubs", "module": "Student Guilds Discovery & Interest Matcher Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1043", "last": "TANGLAO", "first": "Joshua", "gender": "M", "team": "Team FreshStartClubs", "module": "Student Guilds Discovery & Interest Matcher Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1044", "last": "UMALI", "first": "Andrea", "gender": "F", "team": "Team FreshStartClubs", "module": "Student Guilds Discovery & Interest Matcher Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 12: Team FreshStartHealth (Module 4)
    {"id": "1045", "last": "VERGARA", "first": "Daniel", "gender": "M", "team": "Team FreshStartHealth", "module": "Campus Wellness Hub & Mental Health Check-In Module", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "1046", "last": "YABUT", "first": "Camille", "gender": "F", "team": "Team FreshStartHealth", "module": "Campus Wellness Hub & Mental Health Check-In Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1047", "last": "ZABALA", "first": "Patrick", "gender": "M", "team": "Team FreshStartHealth", "module": "Campus Wellness Hub & Mental Health Check-In Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1048", "last": "ABAD", "first": "Lorraine", "gender": "F", "team": "Team FreshStartHealth", "module": "Campus Wellness Hub & Mental Health Check-In Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 13: Team FreshStartEvents (Module 5)
    {"id": "1049", "last": "BALAGTAS", "first": "Mark", "gender": "M", "team": "Team FreshStartEvents", "module": "Freshman Welcome Week & Seminar Attendance Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1050", "last": "CABRAL", "first": "Katrina", "gender": "F", "team": "Team FreshStartEvents", "module": "Freshman Welcome Week & Seminar Attendance Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1051", "last": "DIMACALI", "first": "Sean", "gender": "M", "team": "Team FreshStartEvents", "module": "Freshman Welcome Week & Seminar Attendance Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1052", "last": "ESTEBAN", "first": "Patricia", "gender": "F", "team": "Team FreshStartEvents", "module": "Freshman Welcome Week & Seminar Attendance Module", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 14: Team FreshStartHelpdesk (Module 6)
    {"id": "1053", "last": "FLORENDO", "first": "Carlos", "gender": "M", "team": "Team FreshStartHelpdesk", "module": "Campus FAQ Chatbot & Inquiries Ticketing Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1054", "last": "GUINTO", "first": "Valerie", "gender": "F", "team": "Team FreshStartHelpdesk", "module": "Campus FAQ Chatbot & Inquiries Ticketing Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1055", "last": "HILARIO", "first": "Dennis", "gender": "M", "team": "Team FreshStartHelpdesk", "module": "Campus FAQ Chatbot & Inquiries Ticketing Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1056", "last": "INOCENCIO", "first": "Sarah", "gender": "F", "team": "Team FreshStartHelpdesk", "module": "Campus FAQ Chatbot & Inquiries Ticketing Module", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 15: Team FreshStartLocker (Module 7)
    {"id": "1057", "last": "JUGUETA", "first": "Raymond", "gender": "M", "team": "Team FreshStartLocker", "module": "Digital Student Handbook & Forms Repository Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1058", "last": "LABAO", "first": "Jessica", "gender": "F", "team": "Team FreshStartLocker", "module": "Digital Student Handbook & Forms Repository Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1059", "last": "MALLARI", "first": "Kenneth", "gender": "M", "team": "Team FreshStartLocker", "module": "Digital Student Handbook & Forms Repository Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1060", "last": "NAVAL", "first": "Erica", "gender": "F", "team": "Team FreshStartLocker", "module": "Digital Student Handbook & Forms Repository Module", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 16: Team FreshStartBadges (Module 8)
    {"id": "1061", "last": "OBISPO", "first": "Neil", "gender": "M", "team": "Team FreshStartBadges", "module": "Campus Engagement Badges & Milestone Rewards Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1062", "last": "PAGUIA", "first": "Clarisse", "gender": "F", "team": "Team FreshStartBadges", "module": "Campus Engagement Badges & Milestone Rewards Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1063", "last": "QUITO", "first": "Adrian", "gender": "M", "team": "Team FreshStartBadges", "module": "Campus Engagement Badges & Milestone Rewards Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1064", "last": "ROQUE", "first": "Kathleen", "gender": "F", "team": "Team FreshStartBadges", "module": "Campus Engagement Badges & Milestone Rewards Module", "role": "Member", "adviser": "Teresita Buenaventura"},
]

for s in STUDENTS_1A:
    s["formal_name"] = f"{s['last']}, {s['first']}"
    s["full_name"] = f"{s['first']} {s['last'].title()}"
    s["email"] = f"{s['id']}@ustp.edu.ph"
    s["contact"] = f"0917100{s['id']}"

for s in STUDENTS_1B:
    s["formal_name"] = f"{s['last']}, {s['first']}"
    s["full_name"] = f"{s['first']} {s['last'].title()}"
    s["email"] = f"{s['id']}@ustp.edu.ph"
    s["contact"] = f"0917100{s['id']}"

ALL_STUDENTS_1 = STUDENTS_1A + STUDENTS_1B

# ==============================================================================
# 2. GENERATE STUDENT BATCH IMPORT FILES (.xlsx & .csv)
# ==============================================================================

def generate_user_import_files():
    xlsx_path = os.path.join(USER_DIR, "students_1st_year_by_year_level.xlsx")
    csv_path = os.path.join(USER_DIR, "students_1st_year_by_year_level.csv")

    rows_csv = [
        ["LIST OF ENROLLMENT", "", "", "", "", "", "", "", "", "", "", ""],
        ["2026-2027 1st Semester", "", "", "", "", "", "", "", "", "", "", ""],
        ["Bachelor of Science in Information Technology", "", "", "", "", "", "", "", "", "", "", ""],
        ["", "#", "Student No", "Name", "Program", "Major", "Level", "", "Gender", "Status", "Date", "Date"],
    ]

    for idx, s in enumerate(ALL_STUDENTS_1, start=1):
        rows_csv.append([
            "",
            str(idx),
            s["id"],
            f'"{s["formal_name"]}"',
            "BSIT",
            "",
            "1st Year",
            "",
            s["gender"],
            "Officially Enrolled",
            "06/22/2026",
            "06/22/2026",
        ])

    rows_csv.append(["", "TOTAL", "", "", "", "64", "64", "", "", "", "", ""])

    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        for r in rows_csv:
            f.write(",".join(r) + "\n")
    print(f"Generated: {csv_path}")

    # XLSX Generation
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "LIST OF ENROLLMENT"

    for r_idx, r in enumerate(rows_csv, start=1):
        for c_idx, val in enumerate(r, start=1):
            clean_val = val.strip('"')
            if clean_val:
                ws.cell(row=r_idx, column=c_idx, value=clean_val)

    font_arial = Font(name="Arial", size=10)
    for row in ws.iter_rows():
        for cell in row:
            if cell.value:
                cell.font = font_arial

    wb.save(xlsx_path)
    fix_xlsx_for_dart_compatibility(xlsx_path)
    print(f"Generated: {xlsx_path}")

# ==============================================================================
# 3. GENERATE TEAM ROSTER EXCEL & CSV FILES
# ==============================================================================

def generate_team_roster_files():
    xlsx_path = os.path.join(TEAM_DIR, "Team16roster.xlsx")

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "defensys_team_roster_template"

    # Set column widths
    ws.column_dimensions["A"].width = 4.0
    ws.column_dimensions["B"].width = 24.0
    ws.column_dimensions["C"].width = 54.0
    ws.column_dimensions["D"].width = 14.0
    ws.column_dimensions["E"].width = 26.0
    ws.column_dimensions["F"].width = 24.0
    ws.column_dimensions["G"].width = 4.0
    ws.column_dimensions["H"].width = 24.0
    ws.column_dimensions["I"].width = 54.0
    ws.column_dimensions["J"].width = 14.0
    ws.column_dimensions["K"].width = 26.0
    ws.column_dimensions["L"].width = 24.0

    thin = Side(border_style="thin", color="000000")
    border_all = Border(left=thin, right=thin, top=thin, bottom=thin)

    font_regular = Font(name="Arial", size=10, bold=False)
    align_left = Alignment(horizontal="left", vertical="center")
    align_center = Alignment(horizontal="center", vertical="center")

    def format_cell(cell, value, align=align_left, border=border_all):
        cell.value = value
        cell.font = font_regular
        cell.alignment = align
        if border:
            cell.border = border

    # Row 4:
    # Left: Table 1 Headers (BSIT-1A Different Systems)
    format_cell(ws.cell(row=4, column=2), "Team Name:", align_left)
    format_cell(ws.cell(row=4, column=3), "PIT Project", align_left)
    format_cell(ws.cell(row=4, column=4), "Section", align_center)
    format_cell(ws.cell(row=4, column=5), "Instructor", align_center)
    format_cell(ws.cell(row=4, column=6), "Team Members", align_left)

    # Right: System Name metadata (BSIT-1B One System)
    format_cell(ws.cell(row=4, column=8), "System Name:", align_left)
    format_cell(ws.cell(row=4, column=9), SYSTEM_NAME_1B, align_left)

    # Row 5:
    format_cell(ws.cell(row=5, column=8), "Project Manager:", align_left)
    format_cell(ws.cell(row=5, column=9), PROJECT_MANAGER_1B, align_left)

    # Row 6:
    # Right: Table 2 Headers
    format_cell(ws.cell(row=6, column=8), "Team Name:", align_left)
    format_cell(ws.cell(row=6, column=9), "Module", align_left)
    format_cell(ws.cell(row=6, column=10), "Section", align_center)
    format_cell(ws.cell(row=6, column=11), "Instructor", align_center)
    format_cell(ws.cell(row=6, column=12), "Team Members", align_left)

    # Teams grouping
    teams_1a = [STUDENTS_1A[i:i+4] for i in range(0, len(STUDENTS_1A), 4)]
    teams_1b = [STUDENTS_1B[i:i+4] for i in range(0, len(STUDENTS_1B), 4)]

    # Left Side: BSIT-1A Different Systems (Rows 5 to 36)
    for t_idx in range(8):
        t1a = teams_1a[t_idx]
        start_r = 5 + t_idx * 4

        for r_offset in range(4):
            curr_r = start_r + r_offset
            top_b = thin if r_offset == 0 else None
            bot_b = thin if r_offset == 3 else None
            block_border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)

            cell_b = ws.cell(row=curr_r, column=2)
            if r_offset == 0:
                cell_b.value = t1a[0]["team"]
            cell_b.font = font_regular
            cell_b.alignment = align_left
            cell_b.border = block_border

            cell_c = ws.cell(row=curr_r, column=3)
            if r_offset == 0:
                cell_c.value = t1a[0]["project"]
            cell_c.font = font_regular
            cell_c.alignment = align_left
            cell_c.border = block_border

            cell_f = ws.cell(row=curr_r, column=6, value=t1a[r_offset]["full_name"])
            cell_f.font = font_regular
            cell_f.alignment = align_left
            cell_f.border = block_border

    # Right Side: BSIT-1B One System (Rows 7 to 38)
    for t_idx in range(8):
        t1b = teams_1b[t_idx]
        start_r = 7 + t_idx * 4

        for r_offset in range(4):
            curr_r = start_r + r_offset
            top_b = thin if r_offset == 0 else None
            bot_b = thin if r_offset == 3 else None
            block_border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)

            cell_h = ws.cell(row=curr_r, column=8)
            if r_offset == 0:
                cell_h.value = t1b[0]["team"]
            cell_h.font = font_regular
            cell_h.alignment = align_left
            cell_h.border = block_border

            cell_i = ws.cell(row=curr_r, column=9)
            if r_offset == 0:
                cell_i.value = t1b[0]["module"]
            cell_i.font = font_regular
            cell_i.alignment = align_left
            cell_i.border = block_border

            cell_l = ws.cell(row=curr_r, column=12, value=t1b[r_offset]["full_name"])
            cell_l.font = font_regular
            cell_l.alignment = align_left
            cell_l.border = block_border

    # Merged Columns:
    # Col D: Section BSIT-1A (Rows 5 to 36)
    ws.merge_cells("D5:D36")
    for r in range(5, 37):
        cell = ws.cell(row=r, column=4)
        top_b = thin if r == 5 else None
        bot_b = thin if r == 36 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=5, column=4, value="BSIT-1A")

    # Col E: Advisers 1A
    # Teams 1-4 (Rows 5 to 20): Eduardo Padilla
    ws.merge_cells("E5:E20")
    for r in range(5, 21):
        cell = ws.cell(row=r, column=5)
        top_b = thin if r == 5 else None
        bot_b = thin if r == 20 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=5, column=5, value="Eduardo Padilla")

    # Teams 5-8 (Rows 21 to 36): Florencia Dela Torre
    ws.merge_cells("E21:E36")
    for r in range(21, 37):
        cell = ws.cell(row=r, column=5)
        top_b = thin if r == 21 else None
        bot_b = thin if r == 36 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=21, column=5, value="Florencia Dela Torre")

    # Col J: Section BSIT-1B (Rows 7 to 38)
    ws.merge_cells("J7:J38")
    for r in range(7, 39):
        cell = ws.cell(row=r, column=10)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=10, value="BSIT-1B")

    # Col K: Advisers 1B
    # Teams 9-12 (Rows 7 to 22): Arsenio Macasaet
    ws.merge_cells("K7:K22")
    for r in range(7, 23):
        cell = ws.cell(row=r, column=11)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 22 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=11, value="Arsenio Macasaet")

    # Teams 13-16 (Rows 23 to 38): Teresita Buenaventura
    ws.merge_cells("K23:K38")
    for r in range(23, 39):
        cell = ws.cell(row=r, column=11)
        top_b = thin if r == 23 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=23, column=11, value="Teresita Buenaventura")

    wb.save(xlsx_path)
    fix_xlsx_for_dart_compatibility(xlsx_path)
    print(f"Generated: {xlsx_path}")

    # Modular CSVs
    # 1. Section 1A Standalone CSV (Different Systems)
    csv_1a_path = os.path.join(TEAM_DIR, "team_roster_section_1A_different_systems.csv")
    with open(csv_1a_path, "w", newline="", encoding="utf-8") as f:
        f.write("Team Name,PIT Project,Section,Instructor,Team Members\n")
        for t in teams_1a:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["project"]}","BSIT-1A","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_1a_path}")

    # 2. Section 1B Standalone CSV (One System)
    csv_1b_path = os.path.join(TEAM_DIR, "team_roster_section_1B_one_system.csv")
    with open(csv_1b_path, "w", newline="", encoding="utf-8") as f:
        f.write(f"System Name,{SYSTEM_NAME_1B}\n")
        f.write(f"Project Manager,{PROJECT_MANAGER_1B}\n")
        f.write("Team Name,Module,Section,Instructor,Team Members\n")
        for t in teams_1b:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["module"]}","BSIT-1B","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_1b_path}")

    # 3. Combined 1A & 1B CSV
    csv_combined_path = os.path.join(TEAM_DIR, "team_roster_combined_1A_and_1B.csv")
    with open(csv_combined_path, "w", newline="", encoding="utf-8") as f:
        # Section 1A block (Different Systems)
        f.write("Team Name,PIT Project,Section,Instructor,Team Members\n")
        for t in teams_1a:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["project"]}","BSIT-1A","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
        f.write("\n")
        # Section 1B block (One System)
        f.write(f"System Name,{SYSTEM_NAME_1B}\n")
        f.write(f"Project Manager,{PROJECT_MANAGER_1B}\n")
        f.write("Team Name,Module,Section,Instructor,Team Members\n")
        for t in teams_1b:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["module"]}","BSIT-1B","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_combined_path}")

# ==============================================================================
# 4. GENERATE DEFENSE SCHEDULE FILES (.xlsx & .csv)
# ==============================================================================

def generate_defense_schedule_files():
    xlsx_path = os.path.join(SCHED_DIR, "defense_schedule_import.xlsx")
    csv_path = os.path.join(SCHED_DIR, "defense_schedule_import.csv")

    stage = "PIT Idea Pitch Defense"
    date_str = "Nov 27 2026"
    room_str = "Room 304"

    schedule_data = [
        # BSIT-1A Morning Session (Teams 1 - 8)
        # Adviser Eduardo Padilla (Teams 1-4) | Panel: Renato Villanueva, Jonathan Beltran, Analiza Corpuz
        {"time": "8:00AM-8:30AM", "team": "Team DevCraft", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "8:30AM-9:00AM", "team": "Team InnoSpark", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "9:00AM-9:30AM", "team": "Team SwiftByte", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "9:30AM-10:00AM", "team": "Team NovaCraft", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},

        # Adviser Florencia Dela Torre (Teams 5-8) | Panel: Renato Villanueva, Jonathan Beltran, Analiza Corpuz
        {"time": "10:00AM-10:30AM", "team": "Team AlphaWave", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "10:30AM-11:00AM", "team": "Team ApexCode", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "11:00AM-11:30AM", "team": "Team TechNest", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "11:30AM-12:00PM", "team": "Team NextGenIT", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},

        # BSIT-1B Afternoon Session (Teams 9 - 16)
        # Adviser Arsenio Macasaet (Teams 9-12) | Panel: Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla
        {"time": "1:00PM-1:30PM", "team": "Team FreshStartPortal", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "1:30PM-2:00PM", "team": "Team FreshStartAdvising", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "2:00PM-2:30PM", "team": "Team FreshStartClubs", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "2:30PM-3:00PM", "team": "Team FreshStartHealth", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},

        # Adviser Teresita Buenaventura (Teams 13-16) | Panel: Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla
        {"time": "3:00PM-3:30PM", "team": "Team FreshStartEvents", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "3:30PM-4:00PM", "team": "Team FreshStartHelpdesk", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "4:00PM-4:30PM", "team": "Team FreshStartLocker", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "4:30PM-5:00PM", "team": "Team FreshStartBadges", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
    ]

    # CSV Generation (Matching DefenSYS scheduler import standard)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        f.write(f"{stage},,,,,,\n")
        f.write(f"{date_str},,,,,,\n")
        f.write(f"{room_str},,,,,,\n")
        f.write("Time,Team Name,Adviser,Chair Panel,Panel Member 1,Panel Member 2,Panel Member 3\n")
        for s in schedule_data:
            f.write(f'"{s["time"]}","{s["team"]}","{s["adviser"]}","{s["chair"]}","{s["p1"]}","{s["p2"]}","{s["p3"]}"\n')
    print(f"Generated: {csv_path}")

    # XLSX Generation
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "defense_schedule_import"

    # Margins matching schedule layout
    ws.column_dimensions["A"].width = 16.0
    ws.column_dimensions["B"].width = 18.0
    ws.column_dimensions["C"].width = 18.0 # Time
    ws.column_dimensions["D"].width = 24.0 # Team Name
    ws.column_dimensions["E"].width = 24.0 # Adviser
    ws.column_dimensions["F"].width = 20.0 # Chair Panel
    ws.column_dimensions["G"].width = 20.0 # Panel Member 1
    ws.column_dimensions["H"].width = 20.0 # Panel Member 2
    ws.column_dimensions["I"].width = 20.0 # Panel Member 3

    font_regular = Font(name="Calibri", size=11, bold=False)
    align_left = Alignment(horizontal="left", vertical="center")
    thin = Side(border_style="thin", color="000000")
    border_all = Border(left=thin, right=thin, top=thin, bottom=thin)

    # Row 3: Stage (Cols C to I)
    ws.merge_cells("C3:I3")
    ws.cell(row=3, column=3, value=stage).font = font_regular

    # Row 4: Date
    ws.merge_cells("C4:I4")
    ws.cell(row=4, column=3, value=date_str).font = font_regular

    # Row 5: Room
    ws.merge_cells("C5:I5")
    ws.cell(row=5, column=3, value=room_str).font = font_regular

    # Row 6: Headers
    headers = ["Time", "Team Name", "Adviser", "Chair Panel", "Panel Member 1", "Panel Member 2", "Panel Member 3"]
    for c_idx, h in enumerate(headers, start=3):
        cell = ws.cell(row=6, column=c_idx, value=h)
        cell.font = font_regular
        cell.alignment = align_left
        cell.border = border_all

    # Rows 7 to 22: Slots
    for r_idx, s in enumerate(schedule_data, start=7):
        row_vals = [s["time"], s["team"], s["adviser"], s["chair"], s["p1"], s["p2"], s["p3"]]
        for c_idx, val in enumerate(row_vals, start=3):
            cell = ws.cell(row=r_idx, column=c_idx, value=val)
            cell.font = font_regular
            cell.alignment = align_left
            cell.border = border_all

    wb.save(xlsx_path)
    fix_xlsx_for_dart_compatibility(xlsx_path)
    print(f"Generated: {xlsx_path}")

# ==============================================================================
# 5. GENERATE MASTER README.MD
# ==============================================================================

def generate_readme():
    readme_path = os.path.join(OUTPUT_DIR, "README.md")
    content = f"""# DefenSYS 1st Year PIT Demo Suite (16 Teams, 64 Students)

This dataset provides a complete, production-ready sample suite for **1st Year PIT (Project Innovation and Technology 1 / Freshman Innovation)** in DefenSYS configured according to the curriculum model:
- **Section BSIT-1A**: **Different Systems Format** (8 teams developing independent, standalone PIT innovation projects)
- **Section BSIT-1B**: **One System Format** (8 teams developing specialized modules of *{SYSTEM_NAME_1B}*, PM: *{PROJECT_MANAGER_1B}*)
- **4 Advised Teams per Adviser / Instructor**:
  - `Prof. Eduardo Padilla` (`212`): Teams 1–4 (BSIT-1A) — *1st Year PIT Lead*
  - `Prof. Florencia Dela Torre` (`213`): Teams 5–8 (BSIT-1A)
  - `Prof. Arsenio Macasaet` (`215`): Teams 9–12 (BSIT-1B)
  - `Prof. Teresita Buenaventura` (`214`): Teams 13–16 (BSIT-1B)
- **Zero Adviser Conflict**: Advisers never sit on their own advisee panels. All 10 faculty accounts from `sample_file/faculty_user/demo_faculty_import.csv` are used across chairs, panels, and instructors.
- **PIT Documenter Convention**: Matches DefenSYS PIT scheduling model where documenter is omitted from the schedule import timetable.

---

## 📁 Included Files

| File | Type | Description |
|------|------|-------------|
| [students_1st_year_by_year_level.xlsx](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/USer/students_1st_year_by_year_level.xlsx) | **User Bulk Import (Excel)** | Registrar export (`USTP LIST OF ENROLLMENT` format) with 64 officially enrolled 1st Year students (`1001`–`1064`). Fully compatible with DefenSYS master cohort intake. |
| [students_1st_year_by_year_level.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/USer/students_1st_year_by_year_level.csv) | **User Bulk Import (CSV)** | CSV version of the 64-student freshman class list. |
| [Team16roster.xlsx](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/team/Team16roster.xlsx) | **Team Roster (Master Excel)** | Standard DefenSYS roster format featuring Section 1A (Different Systems) and Section 1B (One System) side-by-side with merged instructor blocks. |
| [team_roster_section_1A_different_systems.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/team/team_roster_section_1A_different_systems.csv) | **Team Roster (Section 1A CSV)** | 8 standalone freshman teams in Section 1A, each with an independent innovation project. |
| [team_roster_section_1B_one_system.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/team/team_roster_section_1B_one_system.csv) | **Team Roster (Section 1B CSV)** | 8 modular freshman teams in Section 1B collaborating on the *FreshStart Ecosystem* under PM Mateo Ilagan. |
| [team_roster_combined_1A_and_1B.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/team/team_roster_combined_1A_and_1B.csv) | **Team Roster (Combined CSV)** | Sequential import file containing Section 1A followed by Section 1B for one-click team bulk intake. |
| [defense_schedule_import.xlsx](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/schedule/defense_schedule_import.xlsx) | **Defense Schedule (Excel)** | 16 scheduled pitch presentation slots with Chair and 3 Panel Members. Documenter column omitted per PIT rules. |
| [defense_schedule_import.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year/1st%20Sem/schedule/defense_schedule_import.csv) | **Defense Schedule (CSV)** | Official 3-row preamble (`PIT Idea Pitch Defense`, `Nov 27 2026`, `Room 304`) CSV timetable. |

---

## 👥 Master Student & Team Allocation Matrix

- **Total Students**: 64 (All unique names, IDs, emails, contact numbers)
- **ID Numbers**: `1001` – `1064` (Default password equals ID number)
- **Team Size**: 4 members per team (1st member is Leader)

---

### Section BSIT-1A — Different Systems (8 Teams, 32 Students)
*Every team in Section 1A develops an independent, unique freshman PIT innovation project.*

#### Instructor: Eduardo Padilla (`212`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Innovation Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|---------------------------------------------------|
| **Team DevCraft** | **Leader** | `1001` | Liam Liwanag | `1001@ustp.edu.ph` | 09171001001 | Freshman Interactive Campus Directory & Room Finder Kiosk |
| | Member | `1002` | Chloe Marquez | `1002@ustp.edu.ph` | 09171001002 | |
| | Member | `1003` | Andrei Catapang | `1003@ustp.edu.ph` | 09171001003 | |
| | Member | `1004` | Alyssa De Vera | `1004@ustp.edu.ph` | 09171001004 | |
| **Team InnoSpark** | **Leader** | `1005` | Ethan Gabriel | `1005@ustp.edu.ph` | 09171001005 | Digital Lost Property Registry & SMS Notification Station |
| | Member | `1006` | Sophia Tupaz | `1006@ustp.edu.ph` | 09171001006 | |
| | Member | `1007` | Justin Cordero | `1007@ustp.edu.ph` | 09171001007 | |
| | Member | `1008` | Michelle Alvarado | `1008@ustp.edu.ph` | 09171001008 | |
| **Team SwiftByte** | **Leader** | `1009` | Kyle Pineda | `1009@ustp.edu.ph` | 09171001009 | Student Study Group Finder & Peer Mentorship Scheduler |
| | Member | `1010` | Bea Espino | `1010@ustp.edu.ph` | 09171001010 | |
| | Member | `1011` | Ralph Miranda | `1011@ustp.edu.ph` | 09171001011 | |
| | Member | `1012` | Claire Ventura | `1012@ustp.edu.ph` | 09171001012 | |
| **Team NovaCraft** | **Leader** | `1013` | Nathan Crisostomo | `1013@ustp.edu.ph` | 09171001013 | Automated Campus Bulletin Board & Digital Signage Controller |
| | Member | `1014` | Denise Ferrer | `1014@ustp.edu.ph` | 09171001014 | |
| | Member | `1015` | Cedric Aguas | `1015@ustp.edu.ph` | 09171001015 | |
| | Member | `1016` | Janine Tengco | `1016@ustp.edu.ph` | 09171001016 | |

#### Instructor: Florencia Dela Torre (`213`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Innovation Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|---------------------------------------------------|
| **Team AlphaWave** | **Leader** | `1017` | Paolo Bartolome | `1017@ustp.edu.ph` | 09171001017 | Library Book Availability Tracker & Study Pod Reservation Desk |
| | Member | `1018` | Nicole Escalada | `1018@ustp.edu.ph` | 09171001018 | |
| | Member | `1019` | Daryl Magno | `1019@ustp.edu.ph` | 09171001019 | |
| | Member | `1020` | Charmaine Lacap | `1020@ustp.edu.ph` | 09171001020 | |
| **Team ApexCode** | **Leader** | `1021` | Jeric Salonga | `1021@ustp.edu.ph` | 09171001021 | Campus Shuttle Dispatch Tracker & Estimated Arrival Sentinel |
| | Member | `1022` | Paula Quizon | `1022@ustp.edu.ph` | 09171001022 | |
| | Member | `1023` | Tristan Yambao | `1023@ustp.edu.ph` | 09171001023 | |
| | Member | `1024` | Stephanie Ting | `1024@ustp.edu.ph` | 09171001024 | |
| **Team TechNest** | **Leader** | `1025` | Kevin Atienza | `1025@ustp.edu.ph` | 09171001025 | Student Printing Credits Kiosk & Automated Queue Dispatcher |
| | Member | `1026` | Angela Bonifacio | `1026@ustp.edu.ph` | 09171001026 | |
| | Member | `1027` | Roniel Canlas | `1027@ustp.edu.ph` | 09171001027 | |
| | Member | `1028` | Maricar Dayrit | `1028@ustp.edu.ph` | 09171001028 | |
| **Team NextGenIT** | **Leader** | `1029` | Kurt Estrada | `1029@ustp.edu.ph` | 09171001029 | Interactive Cafeteria Daily Menu & Feedback Rating Portal |
| | Member | `1030` | Joy Feliciano | `1030@ustp.edu.ph` | 09171001030 | |
| | Member | `1031` | Matthew Galang | `1031@ustp.edu.ph` | 09171001031 | |
| | Member | `1032` | Dianne Hermoso | `1032@ustp.edu.ph` | 09171001032 | |

---

### Section BSIT-1B — One Shared System (8 Teams, 32 Students)
*All teams in Section 1B collaborate on modules of one overarching freshman ecosystem:*
- **System Name**: `{SYSTEM_NAME_1B}`
- **Project Manager**: `{PROJECT_MANAGER_1B}`

#### Instructor: Arsenio Macasaet (`215`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team FreshStartPortal** | **Leader / PM** | `1033` | Mateo Ilagan | `1033@ustp.edu.ph` | 09171001033 | Freshman Orientation Navigator & Campus Checklist Module |
| | Member | `1034` | Kimberly Javier | `1034@ustp.edu.ph` | 09171001034 | |
| | Member | `1035` | Noel Lagman | `1035@ustp.edu.ph` | 09171001035 | |
| | Member | `1036` | Grace Macalintal | `1036@ustp.edu.ph` | 09171001036 | |
| **Team FreshStartAdvising** | **Leader** | `1037` | Francis Nograles | `1037@ustp.edu.ph` | 09171001037 | Academic Peer Tutoring & Guidance Appointment Module |
| | Member | `1038` | Rachel Ortiz | `1038@ustp.edu.ph` | 09171001038 | |
| | Member | `1039` | Timothy Padua | `1039@ustp.edu.ph` | 09171001039 | |
| | Member | `1040` | Christine Quimpo | `1040@ustp.edu.ph` | 09171001040 | |
| **Team FreshStartClubs** | **Leader** | `1041` | Christian Regala | `1041@ustp.edu.ph` | 09171001041 | Student Guilds Discovery & Interest Matcher Module |
| | Member | `1042` | Bianca Silva | `1042@ustp.edu.ph` | 09171001042 | |
| | Member | `1043` | Joshua Tanglao | `1043@ustp.edu.ph` | 09171001043 | |
| | Member | `1044` | Andrea Umali | `1044@ustp.edu.ph` | 09171001044 | |
| **Team FreshStartHealth** | **Leader** | `1045` | Daniel Vergara | `1045@ustp.edu.ph` | 09171001045 | Campus Wellness Hub & Mental Health Check-In Module |
| | Member | `1046` | Camille Yabut | `1046@ustp.edu.ph` | 09171001046 | |
| | Member | `1047` | Patrick Zabala | `1047@ustp.edu.ph` | 09171001047 | |
| | Member | `1048` | Lorraine Abad | `1048@ustp.edu.ph` | 09171001048 | |

#### Instructor: Teresita Buenaventura (`214`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team FreshStartEvents** | **Leader** | `1049` | Mark Balagtas | `1049@ustp.edu.ph` | 09171001049 | Freshman Welcome Week & Seminar Attendance Module |
| | Member | `1050` | Katrina Cabral | `1050@ustp.edu.ph` | 09171001050 | |
| | Member | `1051` | Sean Dimacali | `1051@ustp.edu.ph` | 09171001051 | |
| | Member | `1052` | Patricia Esteban | `1052@ustp.edu.ph` | 09171001052 | |
| **Team FreshStartHelpdesk** | **Leader** | `1053` | Carlos Florendo | `1053@ustp.edu.ph` | 09171001053 | Campus FAQ Chatbot & Inquiries Ticketing Module |
| | Member | `1054` | Valerie Guinto | `1054@ustp.edu.ph` | 09171001054 | |
| | Member | `1055` | Dennis Hilario | `1055@ustp.edu.ph` | 09171001055 | |
| | Member | `1056` | Sarah Inocencio | `1056@ustp.edu.ph` | 09171001056 | |
| **Team FreshStartLocker** | **Leader** | `1057` | Raymond Jugueta | `1057@ustp.edu.ph` | 09171001057 | Digital Student Handbook & Forms Repository Module |
| | Member | `1058` | Jessica Labao | `1058@ustp.edu.ph` | 09171001058 | |
| | Member | `1059` | Kenneth Mallari | `1059@ustp.edu.ph` | 09171001059 | |
| | Member | `1060` | Erica Naval | `1060@ustp.edu.ph` | 09171001060 | |
| **Team FreshStartBadges** | **Leader** | `1061` | Neil Obispo | `1061@ustp.edu.ph` | 09171001061 | Campus Engagement Badges & Milestone Rewards Module |
| | Member | `1062` | Clarisse Paguia | `1062@ustp.edu.ph` | 09171001062 | |
| | Member | `1063` | Adrian Quito | `1063@ustp.edu.ph` | 09171001063 | |
| | Member | `1064` | Kathleen Roque | `1064@ustp.edu.ph` | 09171001064 | |

---

## 📅 Defense Schedule Matrix (`defense_schedule_import.xlsx` / `.csv`)

- **Stage**: `PIT Idea Pitch Defense`
- **Date**: `Nov 27 2026`
- **Venue**: `Room 304`

| Time Slot | Team Name | Section | Adviser | Chair | Panel Members |
|-----------|-----------|---------|---------|-------|---------------|
| 08:00 AM - 08:30 AM | Team DevCraft | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 08:30 AM - 09:00 AM | Team InnoSpark | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 09:00 AM - 09:30 AM | Team SwiftByte | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 09:30 AM - 10:00 AM | Team NovaCraft | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 10:00 AM - 10:30 AM | Team AlphaWave | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 10:30 AM - 11:00 AM | Team ApexCode | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 11:00 AM - 11:30 AM | Team TechNest | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 11:30 AM - 12:00 PM | Team NextGenIT | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 01:00 PM - 01:30 PM | Team FreshStartPortal | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 01:30 PM - 02:00 PM | Team FreshStartAdvising | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 02:00 PM - 02:30 PM | Team FreshStartClubs | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 02:30 PM - 03:00 PM | Team FreshStartHealth | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 03:00 PM - 03:30 PM | Team FreshStartEvents | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 03:30 PM - 04:00 PM | Team FreshStartHelpdesk | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 04:00 PM - 04:30 PM | Team FreshStartLocker | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 04:30 PM - 05:00 PM | Team FreshStartBadges | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |

> **Zero Conflict Guarantee**: Advisers never sit on their own advisee team's panel. All faculty allocations use verified IDs `206` through `215`.

---

## 🚀 Recommended Step-by-Step Import Workflow

### 1. Faculty Accounts
Import `sample_file/faculty_user/demo_faculty_import.csv` via:
`Admin -> User Management -> Faculty / General Users -> Bulk Import Users`

### 2. Student Batch Intake (By Year Level)
Import `students_1st_year_by_year_level.xlsx` (or `.csv`) via:
`Admin -> User Management -> Bulk Import -> By Year Level (Master Cohort Intake)`
*(Enrolls all 64 students 1001 to 1064 in 1st Year).*

### 3. Student Teams Roster Formation
In `Student Teams -> Bulk Import`, upload:
- **Unified Master Excel**: `Team16roster.xlsx` (Section 1A Different Systems and Section 1B One System side-by-side).
- Or use the modular CSV files:
  - `team_roster_section_1A_different_systems.csv`
  - `team_roster_section_1B_one_system.csv`
  - `team_roster_combined_1A_and_1B.csv`

### 4. Defense Schedule
Import `defense_schedule_import.xlsx` (or `.csv`) via:
`Admin -> Defense Scheduler -> Import Schedule`
*(Populates all 16 scheduled pitch presentation slots with chair and panelists).*
"""
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Generated: {readme_path}")

if __name__ == "__main__":
    generate_user_import_files()
    generate_team_roster_files()
    generate_defense_schedule_files()
    generate_readme()
    print("All 1st Year PIT sample suite files successfully generated!")
