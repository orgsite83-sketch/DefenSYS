"""
Execution Tool: generate_2nd_year_pit_sample_suite.py
Generates the complete 2nd Year PIT (16 Teams, 64 Students) sample data suite:
1. User Import: students_2nd_year_by_year_level.xlsx & .csv
2. Team Roster: Team16roster.xlsx, team_roster_section_2A_different_systems.csv,
   team_roster_section_2B_one_system.csv, team_roster_combined_2A_and_2B.csv
3. Defense Schedule: defense_schedule_import.xlsx & .csv
4. Master Documentation: sample_file/16_Teams_2nd_Year/README.md
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
OUTPUT_DIR = os.path.join(BASE_DIR, "sample_file", "16_Teams_2nd_Year")
SEM_DIR = os.path.join(OUTPUT_DIR, "1st Sem")
USER_DIR = os.path.join(SEM_DIR, "USer")
TEAM_DIR = os.path.join(SEM_DIR, "team")
SCHED_DIR = os.path.join(SEM_DIR, "schedule")

os.makedirs(USER_DIR, exist_ok=True)
os.makedirs(TEAM_DIR, exist_ok=True)
os.makedirs(SCHED_DIR, exist_ok=True)

# ==============================================================================
# 1. MASTER STUDENTS AND TEAMS SPECIFICATION (2ND YEAR)
# ==============================================================================

# Section BSIT-2A: Different Systems (8 Teams, 32 Students)
STUDENTS_2A = [
    # Team 1: Team ByteCraft
    {"id": "2001", "last": "ZULUETA", "first": "Joshua", "gender": "M", "team": "Team ByteCraft", "project": "Automated Campus Dormitory Electricity Billing & Pre-Paid Metering System", "role": "Leader", "adviser": "Renato Villanueva"},
    {"id": "2002", "last": "BAUTISTA", "first": "Kristine", "gender": "F", "team": "Team ByteCraft", "project": "Automated Campus Dormitory Electricity Billing & Pre-Paid Metering System", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2003", "last": "SALVADOR", "first": "Aaron", "gender": "M", "team": "Team ByteCraft", "project": "Automated Campus Dormitory Electricity Billing & Pre-Paid Metering System", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2004", "last": "TAYAG", "first": "Marjorie", "gender": "F", "team": "Team ByteCraft", "project": "Automated Campus Dormitory Electricity Billing & Pre-Paid Metering System", "role": "Member", "adviser": "Renato Villanueva"},

    # Team 2: Team CodeSphere
    {"id": "2005", "last": "MERCADO", "first": "Anton", "gender": "M", "team": "Team CodeSphere", "project": "Interactive Laboratory Equipment Maintenance & QR Inspection Sentinel", "role": "Leader", "adviser": "Renato Villanueva"},
    {"id": "2006", "last": "PEREZ", "first": "Sheila", "gender": "F", "team": "Team CodeSphere", "project": "Interactive Laboratory Equipment Maintenance & QR Inspection Sentinel", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2007", "last": "DELFIN", "first": "Carlo", "gender": "M", "team": "Team CodeSphere", "project": "Interactive Laboratory Equipment Maintenance & QR Inspection Sentinel", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2008", "last": "YLAGAN", "first": "Maureen", "gender": "F", "team": "Team CodeSphere", "project": "Interactive Laboratory Equipment Maintenance & QR Inspection Sentinel", "role": "Member", "adviser": "Renato Villanueva"},

    # Team 3: Team NexusCore
    {"id": "2009", "last": "SANTILLAN", "first": "Angelo", "gender": "M", "team": "Team NexusCore", "project": "Smart Locker Biometric Retrieval & Parcel Depot Controller", "role": "Leader", "adviser": "Renato Villanueva"},
    {"id": "2010", "last": "GATMAITAN", "first": "Liezl", "gender": "F", "team": "Team NexusCore", "project": "Smart Locker Biometric Retrieval & Parcel Depot Controller", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2011", "last": "VELASCO", "first": "Ron", "gender": "M", "team": "Team NexusCore", "project": "Smart Locker Biometric Retrieval & Parcel Depot Controller", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2012", "last": "MANZANO", "first": "Irene", "gender": "F", "team": "Team NexusCore", "project": "Smart Locker Biometric Retrieval & Parcel Depot Controller", "role": "Member", "adviser": "Renato Villanueva"},

    # Team 4: Team DataVibe
    {"id": "2013", "last": "BALMES", "first": "Kurt", "gender": "M", "team": "Team DataVibe", "project": "University Library Noise Monitoring & Quiet Zone Alert Station", "role": "Leader", "adviser": "Renato Villanueva"},
    {"id": "2014", "last": "OLEA", "first": "Abigail", "gender": "F", "team": "Team DataVibe", "project": "University Library Noise Monitoring & Quiet Zone Alert Station", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2015", "last": "CASTOR", "first": "Neil", "gender": "M", "team": "Team DataVibe", "project": "University Library Noise Monitoring & Quiet Zone Alert Station", "role": "Member", "adviser": "Renato Villanueva"},
    {"id": "2016", "last": "SAMSON", "first": "Rowena", "gender": "F", "team": "Team DataVibe", "project": "University Library Noise Monitoring & Quiet Zone Alert Station", "role": "Member", "adviser": "Renato Villanueva"},

    # Team 5: Team CloudPulse
    {"id": "2017", "last": "ESTRELLA", "first": "Noel", "gender": "M", "team": "Team CloudPulse", "project": "Campus Lost & Found Property Recovery & Image-Matching Registry", "role": "Leader", "adviser": "Jonathan Beltran"},
    {"id": "2018", "last": "MACARAEG", "first": "Jenny", "gender": "F", "team": "Team CloudPulse", "project": "Campus Lost & Found Property Recovery & Image-Matching Registry", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2019", "last": "BUENAVENTURA", "first": "Gerald", "gender": "M", "team": "Team CloudPulse", "project": "Campus Lost & Found Property Recovery & Image-Matching Registry", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2020", "last": "PASCUAL", "first": "Melanie", "gender": "F", "team": "Team CloudPulse", "project": "Campus Lost & Found Property Recovery & Image-Matching Registry", "role": "Member", "adviser": "Jonathan Beltran"},

    # Team 6: Team AlgoNest
    {"id": "2021", "last": "LABRADOR", "first": "Russell", "gender": "M", "team": "Team AlgoNest", "project": "Peer-to-Peer Academic Textbook & Study Material Exchange Portal", "role": "Leader", "adviser": "Jonathan Beltran"},
    {"id": "2022", "last": "TAMPOS", "first": "Cherry", "gender": "F", "team": "Team AlgoNest", "project": "Peer-to-Peer Academic Textbook & Study Material Exchange Portal", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2023", "last": "CORPUZ", "first": "Vincent", "gender": "M", "team": "Team AlgoNest", "project": "Peer-to-Peer Academic Textbook & Study Material Exchange Portal", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2024", "last": "MADRIGAL", "first": "Elaine", "gender": "F", "team": "Team AlgoNest", "project": "Peer-to-Peer Academic Textbook & Study Material Exchange Portal", "role": "Member", "adviser": "Jonathan Beltran"},

    # Team 7: Team SynapseIT
    {"id": "2025", "last": "VELASQUEZ", "first": "Alden", "gender": "M", "team": "Team SynapseIT", "project": "Automated Attendance Verification with Ultrasonic Beacon Sensors", "role": "Leader", "adviser": "Jonathan Beltran"},
    {"id": "2026", "last": "DAGOHOY", "first": "Giselle", "gender": "F", "team": "Team SynapseIT", "project": "Automated Attendance Verification with Ultrasonic Beacon Sensors", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2027", "last": "TOLENTINO", "first": "Roderick", "gender": "M", "team": "Team SynapseIT", "project": "Automated Attendance Verification with Ultrasonic Beacon Sensors", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2028", "last": "EVANGELISTA", "first": "Karen", "gender": "F", "team": "Team SynapseIT", "project": "Automated Attendance Verification with Ultrasonic Beacon Sensors", "role": "Member", "adviser": "Jonathan Beltran"},

    # Team 8: Team PixelForge
    {"id": "2029", "last": "SISON", "first": "Marco", "gender": "M", "team": "Team PixelForge", "project": "Cafeteria Pre-Ordering & Nutritious Meal Recommendation Hub", "role": "Leader", "adviser": "Jonathan Beltran"},
    {"id": "2030", "last": "OCAMPO", "first": "Cristine", "gender": "F", "team": "Team PixelForge", "project": "Cafeteria Pre-Ordering & Nutritious Meal Recommendation Hub", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2031", "last": "AGUILERA", "first": "Dexter", "gender": "M", "team": "Team PixelForge", "project": "Cafeteria Pre-Ordering & Nutritious Meal Recommendation Hub", "role": "Member", "adviser": "Jonathan Beltran"},
    {"id": "2032", "last": "MORATALLA", "first": "Rona", "gender": "F", "team": "Team PixelForge", "project": "Cafeteria Pre-Ordering & Nutritious Meal Recommendation Hub", "role": "Member", "adviser": "Jonathan Beltran"},
]

# Section BSIT-2B: One System (8 Teams, 32 Students)
SYSTEM_NAME_2B = "Societree: Campus Organizations & Student Guild Management Ecosystem"
PROJECT_MANAGER_2B = "Nathan Cabahug"

STUDENTS_2B = [
    # Team 9: Team SocietreeCore (Module 1)
    {"id": "2033", "last": "CABAHUG", "first": "Nathan", "gender": "M", "team": "Team SocietreeCore", "module": "Core Organization Directory & Membership Governance Module", "role": "Leader / PM", "adviser": "Analiza Corpuz"},
    {"id": "2034", "last": "DAYAP", "first": "Kristine", "gender": "F", "team": "Team SocietreeCore", "module": "Core Organization Directory & Membership Governance Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2035", "last": "PACTORAN", "first": "Maiko", "gender": "M", "team": "Team SocietreeCore", "module": "Core Organization Directory & Membership Governance Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2036", "last": "MANIABO", "first": "Eron", "gender": "F", "team": "Team SocietreeCore", "module": "Core Organization Directory & Membership Governance Module", "role": "Member", "adviser": "Analiza Corpuz"},

    # Team 10: Team SocietreeAuth (Module 2)
    {"id": "2037", "last": "DUMA-OG", "first": "Franz", "gender": "M", "team": "Team SocietreeAuth", "module": "Multi-Factor Identity Verification & SSO Gateway Module", "role": "Leader", "adviser": "Analiza Corpuz"},
    {"id": "2038", "last": "CAMPOS", "first": "Ana Marie", "gender": "F", "team": "Team SocietreeAuth", "module": "Multi-Factor Identity Verification & SSO Gateway Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2039", "last": "PATIGAYON", "first": "Aaron John", "gender": "M", "team": "Team SocietreeAuth", "module": "Multi-Factor Identity Verification & SSO Gateway Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2040", "last": "BARON", "first": "Efren", "gender": "F", "team": "Team SocietreeAuth", "module": "Multi-Factor Identity Verification & SSO Gateway Module", "role": "Member", "adviser": "Analiza Corpuz"},

    # Team 11: Team SocietreeEvents (Module 3)
    {"id": "2041", "last": "CANDAWAN", "first": "Arvin", "gender": "M", "team": "Team SocietreeEvents", "module": "Campus Events Calendar & Venue Reservation Module", "role": "Leader", "adviser": "Analiza Corpuz"},
    {"id": "2042", "last": "YANOYAN", "first": "Jessica", "gender": "F", "team": "Team SocietreeEvents", "module": "Campus Events Calendar & Venue Reservation Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2043", "last": "JUMAMIL", "first": "Rey", "gender": "M", "team": "Team SocietreeEvents", "module": "Campus Events Calendar & Venue Reservation Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2044", "last": "CALIB", "first": "Nora", "gender": "F", "team": "Team SocietreeEvents", "module": "Campus Events Calendar & Venue Reservation Module", "role": "Member", "adviser": "Analiza Corpuz"},

    # Team 12: Team SocietreeFinance (Module 4)
    {"id": "2045", "last": "SALAC", "first": "Xian", "gender": "M", "team": "Team SocietreeFinance", "module": "Student Organization Financial Ledger & Petty Cash Module", "role": "Leader", "adviser": "Analiza Corpuz"},
    {"id": "2046", "last": "PARAMIS", "first": "Earl", "gender": "M", "team": "Team SocietreeFinance", "module": "Student Organization Financial Ledger & Petty Cash Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2047", "last": "OMAGUING", "first": "Alianah", "gender": "F", "team": "Team SocietreeFinance", "module": "Student Organization Financial Ledger & Petty Cash Module", "role": "Member", "adviser": "Analiza Corpuz"},
    {"id": "2048", "last": "VELASQUEZ", "first": "Romy", "gender": "M", "team": "Team SocietreeFinance", "module": "Student Organization Financial Ledger & Petty Cash Module", "role": "Member", "adviser": "Analiza Corpuz"},

    # Team 13: Team SocietreeElection (Module 5)
    {"id": "2049", "last": "BAGUINGCO", "first": "Tristan", "gender": "M", "team": "Team SocietreeElection", "module": "Automated Election Balloting & Digital Audit Module", "role": "Leader", "adviser": "Ricardo Fontanilla"},
    {"id": "2050", "last": "IGOY", "first": "Jennifer", "gender": "F", "team": "Team SocietreeElection", "module": "Automated Election Balloting & Digital Audit Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2051", "last": "BAROT", "first": "Michael", "gender": "M", "team": "Team SocietreeElection", "module": "Automated Election Balloting & Digital Audit Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2052", "last": "TAMPOS", "first": "Leilani", "gender": "F", "team": "Team SocietreeElection", "module": "Automated Election Balloting & Digital Audit Module", "role": "Member", "adviser": "Ricardo Fontanilla"},

    # Team 14: Team SocietreePublic (Module 6)
    {"id": "2053", "last": "MENDOZA", "first": "Clark", "gender": "M", "team": "Team SocietreePublic", "module": "Publications & Editorial Gazette Dispatch Module", "role": "Leader", "adviser": "Ricardo Fontanilla"},
    {"id": "2054", "last": "SUAREZ", "first": "Rachelle", "gender": "F", "team": "Team SocietreePublic", "module": "Publications & Editorial Gazette Dispatch Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2055", "last": "BELTRAN", "first": "Dennis", "gender": "M", "team": "Team SocietreePublic", "module": "Publications & Editorial Gazette Dispatch Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2056", "last": "VILLAR", "first": "Hazel", "gender": "F", "team": "Team SocietreePublic", "module": "Publications & Editorial Gazette Dispatch Module", "role": "Member", "adviser": "Ricardo Fontanilla"},

    # Team 15: Team SocietreeCert (Module 7)
    {"id": "2057", "last": "QUIAMBAO", "first": "Erwin", "gender": "M", "team": "Team SocietreeCert", "module": "Micro-Credentialing & Certificates Authentication Module", "role": "Leader", "adviser": "Ricardo Fontanilla"},
    {"id": "2058", "last": "ALONZO", "first": "Katherine", "gender": "F", "team": "Team SocietreeCert", "module": "Micro-Credentialing & Certificates Authentication Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2059", "last": "MALABANAN", "first": "Joseph", "gender": "M", "team": "Team SocietreeCert", "module": "Micro-Credentialing & Certificates Authentication Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2060", "last": "CORTEZ", "first": "Judy", "gender": "F", "team": "Team SocietreeCert", "module": "Micro-Credentialing & Certificates Authentication Module", "role": "Member", "adviser": "Ricardo Fontanilla"},

    # Team 16: Team SocietreeFeed (Module 8)
    {"id": "2061", "last": "LACSON", "first": "Roderick", "gender": "M", "team": "Team SocietreeFeed", "module": "Student Activity Feed & Community Announcements Module", "role": "Leader", "adviser": "Ricardo Fontanilla"},
    {"id": "2062", "last": "DEL MUNDO", "first": "Joanna", "gender": "F", "team": "Team SocietreeFeed", "module": "Student Activity Feed & Community Announcements Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2063", "last": "SERRANO", "first": "Gilbert", "gender": "M", "team": "Team SocietreeFeed", "module": "Student Activity Feed & Community Announcements Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
    {"id": "2064", "last": "RAMIREZ", "first": "Theresa", "gender": "F", "team": "Team SocietreeFeed", "module": "Student Activity Feed & Community Announcements Module", "role": "Member", "adviser": "Ricardo Fontanilla"},
]

ALL_STUDENTS_2 = STUDENTS_2A + STUDENTS_2B
for s in ALL_STUDENTS_2:
    s["full_name"] = f"{s['first']} {s['last']}"
    s["formal_name"] = f"{s['last']}, {s['first']}"
    s["email"] = f"{s['id']}@ustp.edu.ph"
    s["contact"] = f"0917100{s['id']}"

# ==============================================================================
# 2. GENERATE USER IMPORT FILES (.xlsx & .csv)
# ==============================================================================

def generate_user_import_files():
    csv_path = os.path.join(USER_DIR, "students_2nd_year_by_year_level.csv")
    xlsx_path = os.path.join(USER_DIR, "students_2nd_year_by_year_level.xlsx")

    # CSV Generation (USTP Registrar Format)
    rows_csv = [
        ["LIST OF ENROLLMENT", "", "", "", "", "", "", "", "", "", "", ""],
        ["2026-2027 1st Semester", "", "", "", "", "", "", "", "", "", "", ""],
        ["", "Program", "Registered", "Officially Enrolled", "", "", "", "", "", "", "", ""],
        ["", "Bachelor of Science in Information Technology", "64", "64", "", "", "", "", "", "", "", ""],
        ["", "TOTAL", "", "", "", "", "", "", "", "", "", ""],
        ["", "", "64", "64", "", "", "", "", "", "", "", ""],
        ["LIST OF ENROLLMENT", "", "", "", "", "", "", "", "", "", "", ""],
        ["2026-2027 1st Semester", "", "", "", "", "", "", "", "", "", "", ""],
        ["Bachelor of Science in Information Technology", "", "", "", "", "", "", "", "", "", "", ""],
        ["", "#", "Student No", "Name", "Program", "Major", "Level", "", "Gender", "Status", "Date", "Date"],
    ]

    for idx, s in enumerate(ALL_STUDENTS_2, start=1):
        rows_csv.append([
            "",
            str(idx),
            s["id"],
            f'"{s["formal_name"]}"',
            "BSIT",
            "",
            "2nd Year",
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
    # Left: Table 1 Headers (BSIT-2A Different Systems)
    format_cell(ws.cell(row=4, column=2), "Team Name:", align_left)
    format_cell(ws.cell(row=4, column=3), "PIT Project", align_left)
    format_cell(ws.cell(row=4, column=4), "Section", align_center)
    format_cell(ws.cell(row=4, column=5), "Instructor", align_center)
    format_cell(ws.cell(row=4, column=6), "Team Members", align_left)

    # Right: System Name metadata (BSIT-2B One System)
    format_cell(ws.cell(row=4, column=8), "System Name:", align_left)
    format_cell(ws.cell(row=4, column=9), SYSTEM_NAME_2B, align_left)

    # Row 5:
    format_cell(ws.cell(row=5, column=8), "Project Manager:", align_left)
    format_cell(ws.cell(row=5, column=9), PROJECT_MANAGER_2B, align_left)

    # Row 6:
    # Right: Table 2 Headers
    format_cell(ws.cell(row=6, column=8), "Team Name:", align_left)
    format_cell(ws.cell(row=6, column=9), "Module", align_left)
    format_cell(ws.cell(row=6, column=10), "Section", align_center)
    format_cell(ws.cell(row=6, column=11), "Instructor", align_center)
    format_cell(ws.cell(row=6, column=12), "Team Members", align_left)

    # Teams grouping
    teams_2a = [STUDENTS_2A[i:i+4] for i in range(0, len(STUDENTS_2A), 4)]
    teams_2b = [STUDENTS_2B[i:i+4] for i in range(0, len(STUDENTS_2B), 4)]

    # Left Side: BSIT-2A Different Systems (Rows 5 to 36)
    for t_idx in range(8):
        t2a = teams_2a[t_idx]
        start_r = 5 + t_idx * 4

        for r_offset in range(4):
            curr_r = start_r + r_offset
            top_b = thin if r_offset == 0 else None
            bot_b = thin if r_offset == 3 else None
            block_border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)

            cell_b = ws.cell(row=curr_r, column=2)
            if r_offset == 0:
                cell_b.value = t2a[0]["team"]
            cell_b.font = font_regular
            cell_b.alignment = align_left
            cell_b.border = block_border

            cell_c = ws.cell(row=curr_r, column=3)
            if r_offset == 0:
                cell_c.value = t2a[0]["project"]
            cell_c.font = font_regular
            cell_c.alignment = align_left
            cell_c.border = block_border

            cell_f = ws.cell(row=curr_r, column=6, value=t2a[r_offset]["full_name"])
            cell_f.font = font_regular
            cell_f.alignment = align_left
            cell_f.border = block_border

    # Right Side: BSIT-2B One System (Rows 7 to 38)
    for t_idx in range(8):
        t2b = teams_2b[t_idx]
        start_r = 7 + t_idx * 4

        for r_offset in range(4):
            curr_r = start_r + r_offset
            top_b = thin if r_offset == 0 else None
            bot_b = thin if r_offset == 3 else None
            block_border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)

            cell_h = ws.cell(row=curr_r, column=8)
            if r_offset == 0:
                cell_h.value = t2b[0]["team"]
            cell_h.font = font_regular
            cell_h.alignment = align_left
            cell_h.border = block_border

            cell_i = ws.cell(row=curr_r, column=9)
            if r_offset == 0:
                cell_i.value = t2b[0]["module"]
            cell_i.font = font_regular
            cell_i.alignment = align_left
            cell_i.border = block_border

            cell_l = ws.cell(row=curr_r, column=12, value=t2b[r_offset]["full_name"])
            cell_l.font = font_regular
            cell_l.alignment = align_left
            cell_l.border = block_border

    # Merged Columns:
    # Col D: Section BSIT-2A (Rows 5 to 36)
    ws.merge_cells("D5:D36")
    for r in range(5, 37):
        cell = ws.cell(row=r, column=4)
        top_b = thin if r == 5 else None
        bot_b = thin if r == 36 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=5, column=4, value="BSIT-2A")

    # Col E: Advisers 2A
    # Teams 1-4 (Rows 5 to 20): Renato Villanueva
    ws.merge_cells("E5:E20")
    for r in range(5, 21):
        cell = ws.cell(row=r, column=5)
        top_b = thin if r == 5 else None
        bot_b = thin if r == 20 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=5, column=5, value="Renato Villanueva")

    # Teams 5-8 (Rows 21 to 36): Jonathan Beltran
    ws.merge_cells("E21:E36")
    for r in range(21, 37):
        cell = ws.cell(row=r, column=5)
        top_b = thin if r == 21 else None
        bot_b = thin if r == 36 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=21, column=5, value="Jonathan Beltran")

    # Col J: Section BSIT-2B (Rows 7 to 38)
    ws.merge_cells("J7:J38")
    for r in range(7, 39):
        cell = ws.cell(row=r, column=10)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=10, value="BSIT-2B")

    # Col K: Advisers 2B
    # Teams 9-12 (Rows 7 to 22): Analiza Corpuz
    ws.merge_cells("K7:K22")
    for r in range(7, 23):
        cell = ws.cell(row=r, column=11)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 22 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=11, value="Analiza Corpuz")

    # Teams 13-16 (Rows 23 to 38): Ricardo Fontanilla
    ws.merge_cells("K23:K38")
    for r in range(23, 39):
        cell = ws.cell(row=r, column=12)
        top_b = thin if r == 23 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=23, column=12, value="Ricardo Fontanilla")

    wb.save(xlsx_path)
    fix_xlsx_for_dart_compatibility(xlsx_path)
    print(f"Generated: {xlsx_path}")

    # Generate CSV Variations
    # 1. Section 2A Standalone CSV (Different Systems)
    csv_2a_path = os.path.join(TEAM_DIR, "team_roster_section_2A_different_systems.csv")
    with open(csv_2a_path, "w", newline="", encoding="utf-8") as f:
        f.write("Team Name,PIT Project,Section,Instructor,Team Members\n")
        for t in teams_2a:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["project"]}","BSIT-2A","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_2a_path}")

    # 2. Section 2B Standalone CSV (One System)
    csv_2b_path = os.path.join(TEAM_DIR, "team_roster_section_2B_one_system.csv")
    with open(csv_2b_path, "w", newline="", encoding="utf-8") as f:
        f.write(f"System Name,{SYSTEM_NAME_2B}\n")
        f.write(f"Project Manager,{PROJECT_MANAGER_2B}\n")
        f.write("Team Name,Module,Section,Instructor,Team Members\n")
        for t in teams_2b:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["module"]}","BSIT-2B","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_2b_path}")

    # 3. Combined 2A & 2B CSV
    csv_combined_path = os.path.join(TEAM_DIR, "team_roster_combined_2A_and_2B.csv")
    with open(csv_combined_path, "w", newline="", encoding="utf-8") as f:
        # Section 2A block (Different Systems)
        f.write("Team Name,PIT Project,Section,Instructor,Team Members\n")
        for t in teams_2a:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["project"]}","BSIT-2A","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
        f.write("\n")
        # Section 2B block (One System)
        f.write(f"System Name,{SYSTEM_NAME_2B}\n")
        f.write(f"Project Manager,{PROJECT_MANAGER_2B}\n")
        f.write("Team Name,Module,Section,Instructor,Team Members\n")
        for t in teams_2b:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["module"]}","BSIT-2B","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_combined_path}")

# ==============================================================================
# 4. GENERATE DEFENSE SCHEDULE FILES (.xlsx & .csv)
# ==============================================================================

def generate_defense_schedule_files():
    xlsx_path = os.path.join(SCHED_DIR, "defense_schedule_import.xlsx")
    csv_path = os.path.join(SCHED_DIR, "defense_schedule_import.csv")

    stage = "PIT Prototype Defense"
    date_str = "Dec 11 2026"
    room_str = "Room 303"

    schedule_data = [
        # BSIT-2A Morning Session (Teams 1 - 8)
        {"time": "8:00AM-8:30AM", "team": "Team ByteCraft", "adviser": "Renato Villanueva", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "8:30AM-9:00AM", "team": "Team CodeSphere", "adviser": "Renato Villanueva", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "9:00AM-9:30AM", "team": "Team NexusCore", "adviser": "Renato Villanueva", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "9:30AM-10:00AM", "team": "Team DataVibe", "adviser": "Renato Villanueva", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "10:00AM-10:30AM", "team": "Team CloudPulse", "adviser": "Jonathan Beltran", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "10:30AM-11:00AM", "team": "Team AlgoNest", "adviser": "Jonathan Beltran", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "11:00AM-11:30AM", "team": "Team SynapseIT", "adviser": "Jonathan Beltran", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},
        {"time": "11:30AM-12:00PM", "team": "Team PixelForge", "adviser": "Jonathan Beltran", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Arsenio Macasaet"},

        # BSIT-2B Afternoon Session (Teams 9 - 16)
        {"time": "1:00PM-1:30PM", "team": "Team SocietreeCore", "adviser": "Analiza Corpuz", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "1:30PM-2:00PM", "team": "Team SocietreeAuth", "adviser": "Analiza Corpuz", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "2:00PM-2:30PM", "team": "Team SocietreeEvents", "adviser": "Analiza Corpuz", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "2:30PM-3:00PM", "team": "Team SocietreeFinance", "adviser": "Analiza Corpuz", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "3:00PM-3:30PM", "team": "Team SocietreeElection", "adviser": "Ricardo Fontanilla", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "3:30PM-4:00PM", "team": "Team SocietreePublic", "adviser": "Ricardo Fontanilla", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "4:00PM-4:30PM", "team": "Team SocietreeCert", "adviser": "Ricardo Fontanilla", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
        {"time": "4:30PM-5:00PM", "team": "Team SocietreeFeed", "adviser": "Ricardo Fontanilla", "chair": "Maricel Suarez", "p1": "Eduardo Padilla", "p2": "Florencia Dela Torre", "p3": "Teresita Buenaventura"},
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
    content = f"""# DefenSYS 2nd Year PIT Demo Suite (16 Teams, 64 Students)

