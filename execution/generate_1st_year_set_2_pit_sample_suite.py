"""
Execution Tool: generate_1st_year_set_2_pit_sample_suite.py
Generates the complete 1st Year PIT Set 2 (16 Teams, 64 Students, IDs 1065-1128) sample data suite:
1. User Import: students_1st_year_by_year_level.xlsx & .csv
2. Team Roster: Team16roster.xlsx, team_roster_section_1A_different_systems.csv,
   team_roster_section_1B_one_system.csv, team_roster_combined_1A_and_1B.csv
3. Defense Schedule: defense_schedule_import.xlsx & .csv
4. Master Documentation: sample_file/16_Teams_1st_Year_Set_2/README.md
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
OUTPUT_DIR = os.path.join(BASE_DIR, "sample_file", "16_Teams_1st_Year_Set_2")
SEM_DIR = os.path.join(OUTPUT_DIR, "1st Sem")
USER_DIR = os.path.join(SEM_DIR, "USer")
TEAM_DIR = os.path.join(SEM_DIR, "team")
SCHED_DIR = os.path.join(SEM_DIR, "schedule")

os.makedirs(USER_DIR, exist_ok=True)
os.makedirs(TEAM_DIR, exist_ok=True)
os.makedirs(SCHED_DIR, exist_ok=True)

# ==============================================================================
# 1. MASTER STUDENTS AND TEAMS SPECIFICATION (1ST YEAR SET 2)
# ==============================================================================

# Section BSIT-1A: Different Systems (8 Teams, 32 Students)
STUDENTS_1A = [
    # Team 1: Team CodeSprint (1065-1068)
    {"id": "1065", "last": "PASCUA", "first": "Jethro", "gender": "M", "team": "Team CodeSprint", "project": "Campus Lost Keycard & RFID Tag Auto-Verification Kiosk", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1066", "last": "FERMIN", "first": "Trisha", "gender": "F", "team": "Team CodeSprint", "project": "Campus Lost Keycard & RFID Tag Auto-Verification Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1067", "last": "GALVEZ", "first": "Alren", "gender": "M", "team": "Team CodeSprint", "project": "Campus Lost Keycard & RFID Tag Auto-Verification Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1068", "last": "SAMPANG", "first": "Kyla", "gender": "F", "team": "Team CodeSprint", "project": "Campus Lost Keycard & RFID Tag Auto-Verification Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 2: Team BrainSync (1069-1072)
    {"id": "1069", "last": "VILLALUZ", "first": "Bryan", "gender": "M", "team": "Team BrainSync", "project": "Automated Class Attendance Verification via Bluetooth Low Energy Beacons", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1070", "last": "TIAMZON", "first": "Aira", "gender": "F", "team": "Team BrainSync", "project": "Automated Class Attendance Verification via Bluetooth Low Energy Beacons", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1071", "last": "LUMABAS", "first": "Gideon", "gender": "M", "team": "Team BrainSync", "project": "Automated Class Attendance Verification via Bluetooth Low Energy Beacons", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1072", "last": "SARMIENTO", "first": "Roxanne", "gender": "F", "team": "Team BrainSync", "project": "Automated Class Attendance Verification via Bluetooth Low Energy Beacons", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 3: Team DataNest (1073-1076)
    {"id": "1073", "last": "MALABANAN", "first": "Warren", "gender": "M", "team": "Team DataNest", "project": "Campus Cafeteria Nutrition Analyzer & Daily Meal Pre-Ordering Kiosk", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1074", "last": "QUISUMBING", "first": "Ella", "gender": "F", "team": "Team DataNest", "project": "Campus Cafeteria Nutrition Analyzer & Daily Meal Pre-Ordering Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1075", "last": "TARUC", "first": "Alfonso", "gender": "M", "team": "Team DataNest", "project": "Campus Cafeteria Nutrition Analyzer & Daily Meal Pre-Ordering Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1076", "last": "PANLILIO", "first": "Jazmin", "gender": "F", "team": "Team DataNest", "project": "Campus Cafeteria Nutrition Analyzer & Daily Meal Pre-Ordering Kiosk", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 4: Team SparkByte (1077-1080)
    {"id": "1077", "last": "MONTEALEGRE", "first": "Ezekiel", "gender": "M", "team": "Team SparkByte", "project": "Interactive Campus Map & Accessible Pathway Navigation for PWDs", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "1078", "last": "DELA MERCED", "first": "Cheska", "gender": "F", "team": "Team SparkByte", "project": "Interactive Campus Map & Accessible Pathway Navigation for PWDs", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1079", "last": "BAUTISTA", "first": "Gelo", "gender": "M", "team": "Team SparkByte", "project": "Interactive Campus Map & Accessible Pathway Navigation for PWDs", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "1080", "last": "CALDERON", "first": "Princess", "gender": "F", "team": "Team SparkByte", "project": "Interactive Campus Map & Accessible Pathway Navigation for PWDs", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 5: Team CloudNexus (1081-1084)
    {"id": "1081", "last": "VENTURINA", "first": "Lester", "gender": "M", "team": "Team CloudNexus", "project": "Student Printing Credits Kiosk with Remote Mobile Document Queue", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1082", "last": "SEVILLA", "first": "Mariane", "gender": "F", "team": "Team CloudNexus", "project": "Student Printing Credits Kiosk with Remote Mobile Document Queue", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1083", "last": "MANALILI", "first": "Darwin", "gender": "M", "team": "Team CloudNexus", "project": "Student Printing Credits Kiosk with Remote Mobile Document Queue", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1084", "last": "TOLENTINO", "first": "Charmel", "gender": "F", "team": "Team CloudNexus", "project": "Student Printing Credits Kiosk with Remote Mobile Document Queue", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 6: Team AlgoSphere (1085-1088)
    {"id": "1085", "last": "ALCANTARA", "first": "Jomar", "gender": "M", "team": "Team AlgoSphere", "project": "IoT-Based Classroom Power Conservation & Automated Light Controller", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1086", "last": "IBARRA", "first": "Lourdes", "gender": "F", "team": "Team AlgoSphere", "project": "IoT-Based Classroom Power Conservation & Automated Light Controller", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1087", "last": "LEGASPI", "first": "Renan", "gender": "M", "team": "Team AlgoSphere", "project": "IoT-Based Classroom Power Conservation & Automated Light Controller", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1088", "last": "MALLARI", "first": "Krizzia", "gender": "F", "team": "Team AlgoSphere", "project": "IoT-Based Classroom Power Conservation & Automated Light Controller", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 7: Team CyberCraft (1089-1092)
    {"id": "1089", "last": "VALENCIANO", "first": "Marlon", "gender": "M", "team": "Team CyberCraft", "project": "University Event Badge Scanner & Real-Time Headcount Sentinel", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1090", "last": "YUSON", "first": "Gellie", "gender": "F", "team": "Team CyberCraft", "project": "University Event Badge Scanner & Real-Time Headcount Sentinel", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1091", "last": "AGUILAR", "first": "Rommel", "gender": "M", "team": "Team CyberCraft", "project": "University Event Badge Scanner & Real-Time Headcount Sentinel", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1092", "last": "ZUNIGA", "first": "Jhoanna", "gender": "F", "team": "Team CyberCraft", "project": "University Event Badge Scanner & Real-Time Headcount Sentinel", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 8: Team IntelliTech (1093-1096)
    {"id": "1093", "last": "CORONADO", "first": "Arjay", "gender": "M", "team": "Team IntelliTech", "project": "Digital Student Lockers with One-Time Password Retrieval Terminal", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "1094", "last": "FAJARDO", "first": "Myra", "gender": "F", "team": "Team IntelliTech", "project": "Digital Student Lockers with One-Time Password Retrieval Terminal", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1095", "last": "DIMAPILIS", "first": "Jared", "gender": "M", "team": "Team IntelliTech", "project": "Digital Student Lockers with One-Time Password Retrieval Terminal", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "1096", "last": "BARCELONA", "first": "Shiela", "gender": "F", "team": "Team IntelliTech", "project": "Digital Student Lockers with One-Time Password Retrieval Terminal", "role": "Member", "adviser": "Florencia Dela Torre"},
]

# Section BSIT-1B: One System (8 Teams, 32 Students)
SYSTEM_NAME_1B = "UniConnect: Integrated Campus Student Service & Collaborative Resource Network"
PROJECT_MANAGER_1B = "Lance San Pedro"

STUDENTS_1B = [
    # Team 9: Team UniConnectCore (Module 1)
    {"id": "1097", "last": "SAN PEDRO", "first": "Lance", "gender": "M", "team": "Team UniConnectCore", "module": "Student Service Desk & Facilities Work Order Dispatch Module", "role": "Leader / PM", "adviser": "Arsenio Macasaet"},
    {"id": "1098", "last": "BORJA", "first": "Kathleen", "gender": "F", "team": "Team UniConnectCore", "module": "Student Service Desk & Facilities Work Order Dispatch Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1099", "last": "LACSAMANA", "first": "Roderick", "gender": "M", "team": "Team UniConnectCore", "module": "Student Service Desk & Facilities Work Order Dispatch Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1100", "last": "OBRERO", "first": "Hazel", "gender": "F", "team": "Team UniConnectCore", "module": "Student Service Desk & Facilities Work Order Dispatch Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 10: Team UniConnectShuttle (Module 2)
    {"id": "1101", "last": "PANGILINAN", "first": "Cedie", "gender": "M", "team": "Team UniConnectShuttle", "module": "Campus Shuttle Real-Time Tracking & Station ETA Module", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "1102", "last": "SAMSON", "first": "Danica", "gender": "F", "team": "Team UniConnectShuttle", "module": "Campus Shuttle Real-Time Tracking & Station ETA Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1103", "last": "VILLANUEVA", "first": "Gian", "gender": "M", "team": "Team UniConnectShuttle", "module": "Campus Shuttle Real-Time Tracking & Station ETA Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1104", "last": "CRUZAT", "first": "Bernadette", "gender": "F", "team": "Team UniConnectShuttle", "module": "Campus Shuttle Real-Time Tracking & Station ETA Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 11: Team UniConnectFinder (Module 3)
    {"id": "1105", "last": "TOLOSA", "first": "Kervin", "gender": "M", "team": "Team UniConnectFinder", "module": "Lost Property Digital Catalog & Biometric Claim Module", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "1106", "last": "VELOSO", "first": "Clarice", "gender": "F", "team": "Team UniConnectFinder", "module": "Lost Property Digital Catalog & Biometric Claim Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1107", "last": "ZAFRA", "first": "Aldrin", "gender": "M", "team": "Team UniConnectFinder", "module": "Lost Property Digital Catalog & Biometric Claim Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1108", "last": "ASUNCION", "first": "Mikaela", "gender": "F", "team": "Team UniConnectFinder", "module": "Lost Property Digital Catalog & Biometric Claim Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 12: Team UniConnectLab (Module 4)
    {"id": "1109", "last": "BELTRAN", "first": "Edgardo", "gender": "M", "team": "Team UniConnectLab", "module": "IT Computer Laboratory Workstation Reservation & Usage Module", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "1110", "last": "CARREON", "first": "Jemimah", "gender": "F", "team": "Team UniConnectLab", "module": "IT Computer Laboratory Workstation Reservation & Usage Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1111", "last": "DE GUZMAN", "first": "Nico", "gender": "M", "team": "Team UniConnectLab", "module": "IT Computer Laboratory Workstation Reservation & Usage Module", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "1112", "last": "ESPIRITU", "first": "Abby", "gender": "F", "team": "Team UniConnectLab", "module": "IT Computer Laboratory Workstation Reservation & Usage Module", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 13: Team UniConnectClinic (Module 5)
    {"id": "1113", "last": "FORONDA", "first": "Jayson", "gender": "M", "team": "Team UniConnectClinic", "module": "Student Health Center Queue & Medical Triage Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1114", "last": "GARCIA", "first": "Trina", "gender": "F", "team": "Team UniConnectClinic", "module": "Student Health Center Queue & Medical Triage Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1115", "last": "HERRERA", "first": "Mark Anthony", "gender": "M", "team": "Team UniConnectClinic", "module": "Student Health Center Queue & Medical Triage Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1116", "last": "ILAGAN", "first": "Giselle", "gender": "F", "team": "Team UniConnectClinic", "module": "Student Health Center Queue & Medical Triage Module", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 14: Team UniConnectEco (Module 6)
    {"id": "1117", "last": "JALOSJOS", "first": "Kenneth", "gender": "M", "team": "Team UniConnectEco", "module": "Campus Eco-Drop & Material Recycling Rewards Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1118", "last": "KATINDIG", "first": "Maricel", "gender": "F", "team": "Team UniConnectEco", "module": "Campus Eco-Drop & Material Recycling Rewards Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1119", "last": "LAUREL", "first": "Elmer", "gender": "M", "team": "Team UniConnectEco", "module": "Campus Eco-Drop & Material Recycling Rewards Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1120", "last": "MANAPAT", "first": "Charmaine", "gender": "F", "team": "Team UniConnectEco", "module": "Campus Eco-Drop & Material Recycling Rewards Module", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 15: Team UniConnectPods (Module 7)
    {"id": "1121", "last": "NATIVIDAD", "first": "Roderick", "gender": "M", "team": "Team UniConnectPods", "module": "Silent Study Pods & Collaborative Space Booking Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1122", "last": "OLIVEROS", "first": "Bea", "gender": "F", "team": "Team UniConnectPods", "module": "Silent Study Pods & Collaborative Space Booking Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1123", "last": "PADILLA", "first": "Jerome", "gender": "M", "team": "Team UniConnectPods", "module": "Silent Study Pods & Collaborative Space Booking Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1124", "last": "QUERUBIN", "first": "Janelle", "gender": "F", "team": "Team UniConnectPods", "module": "Silent Study Pods & Collaborative Space Booking Module", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 16: Team UniConnectSafe (Module 8)
    {"id": "1125", "last": "RAMOS", "first": "Dominic", "gender": "M", "team": "Team UniConnectSafe", "module": "Campus Emergency Blue Light & Night Escort Sentinel Module", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "1126", "last": "SALAS", "first": "Kirsten", "gender": "F", "team": "Team UniConnectSafe", "module": "Campus Emergency Blue Light & Night Escort Sentinel Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1127", "last": "TIAMSON", "first": "Rodel", "gender": "M", "team": "Team UniConnectSafe", "module": "Campus Emergency Blue Light & Night Escort Sentinel Module", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "1128", "last": "URBINA", "first": "Stephanie", "gender": "F", "team": "Team UniConnectSafe", "module": "Campus Emergency Blue Light & Night Escort Sentinel Module", "role": "Member", "adviser": "Teresita Buenaventura"},
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
    date_str = "Dec 04 2026"
    room_str = "Room 305"

    schedule_data = [
        # BSIT-1A Morning Session (Teams 1 - 8)
        # Adviser Eduardo Padilla (Teams 1-4) | Panel: Renato Villanueva, Jonathan Beltran, Analiza Corpuz
        {"time": "8:00AM-8:30AM", "team": "Team CodeSprint", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "8:30AM-9:00AM", "team": "Team BrainSync", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "9:00AM-9:30AM", "team": "Team DataNest", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "9:30AM-10:00AM", "team": "Team SparkByte", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},

        # Adviser Florencia Dela Torre (Teams 5-8) | Panel: Renato Villanueva, Jonathan Beltran, Analiza Corpuz
        {"time": "10:00AM-10:30AM", "team": "Team CloudNexus", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "10:30AM-11:00AM", "team": "Team AlgoSphere", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "11:00AM-11:30AM", "team": "Team CyberCraft", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},
        {"time": "11:30AM-12:00PM", "team": "Team IntelliTech", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Analiza Corpuz"},

        # BSIT-1B Afternoon Session (Teams 9 - 16)
        # Adviser Arsenio Macasaet (Teams 9-12) | Panel: Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla
        {"time": "1:00PM-1:30PM", "team": "Team UniConnectCore", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "1:30PM-2:00PM", "team": "Team UniConnectShuttle", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "2:00PM-2:30PM", "team": "Team UniConnectFinder", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "2:30PM-3:00PM", "team": "Team UniConnectLab", "adviser": "Arsenio Macasaet", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},

        # Adviser Teresita Buenaventura (Teams 13-16) | Panel: Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla
        {"time": "3:00PM-3:30PM", "team": "Team UniConnectClinic", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "3:30PM-4:00PM", "team": "Team UniConnectEco", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "4:00PM-4:30PM", "team": "Team UniConnectPods", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
        {"time": "4:30PM-5:00PM", "team": "Team UniConnectSafe", "adviser": "Teresita Buenaventura", "chair": "Maricel Suarez", "p1": "Renato Villanueva", "p2": "Jonathan Beltran", "p3": "Ricardo Fontanilla"},
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
    content = f"""# DefenSYS 1st Year PIT Demo Suite - Set 2 (16 Teams, 64 Students)