This dataset provides a complete, production-ready sample suite for **2nd Year PIT (Project Innovation and Technology 2)** in DefenSYS configured according to the curriculum model:
- **Section BSIT-2A**: **Different Systems Format** (8 teams developing independent, standalone PIT innovation projects)
- **Section BSIT-2B**: **One System Format** (8 teams developing specialized modules of *{SYSTEM_NAME_2B}*, PM: *{PROJECT_MANAGER_2B}*)
- **4 Advised Teams per Adviser / Instructor**:
  - `Prof. Renato Villanueva` (`210`): Teams 1–4 (BSIT-2A) — *2nd Year PIT Lead*
  - `Prof. Jonathan Beltran` (`208`): Teams 5–8 (BSIT-2A)
  - `Prof. Analiza Corpuz` (`209`): Teams 9–12 (BSIT-2B)
  - `Prof. Ricardo Fontanilla` (`206`): Teams 13–16 (BSIT-2B)
- **Zero Adviser Conflict**: Advisers never sit on their own advisee panels. All 10 faculty accounts from `sample_file/faculty_user/demo_faculty_import.csv` are used across chairs, panels, and instructors.
- **PIT Documenter Convention**: Matches DefenSYS PIT scheduling model where documenter is omitted from the schedule import timetable.

---