This dataset provides an independent, production-ready sample suite for **1st Year PIT (Project Innovation and Technology 1 / Freshman Innovation - Set 2)** in DefenSYS configured according to the curriculum model:
- **Section BSIT-1A**: **Different Systems Format** (8 teams developing independent, standalone PIT innovation projects)
- **Section BSIT-1B**: **One System Format** (8 teams developing specialized modules of *{SYSTEM_NAME_1B}*, PM: *{PROJECT_MANAGER_1B}*)
- **4 Advised Teams per Adviser / Instructor**:
  - `Prof. Eduardo Padilla` (`212`): Teams 1–4 (BSIT-1A) — *1st Year PIT Lead*
  - `Prof. Florencia Dela Torre` (`213`): Teams 5–8 (BSIT-1A)
  - `Prof. Arsenio Macasaet` (`214`): Teams 9–12 (BSIT-1B)
  - `Prof. Teresita Buenaventura` (`215`): Teams 13–16 (BSIT-1B)
- **Zero Adviser Conflict**: Advisers never sit on their own advisee panels. All 10 faculty accounts from `sample_file/faculty_user/demo_faculty_import.csv` are used across chairs, panels, and instructors.
- **PIT Documenter Convention**: Matches DefenSYS PIT scheduling model where documenter is omitted from the schedule import timetable.
- **100% Unique Data**: All 64 students (`1065`–`1128`), emails, contact numbers, team names, and innovation projects are completely distinct from Set 1 and all other years.

---

## 📁 Included Files

| File | Type | Description |
|------|------|-------------|
| [students_1st_year_by_year_level.xlsx](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/USer/students_1st_year_by_year_level.xlsx) | **User Bulk Import (Excel)** | Registrar export (`USTP LIST OF ENROLLMENT` format) with 64 officially enrolled 1st Year students (`1065`–`1128`). Fully compatible with DefenSYS master cohort intake. |
| [students_1st_year_by_year_level.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/USer/students_1st_year_by_year_level.csv) | **User Bulk Import (CSV)** | CSV version of the 64-student freshman class list. |
| [Team16roster.xlsx](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/team/Team16roster.xlsx) | **Team Roster (Master Excel)** | Standard DefenSYS roster format featuring Section 1A (Different Systems) and Section 1B (One System) side-by-side with merged instructor blocks. |
| [team_roster_section_1A_different_systems.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/team/team_roster_section_1A_different_systems.csv) | **Team Roster (Section 1A CSV)** | 8 standalone freshman teams in Section 1A, each with an independent innovation project. |
| [team_roster_section_1B_one_system.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/team/team_roster_section_1B_one_system.csv) | **Team Roster (Section 1B CSV)** | 8 modular freshman teams in Section 1B collaborating on the *{SYSTEM_NAME_1B}* under PM {PROJECT_MANAGER_1B}. |
| [team_roster_combined_1A_and_1B.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/team/team_roster_combined_1A_and_1B.csv) | **Team Roster (Combined CSV)** | Sequential import file containing Section 1A followed by Section 1B for one-click team bulk intake. |
| [defense_schedule_import.xlsx](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/schedule/defense_schedule_import.xlsx) | **Defense Schedule (Excel)** | 16 scheduled pitch presentation slots with Chair and 3 Panel Members. Documenter column omitted per PIT rules. |
| [defense_schedule_import.csv](file:///c:/Users/Admin/Desktop/DefenSYS/sample_file/16_Teams_1st_Year_Set_2/1st%20Sem/schedule/defense_schedule_import.csv) | **Defense Schedule (CSV)** | Official 3-row preamble (`PIT Idea Pitch Defense`, `Dec 04 2026`, `Room 305`) CSV timetable. |

---

## 👥 Master Student & Team Allocation Matrix

- **Total Students**: 64 (All unique names, IDs, emails, contact numbers)
- **ID Numbers**: `1065` – `1128` (Default password equals ID number)
- **Team Size**: 4 members per team (1st member is Leader)

---

### Section BSIT-1A — Different Systems (8 Teams, 32 Students)
*Every team in Section 1A develops an independent, unique freshman PIT innovation project.*

#### Instructor: Eduardo Padilla (`212`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Innovation Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|---------------------------------------------------|
| **Team CodeSprint** | **Leader** | `1065` | Jethro Pascua | `1065@ustp.edu.ph` | 09171001065 | Campus Lost Keycard & RFID Tag Auto-Verification Kiosk |
| | Member | `1066` | Trisha Fermin | `1066@ustp.edu.ph` | 09171001066 | |
| | Member | `1067` | Alren Galvez | `1067@ustp.edu.ph` | 09171001067 | |
| | Member | `1068` | Kyla Sampang | `1068@ustp.edu.ph` | 09171001068 | |
| **Team BrainSync** | **Leader** | `1069` | Bryan Villaluz | `1069@ustp.edu.ph` | 09171001069 | Automated Class Attendance Verification via Bluetooth Low Energy Beacons |
| | Member | `1070` | Aira Tiamzon | `1070@ustp.edu.ph` | 09171001070 | |
| | Member | `1071` | Gideon Lumabas | `1071@ustp.edu.ph` | 09171001071 | |
| | Member | `1072` | Roxanne Sarmiento | `1072@ustp.edu.ph` | 09171001072 | |
| **Team DataNest** | **Leader** | `1073` | Warren Malabanan | `1073@ustp.edu.ph` | 09171001073 | Campus Cafeteria Nutrition Analyzer & Daily Meal Pre-Ordering Kiosk |
| | Member | `1074` | Ella Quisumbing | `1074@ustp.edu.ph` | 09171001074 | |
| | Member | `1075` | Alfonso Taruc | `1075@ustp.edu.ph` | 09171001075 | |
| | Member | `1076` | Jazmin Panlilio | `1076@ustp.edu.ph` | 09171001076 | |
| **Team SparkByte** | **Leader** | `1077` | Ezekiel Montealegre | `1077@ustp.edu.ph` | 09171001077 | Interactive Campus Map & Accessible Pathway Navigation for PWDs |
| | Member | `1078` | Cheska Dela Merced | `1078@ustp.edu.ph` | 09171001078 | |
| | Member | `1079` | Gelo Bautista | `1079@ustp.edu.ph` | 09171001079 | |
| | Member | `1080` | Princess Calderon | `1080@ustp.edu.ph` | 09171001080 | |

#### Instructor: Florencia Dela Torre (`213`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Innovation Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|---------------------------------------------------|
| **Team CloudNexus** | **Leader** | `1081` | Lester Venturina | `1081@ustp.edu.ph` | 09171001081 | Student Printing Credits Kiosk with Remote Mobile Document Queue |
| | Member | `1082` | Mariane Sevilla | `1082@ustp.edu.ph` | 09171001082 | |
| | Member | `1083` | Darwin Manalili | `1083@ustp.edu.ph` | 09171001083 | |
| | Member | `1084` | Charmel Tolentino | `1084@ustp.edu.ph` | 09171001084 | |
| **Team AlgoSphere** | **Leader** | `1085` | Jomar Alcantara | `1085@ustp.edu.ph` | 09171001085 | IoT-Based Classroom Power Conservation & Automated Light Controller |
| | Member | `1086` | Lourdes Ibarra | `1086@ustp.edu.ph` | 09171001086 | |
| | Member | `1087` | Renan Legaspi | `1087@ustp.edu.ph` | 09171001087 | |
| | Member | `1088` | Krizzia Mallari | `1088@ustp.edu.ph` | 09171001088 | |
| **Team CyberCraft** | **Leader** | `1089` | Marlon Valenciano | `1089@ustp.edu.ph` | 09171001089 | University Event Badge Scanner & Real-Time Headcount Sentinel |
| | Member | `1090` | Gellie Yuson | `1090@ustp.edu.ph` | 09171001090 | |
| | Member | `1091` | Rommel Aguilar | `1091@ustp.edu.ph` | 09171001091 | |
| | Member | `1092` | Jhoanna Zuniga | `1092@ustp.edu.ph` | 09171001092 | |
| **Team IntelliTech** | **Leader** | `1093` | Arjay Coronado | `1093@ustp.edu.ph` | 09171001093 | Digital Student Lockers with One-Time Password Retrieval Terminal |
| | Member | `1094` | Myra Fajardo | `1094@ustp.edu.ph` | 09171001094 | |
| | Member | `1095` | Jared Dimapilis | `1095@ustp.edu.ph` | 09171001095 | |
| | Member | `1096` | Shiela Barcelona | `1096@ustp.edu.ph` | 09171001096 | |

---

### Section BSIT-1B — One Shared System (8 Teams, 32 Students)
*All teams in Section 1B collaborate on modules of one overarching freshman ecosystem:*
- **System Name**: `{SYSTEM_NAME_1B}`
- **Project Manager**: `{PROJECT_MANAGER_1B}`

#### Instructor: Arsenio Macasaet (`214`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team UniConnectCore** | **Leader / PM** | `1097` | Lance San Pedro | `1097@ustp.edu.ph` | 09171001097 | Student Service Desk & Facilities Work Order Dispatch Module |
| | Member | `1098` | Kathleen Borja | `1098@ustp.edu.ph` | 09171001098 | |
| | Member | `1099` | Roderick Lacsamana | `1099@ustp.edu.ph` | 09171001099 | |
| | Member | `1100` | Hazel Obrero | `1100@ustp.edu.ph` | 09171001100 | |
| **Team UniConnectShuttle** | **Leader** | `1101` | Cedie Pangilinan | `1101@ustp.edu.ph` | 09171001101 | Campus Shuttle Real-Time Tracking & Station ETA Module |
| | Member | `1102` | Danica Samson | `1102@ustp.edu.ph` | 09171001102 | |
| | Member | `1103` | Gian Villanueva | `1103@ustp.edu.ph` | 09171001103 | |
| | Member | `1104` | Bernadette Cruzat | `1104@ustp.edu.ph` | 09171001104 | |
| **Team UniConnectFinder** | **Leader** | `1105` | Kervin Tolosa | `1105@ustp.edu.ph` | 09171001105 | Lost Property Digital Catalog & Biometric Claim Module |
| | Member | `1106` | Clarice Veloso | `1106@ustp.edu.ph` | 09171001106 | |
| | Member | `1107` | Aldrin Zafra | `1107@ustp.edu.ph` | 09171001107 | |
| | Member | `1108` | Mikaela Asuncion | `1108@ustp.edu.ph` | 09171001108 | |
| **Team UniConnectLab** | **Leader** | `1109` | Edgardo Beltran | `1109@ustp.edu.ph` | 09171001109 | IT Computer Laboratory Workstation Reservation & Usage Module |
| | Member | `1110` | Jemimah Carreon | `1110@ustp.edu.ph` | 09171001110 | |
| | Member | `1111` | Nico De Guzman | `1111@ustp.edu.ph` | 09171001111 | |
| | Member | `1112` | Abby Espiritu | `1112@ustp.edu.ph` | 09171001112 | |

#### Instructor: Teresita Buenaventura (`215`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team UniConnectClinic** | **Leader** | `1113` | Jayson Foronda | `1113@ustp.edu.ph` | 09171001113 | Student Health Center Queue & Medical Triage Module |
| | Member | `1114` | Trina Garcia | `1114@ustp.edu.ph` | 09171001114 | |
| | Member | `1115` | Mark Anthony Herrera | `1115@ustp.edu.ph` | 09171001115 | |
| | Member | `1116` | Giselle Ilagan | `1116@ustp.edu.ph` | 09171001116 | |
| **Team UniConnectEco** | **Leader** | `1117` | Kenneth Jalosjos | `1117@ustp.edu.ph` | 09171001117 | Campus Eco-Drop & Material Recycling Rewards Module |
| | Member | `1118` | Maricel Katindig | `1118@ustp.edu.ph` | 09171001118 | |
| | Member | `1119` | Elmer Laurel | `1119@ustp.edu.ph` | 09171001119 | |
| | Member | `1120` | Charmaine Manapat | `1120@ustp.edu.ph` | 09171001120 | |
| **Team UniConnectPods** | **Leader** | `1121` | Roderick Natividad | `1121@ustp.edu.ph` | 09171001121 | Silent Study Pods & Collaborative Space Booking Module |
| | Member | `1122` | Bea Oliveros | `1122@ustp.edu.ph` | 09171001122 | |
| | Member | `1123` | Jerome Padilla | `1123@ustp.edu.ph` | 09171001123 | |
| | Member | `1124` | Janelle Querubin | `1124@ustp.edu.ph` | 09171001124 | |
| **Team UniConnectSafe** | **Leader** | `1125` | Dominic Ramos | `1125@ustp.edu.ph` | 09171001125 | Campus Emergency Blue Light & Night Escort Sentinel Module |
| | Member | `1126` | Kirsten Salas | `1126@ustp.edu.ph` | 09171001126 | |
| | Member | `1127` | Rodel Tiamson | `1127@ustp.edu.ph` | 09171001127 | |
| | Member | `1128` | Stephanie Urbina | `1128@ustp.edu.ph` | 09171001128 | |

---

## 📅 Defense Schedule Matrix (`defense_schedule_import.xlsx` / `.csv`)

- **Stage**: `PIT Idea Pitch Defense`
- **Date**: `Dec 04 2026`
- **Venue**: `Room 305`

| Time Slot | Team Name | Section | Adviser | Chair | Panel Members |
|-----------|-----------|---------|---------|-------|---------------|
| 08:00 AM - 08:30 AM | Team CodeSprint | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 08:30 AM - 09:00 AM | Team BrainSync | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 09:00 AM - 09:30 AM | Team DataNest | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 09:30 AM - 10:00 AM | Team SparkByte | BSIT-1A | Eduardo Padilla | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 10:00 AM - 10:30 AM | Team CloudNexus | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 10:30 AM - 11:00 AM | Team AlgoSphere | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 11:00 AM - 11:30 AM | Team CyberCraft | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 11:30 AM - 12:00 PM | Team IntelliTech | BSIT-1A | Florencia Dela Torre | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Analiza Corpuz |
| 01:00 PM - 01:30 PM | Team UniConnectCore | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 01:30 PM - 02:00 PM | Team UniConnectShuttle | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 02:00 PM - 02:30 PM | Team UniConnectFinder | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 02:30 PM - 03:00 PM | Team UniConnectLab | BSIT-1B | Arsenio Macasaet | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 03:00 PM - 03:30 PM | Team UniConnectClinic | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 03:30 PM - 04:00 PM | Team UniConnectEco | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 04:00 PM - 04:30 PM | Team UniConnectPods | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |
| 04:30 PM - 05:00 PM | Team UniConnectSafe | BSIT-1B | Teresita Buenaventura | Maricel Suarez | Renato Villanueva, Jonathan Beltran, Ricardo Fontanilla |

> **Zero Conflict Guarantee**: Advisers never sit on their own advisee team's panel. All faculty allocations use verified IDs `206` through `215`.

---

## 🚀 Recommended Step-by-Step Import Workflow

### 1. Faculty Accounts
Import `sample_file/faculty_user/demo_faculty_import.csv` via:
`Admin -> User Management -> Faculty / General Users -> Bulk Import Users`

### 2. Student Batch Intake (By Year Level)
Import `students_1st_year_by_year_level.xlsx` (or `.csv`) via:
`Admin -> User Management -> Bulk Import -> By Year Level (Master Cohort Intake)`
*(Enrolls all 64 students 1065 to 1128 in 1st Year).*

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
    print("All 1st Year PIT Set 2 sample suite files successfully generated!")