## 📁 Included Files

| File | Type | Description |
|------|------|-------------|
| [students_2nd_year_by_year_level.xlsx](file:///{os.path.join(USER_DIR, 'students_2nd_year_by_year_level.xlsx').replace('\\', '/')}) | **Student Bulk Import (Excel)** | Registrar export (**USTP LIST OF ENROLLMENT** format) for all 64 students (`2001`–`2064`) in 2nd Year. |
| [students_2nd_year_by_year_level.csv](file:///{os.path.join(USER_DIR, 'students_2nd_year_by_year_level.csv').replace('\\', '/')}) | **Student Bulk Import (CSV)** | CSV version of the 64-student intake cohort. |
| [Team16roster.xlsx](file:///{os.path.join(TEAM_DIR, 'Team16roster.xlsx').replace('\\', '/')}) | **Team Roster (Excel)** | Unified side-by-side template containing Section BSIT-2A (Different Systems on Left) and Section BSIT-2B (One System on Right). |
| [team_roster_section_2A_different_systems.csv](file:///{os.path.join(TEAM_DIR, 'team_roster_section_2A_different_systems.csv').replace('\\', '/')}) | **Team Roster (Section 2A - Different Systems)** | 8 teams developing independent PIT projects under Advisers Renato Villanueva and Jonathan Beltran. |
| [team_roster_section_2B_one_system.csv](file:///{os.path.join(TEAM_DIR, 'team_roster_section_2B_one_system.csv').replace('\\', '/')}) | **Team Roster (Section 2B - One System)** | 8 teams collaborating on *{SYSTEM_NAME_2B}* under Advisers Analiza Corpuz and Ricardo Fontanilla. |
| [team_roster_combined_2A_and_2B.csv](file:///{os.path.join(TEAM_DIR, 'team_roster_combined_2A_and_2B.csv').replace('\\', '/')}) | **Team Roster (Combined 2A & 2B CSV)** | Single sequential import file with Section 2A Different Systems and Section 2B One System. |
| [defense_schedule_import.xlsx](file:///{os.path.join(SCHED_DIR, 'defense_schedule_import.xlsx').replace('\\', '/')}) | **Defense Schedule (Excel)** | Official 3-row preamble format (`2nd Year Innovation Expo`, `Dec 11 2026`, `Room 303`) with 16 defense slots and faculty panel allocations. |
| [defense_schedule_import.csv](file:///{os.path.join(SCHED_DIR, 'defense_schedule_import.csv').replace('\\', '/')}) | **Defense Schedule (CSV)** | CSV version of the 16-slot defense schedule. |

---

## 👥 Master Student & Team Allocation Matrix

- **Total Students**: 64 (All unique names, IDs, emails, contact numbers)
- **ID Numbers**: `2001` – `2064` (Default password equals ID number)
- **Team Size**: 4 members per team (1st member is Leader)

---

### Section BSIT-2A — Different Systems (8 Teams, 32 Students)

#### Instructor / Adviser: Prof. Renato Villanueva (`210`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|----------------------------------------|
| **Team ByteCraft** | **Leader** | `2001` | Joshua Zulueta | `2001@ustp.edu.ph` | 09171002001 | Automated Campus Dormitory Electricity Billing & Pre-Paid Metering System |
| | Member | `2002` | Kristine Bautista | `2002@ustp.edu.ph` | 09171002002 | |
| | Member | `2003` | Aaron Salvador | `2003@ustp.edu.ph` | 09171002003 | |
| | Member | `2004` | Marjorie Tayag | `2004@ustp.edu.ph` | 09171002004 | |
| **Team CodeSphere** | **Leader** | `2005` | Anton Mercado | `2005@ustp.edu.ph` | 09171002005 | Interactive Laboratory Equipment Maintenance & QR Inspection Sentinel |
| | Member | `2006` | Sheila Perez | `2006@ustp.edu.ph` | 09171002006 | |
| | Member | `2007` | Carlo Delfin | `2007@ustp.edu.ph` | 09171002007 | |
| | Member | `2008` | Maureen Ylagan | `2008@ustp.edu.ph` | 09171002008 | |
| **Team NexusCore** | **Leader** | `2009` | Angelo Santillan | `2009@ustp.edu.ph` | 09171002009 | Smart Locker Biometric Retrieval & Parcel Depot Controller |
| | Member | `2010` | Liezl Gatmaitan | `2010@ustp.edu.ph` | 09171002010 | |
| | Member | `2011` | Ron Velasco | `2011@ustp.edu.ph` | 09171002011 | |
| | Member | `2012` | Irene Manzano | `2012@ustp.edu.ph` | 09171002012 | |
| **Team DataVibe** | **Leader** | `2013` | Kurt Balmes | `2013@ustp.edu.ph` | 09171002013 | University Library Noise Monitoring & Quiet Zone Alert Station |
| | Member | `2014` | Abigail Olea | `2014@ustp.edu.ph` | 09171002014 | |
| | Member | `2015` | Neil Castor | `2015@ustp.edu.ph` | 09171002015 | |
| | Member | `2016` | Rowena Samson | `2016@ustp.edu.ph` | 09171002016 | |

#### Instructor / Adviser: Prof. Jonathan Beltran (`208`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|----------------------------------------|
| **Team CloudPulse** | **Leader** | `2017` | Noel Estrella | `2017@ustp.edu.ph` | 09171002017 | Campus Lost & Found Property Recovery & Image-Matching Registry |
| | Member | `2018` | Jenny Macaraeg | `2018@ustp.edu.ph` | 09171002018 | |
| | Member | `2019` | Gerald Buenaventura | `2019@ustp.edu.ph` | 09171002019 | |
| | Member | `2020` | Melanie Pascual | `2020@ustp.edu.ph` | 09171002020 | |
| **Team AlgoNest** | **Leader** | `2021` | Russell Labrador | `2021@ustp.edu.ph` | 09171002021 | Peer-to-Peer Academic Textbook & Study Material Exchange Portal |
| | Member | `2022` | Cherry Tampos | `2022@ustp.edu.ph` | 09171002022 | |
| | Member | `2023` | Vincent Corpuz | `2023@ustp.edu.ph` | 09171002023 | |
| | Member | `2024` | Elaine Madrigal | `2024@ustp.edu.ph` | 09171002024 | |
| **Team SynapseIT** | **Leader** | `2025` | Alden Velasquez | `2025@ustp.edu.ph` | 09171002025 | Automated Attendance Verification with Ultrasonic Beacon Sensors |
| | Member | `2026` | Giselle Dagohoy | `2026@ustp.edu.ph` | 09171002026 | |
| | Member | `2027` | Roderick Tolentino | `2027@ustp.edu.ph` | 09171002027 | |
| | Member | `2028` | Karen Evangelista | `2028@ustp.edu.ph` | 09171002028 | |
| **Team PixelForge** | **Leader** | `2029` | Marco Sison | `2029@ustp.edu.ph` | 09171002029 | Cafeteria Pre-Ordering & Nutritious Meal Recommendation Hub |
| | Member | `2030` | Cristine Ocampo | `2030@ustp.edu.ph` | 09171002030 | |
| | Member | `2031` | Dexter Aguilera | `2031@ustp.edu.ph` | 09171002031 | |
| | Member | `2032` | Rona Moratalla | `2032@ustp.edu.ph` | 09171002032 | |

---

### Section BSIT-2B — One Shared System (8 Teams, 32 Students)
- **System Name**: `{SYSTEM_NAME_2B}`
- **Project Manager**: `{PROJECT_MANAGER_2B}` (`2033`)

#### Instructor / Adviser: Prof. Analiza Corpuz (`209`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team SocietreeCore** | **Leader / PM** | `2033` | Nathan Cabahug | `2033@ustp.edu.ph` | 09171002033 | Core Organization Directory & Membership Governance Module |
| | Member | `2034` | Kristine Dayap | `2034@ustp.edu.ph` | 09171002034 | |
| | Member | `2035` | Maiko Pactoran | `2035@ustp.edu.ph` | 09171002035 | |
| | Member | `2036` | Eron Maniabo | `2036@ustp.edu.ph` | 09171002036 | |
| **Team SocietreeAuth** | **Leader** | `2037` | Franz Duma-og | `2037@ustp.edu.ph` | 09171002037 | Multi-Factor Identity Verification & SSO Gateway Module |
| | Member | `2038` | Ana Marie Campos | `2038@ustp.edu.ph` | 09171002038 | |
| | Member | `2039` | Aaron John Patigayon | `2039@ustp.edu.ph` | 09171002039 | |
| | Member | `2040` | Efren Baron | `2040@ustp.edu.ph` | 09171002040 | |
| **Team SocietreeEvents** | **Leader** | `2041` | Arvin Candawan | `2041@ustp.edu.ph` | 09171002041 | Campus Events Calendar & Venue Reservation Module |
| | Member | `2042` | Jessica Yanoyan | `2042@ustp.edu.ph` | 09171002042 | |
| | Member | `2043` | Rey Jumamil | `2043@ustp.edu.ph` | 09171002043 | |
| | Member | `2044` | Nora Calib | `2044@ustp.edu.ph` | 09171002044 | |
| **Team SocietreeFinance** | **Leader** | `2045` | Xian Salac | `2045@ustp.edu.ph` | 09171002045 | Student Organization Financial Ledger & Petty Cash Module |
| | Member | `2046` | Earl Paramis | `2046@ustp.edu.ph` | 09171002046 | |
| | Member | `2047` | Alianah Omaguing | `2047@ustp.edu.ph` | 09171002047 | |
| | Member | `2048` | Romy Velasquez | `2048@ustp.edu.ph` | 09171002048 | |

#### Instructor / Adviser: Prof. Ricardo Fontanilla (`206`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team SocietreeElection** | **Leader** | `2049` | Tristan Baguingco | `2049@ustp.edu.ph` | 09171002049 | Automated Election Balloting & Digital Audit Module |
| | Member | `2050` | Jennifer Igoy | `2050@ustp.edu.ph` | 09171002050 | |
| | Member | `2051` | Michael Barot | `2051@ustp.edu.ph` | 09171002051 | |
| | Member | `2052` | Leilani Tampos | `2052@ustp.edu.ph` | 09171002052 | |
| **Team SocietreePublic** | **Leader** | `2053` | Clark Mendoza | `2053@ustp.edu.ph` | 09171002053 | Publications & Editorial Gazette Dispatch Module |
| | Member | `2054` | Rachelle Suarez | `2054@ustp.edu.ph` | 09171002054 | |
| | Member | `2055` | Dennis Beltran | `2055@ustp.edu.ph` | 09171002055 | |
| | Member | `2056` | Hazel Villar | `2056@ustp.edu.ph` | 09171002056 | |
| **Team SocietreeCert** | **Leader** | `2057` | Erwin Quiambao | `2057@ustp.edu.ph` | 09171002057 | Micro-Credentialing & Certificates Authentication Module |
| | Member | `2058` | Katherine Alonzo | `2058@ustp.edu.ph` | 09171002058 | |
| | Member | `2059` | Joseph Malabanan | `2059@ustp.edu.ph` | 09171002059 | |
| | Member | `2060` | Judy Cortez | `2060@ustp.edu.ph` | 09171002060 | |
| **Team SocietreeFeed** | **Leader** | `2061` | Roderick Lacson | `2061@ustp.edu.ph` | 09171002061 | Student Activity Feed & Community Announcements Module |
| | Member | `2062` | Joanna Del Mundo | `2062@ustp.edu.ph` | 09171002062 | |
| | Member | `2063` | Gilbert Serrano | `2063@ustp.edu.ph` | 09171002063 | |
| | Member | `2064` | Theresa Ramirez | `2064@ustp.edu.ph` | 09171002064 | |

---

## 📅 Defense Schedule Matrix (`defense_schedule_import.xlsx` / `.csv`)

- **Stage**: `PIT Prototype Defense`
- **Date**: `Dec 11 2026`
- **Venue**: `Room 303`

| Time Slot | Team Name | Section | Adviser | Chair | Panel Members |
|-----------|-----------|---------|---------|-------|---------------|
| 08:00 AM - 08:30 AM | Team ByteCraft | BSIT-2A | Renato Villanueva | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 08:30 AM - 09:00 AM | Team CodeSphere | BSIT-2A | Renato Villanueva | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 09:00 AM - 09:30 AM | Team NexusCore | BSIT-2A | Renato Villanueva | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 09:30 AM - 10:00 AM | Team DataVibe | BSIT-2A | Renato Villanueva | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 10:00 AM - 10:30 AM | Team CloudPulse | BSIT-2A | Jonathan Beltran | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 10:30 AM - 11:00 AM | Team AlgoNest | BSIT-2A | Jonathan Beltran | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 11:00 AM - 11:30 AM | Team SynapseIT | BSIT-2A | Jonathan Beltran | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 11:30 AM - 12:00 PM | Team PixelForge | BSIT-2A | Jonathan Beltran | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Arsenio Macasaet |
| 01:00 PM - 01:30 PM | Team SocietreeCore | BSIT-2B | Analiza Corpuz | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 01:30 PM - 02:00 PM | Team SocietreeAuth | BSIT-2B | Analiza Corpuz | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 02:00 PM - 02:30 PM | Team SocietreeEvents | BSIT-2B | Analiza Corpuz | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 02:30 PM - 03:00 PM | Team SocietreeFinance | BSIT-2B | Analiza Corpuz | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 03:00 PM - 03:30 PM | Team SocietreeElection | BSIT-2B | Ricardo Fontanilla | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 03:30 PM - 04:00 PM | Team SocietreePublic | BSIT-2B | Ricardo Fontanilla | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 04:00 PM - 04:30 PM | Team SocietreeCert | BSIT-2B | Ricardo Fontanilla | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |
| 04:30 PM - 05:00 PM | Team SocietreeFeed | BSIT-2B | Ricardo Fontanilla | Maricel Suarez | Eduardo Padilla, Florencia Dela Torre, Teresita Buenaventura |

> **Zero Conflict Guarantee**: Advisers never sit on their own advisee team's panel. All faculty allocations use verified IDs `206` through `215`.

---

## 🚀 Recommended Step-by-Step Import Workflow

### 1. Faculty Accounts
Import `sample_file/faculty_user/demo_faculty_import.csv` via:
`Admin -> User Management -> Faculty / General Users -> Bulk Import Users`

### 2. Student Batch Intake (By Year Level)
Import `students_2nd_year_by_year_level.xlsx` (or `.csv`) via:
`Admin -> User Management -> Bulk Import -> By Year Level (Master Cohort Intake)`
*(Enrolls all 64 students 2001 to 2064 in 2nd Year).*

### 3. Student Teams Roster Formation
In `Student Teams -> Bulk Import`, upload:
- **Unified Master Excel**: `Team16roster.xlsx` (Section 2A Different Systems and Section 2B One System side-by-side).
- Or use the modular CSV files:
  - `team_roster_section_2A_different_systems.csv`
  - `team_roster_section_2B_one_system.csv`
  - `team_roster_combined_2A_and_2B.csv`

### 4. Defense Schedule
Import `defense_schedule_import.xlsx` (or `.csv`) via:
`Admin -> Defense Scheduler -> Import Schedule`
*(Populates all 16 scheduled defense slots with chair and panelists).*
"""
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Generated: {readme_path}")

if __name__ == "__main__":
    generate_user_import_files()
    generate_team_roster_files()
    generate_defense_schedule_files()
    generate_readme()
    print("All 2nd Year PIT sample suite files successfully generated!")
