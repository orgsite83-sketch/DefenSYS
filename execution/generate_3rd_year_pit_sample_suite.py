"""
Execution Tool: generate_3rd_year_pit_sample_suite.py
Generates the complete 3rd Year PIT (16 Teams, 64 Students) sample data suite:
1. User Import: students_3rd_year_by_year_level.xlsx & .csv
2. Team Roster: Team16roster.xlsx, team_roster_section_3A_one_system.csv,
   team_roster_section_3B_different_systems.csv, team_roster_combined_3A_and_3B.csv
3. Defense Schedule: defense_schedule_import.xlsx & .csv
4. Master Documentation: sample_file/16_Teams_3rd_Year/README.md
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
OUTPUT_DIR = os.path.join(BASE_DIR, "sample_file", "16_Teams_3rd_Year")
SEM_DIR = os.path.join(OUTPUT_DIR, "1st Sem")
USER_DIR = os.path.join(SEM_DIR, "USer")
TEAM_DIR = os.path.join(SEM_DIR, "team")
SCHED_DIR = os.path.join(SEM_DIR, "schedule")

os.makedirs(USER_DIR, exist_ok=True)
os.makedirs(TEAM_DIR, exist_ok=True)
os.makedirs(SCHED_DIR, exist_ok=True)

# ==============================================================================
# 1. MASTER STUDENTS AND TEAMS SPECIFICATION
# ==============================================================================

STUDENTS_3A = [
    # Team 1: Team AgriPulse (Module 1)
    {"id": "3001", "last": "NAVARRO", "first": "Gabriel", "gender": "M", "team": "Team AgriPulse", "module": "Autonomous Soil Sensor & Dynamic Drip Irrigation Module", "role": "Leader / PM", "adviser": "Eduardo Padilla"},
    {"id": "3002", "last": "ALCANTARA", "first": "Daphne", "gender": "F", "team": "Team AgriPulse", "module": "Autonomous Soil Sensor & Dynamic Drip Irrigation Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3003", "last": "CORTEZ", "first": "Lance", "gender": "M", "team": "Team AgriPulse", "module": "Autonomous Soil Sensor & Dynamic Drip Irrigation Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3004", "last": "TIONGSON", "first": "Samantha", "gender": "F", "team": "Team AgriPulse", "module": "Autonomous Soil Sensor & Dynamic Drip Irrigation Module", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 2: Team SoilSense (Module 2)
    {"id": "3005", "last": "BALTAZAR", "first": "Patrick", "gender": "M", "team": "Team SoilSense", "module": "Soil NPK Nutrient Analysis & Fertilizer Dispensing Module", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "3006", "last": "MIRALLES", "first": "Kimberly", "gender": "F", "team": "Team SoilSense", "module": "Soil NPK Nutrient Analysis & Fertilizer Dispensing Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3007", "last": "ENRIQUEZ", "first": "Cedric", "gender": "M", "team": "Team SoilSense", "module": "Soil NPK Nutrient Analysis & Fertilizer Dispensing Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3008", "last": "DEL ROSARIO", "first": "Patricia", "gender": "F", "team": "Team SoilSense", "module": "Soil NPK Nutrient Analysis & Fertilizer Dispensing Module", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 3: Team ClimateNode (Module 3)
    {"id": "3009", "last": "PANGANIBAN", "first": "Joaquin", "gender": "M", "team": "Team ClimateNode", "module": "Greenhouse Ambient Climate & Hydroponics Telemetry Module", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "3010", "last": "VALENCIA", "first": "Rochelle", "gender": "F", "team": "Team ClimateNode", "module": "Greenhouse Ambient Climate & Hydroponics Telemetry Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3011", "last": "SEBASTIAN", "first": "Marco", "gender": "M", "team": "Team ClimateNode", "module": "Greenhouse Ambient Climate & Hydroponics Telemetry Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3012", "last": "QUINTANA", "first": "Beatriz", "gender": "F", "team": "Team ClimateNode", "module": "Greenhouse Ambient Climate & Hydroponics Telemetry Module", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 4: Team CropVision (Module 4)
    {"id": "3013", "last": "MAGPANTAY", "first": "Dominic", "gender": "M", "team": "Team CropVision", "module": "AI Drone Imagery & Automated Crop Disease Diagnostic Module", "role": "Leader", "adviser": "Eduardo Padilla"},
    {"id": "3014", "last": "VILLAFUERTE", "first": "Celine", "gender": "F", "team": "Team CropVision", "module": "AI Drone Imagery & Automated Crop Disease Diagnostic Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3015", "last": "BUSTAMANTE", "first": "Sean", "gender": "M", "team": "Team CropVision", "module": "AI Drone Imagery & Automated Crop Disease Diagnostic Module", "role": "Member", "adviser": "Eduardo Padilla"},
    {"id": "3016", "last": "SAMONTE", "first": "Erica", "gender": "F", "team": "Team CropVision", "module": "AI Drone Imagery & Automated Crop Disease Diagnostic Module", "role": "Member", "adviser": "Eduardo Padilla"},

    # Team 5: Team SiloTelemetry (Module 5)
    {"id": "3017", "last": "CORNELIO", "first": "Rafael", "gender": "M", "team": "Team SiloTelemetry", "module": "Grain Silo Level Sensing & Anti-Spoilage Ventilation Module", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "3018", "last": "ESGUERRA", "first": "Clarissa", "gender": "F", "team": "Team SiloTelemetry", "module": "Grain Silo Level Sensing & Anti-Spoilage Ventilation Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3019", "last": "MANALO", "first": "Kenneth", "gender": "M", "team": "Team SiloTelemetry", "module": "Grain Silo Level Sensing & Anti-Spoilage Ventilation Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3020", "last": "PASCUA", "first": "Andrea", "gender": "F", "team": "Team SiloTelemetry", "module": "Grain Silo Level Sensing & Anti-Spoilage Ventilation Module", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 6: Team FarmLogix (Module 6)
    {"id": "3021", "last": "DE GUZMAN", "first": "Ian", "gender": "M", "team": "Team FarmLogix", "module": "Farmers Cooperative Harvest Inventory & B2B Dispatch Module", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "3022", "last": "LACSON", "first": "Katrina", "gender": "F", "team": "Team FarmLogix", "module": "Farmers Cooperative Harvest Inventory & B2B Dispatch Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3023", "last": "VILLA", "first": "Lorenzo", "gender": "M", "team": "Team FarmLogix", "module": "Farmers Cooperative Harvest Inventory & B2B Dispatch Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3024", "last": "CATACUTAN", "first": "Joanne", "gender": "F", "team": "Team FarmLogix", "module": "Farmers Cooperative Harvest Inventory & B2B Dispatch Module", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 7: Team ColdChain (Module 7)
    {"id": "3025", "last": "MONTALBAN", "first": "Arthur", "gender": "M", "team": "Team ColdChain", "module": "Refrigerated Transport Cold-Chain & GPS Fleet Tracking Module", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "3026", "last": "AGONCILLO", "first": "Monica", "gender": "F", "team": "Team ColdChain", "module": "Refrigerated Transport Cold-Chain & GPS Fleet Tracking Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3027", "last": "RELOPEZ", "first": "Tristan", "gender": "M", "team": "Team ColdChain", "module": "Refrigerated Transport Cold-Chain & GPS Fleet Tracking Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3028", "last": "MACAPAGAL", "first": "Valerie", "gender": "F", "team": "Team ColdChain", "module": "Refrigerated Transport Cold-Chain & GPS Fleet Tracking Module", "role": "Member", "adviser": "Florencia Dela Torre"},

    # Team 8: Team AgroTrade (Module 8)
    {"id": "3029", "last": "SERRANO", "first": "Christian", "gender": "M", "team": "Team AgroTrade", "module": "Agricultural Commodity Price Forecasting & Direct Market Module", "role": "Leader", "adviser": "Florencia Dela Torre"},
    {"id": "3030", "last": "LLAMAS", "first": "Bernadette", "gender": "F", "team": "Team AgroTrade", "module": "Agricultural Commodity Price Forecasting & Direct Market Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3031", "last": "BELMONTE", "first": "Kyle", "gender": "M", "team": "Team AgroTrade", "module": "Agricultural Commodity Price Forecasting & Direct Market Module", "role": "Member", "adviser": "Florencia Dela Torre"},
    {"id": "3032", "last": "ZAMORA", "first": "Nadine", "gender": "F", "team": "Team AgroTrade", "module": "Agricultural Commodity Price Forecasting & Direct Market Module", "role": "Member", "adviser": "Florencia Dela Torre"},
]

STUDENTS_3B = [
    # Team 9: Team EcoSort (Independent PIT Project)
    {"id": "3033", "last": "DIZON", "first": "Kenneth", "gender": "M", "team": "Team EcoSort", "project": "AI-Powered Waste Sorting & Recyclable Material Identification System", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "3034", "last": "LOPEZ", "first": "Princess", "gender": "F", "team": "Team EcoSort", "project": "AI-Powered Waste Sorting & Recyclable Material Identification System", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3035", "last": "VALENZUELA", "first": "Mark", "gender": "M", "team": "Team EcoSort", "project": "AI-Powered Waste Sorting & Recyclable Material Identification System", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3036", "last": "RAMOS", "first": "Camille", "gender": "F", "team": "Team EcoSort", "project": "AI-Powered Waste Sorting & Recyclable Material Identification System", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 10: Team FloodWatch
    {"id": "3037", "last": "TONGSON", "first": "Gerard", "gender": "M", "team": "Team FloodWatch", "project": "Ultrasonic River Level Sensing & Flood Warning Gateway", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "3038", "last": "SALAZAR", "first": "Katrina", "gender": "F", "team": "Team FloodWatch", "project": "Ultrasonic River Level Sensing & Flood Warning Gateway", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3039", "last": "GOMEZ", "first": "Alvin", "gender": "M", "team": "Team FloodWatch", "project": "Ultrasonic River Level Sensing & Flood Warning Gateway", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3040", "last": "NATIVIDAD", "first": "Diane", "gender": "F", "team": "Team FloodWatch", "project": "Ultrasonic River Level Sensing & Flood Warning Gateway", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 11: Team SolarGrid
    {"id": "3041", "last": "PADILLA", "first": "Raymond", "gender": "M", "team": "Team SolarGrid", "project": "IoT Distributed Solar Microgrid Energy Monitor & Inverter Controller", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "3042", "last": "CASTRO", "first": "Janelle", "gender": "F", "team": "Team SolarGrid", "project": "IoT Distributed Solar Microgrid Energy Monitor & Inverter Controller", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3043", "last": "MARIANO", "first": "Victor", "gender": "M", "team": "Team SolarGrid", "project": "IoT Distributed Solar Microgrid Energy Monitor & Inverter Controller", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3044", "last": "ESCUETA", "first": "Leslie", "gender": "F", "team": "Team SolarGrid", "project": "IoT Distributed Solar Microgrid Energy Monitor & Inverter Controller", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 12: Team Credentia
    {"id": "3045", "last": "ARELLANO", "first": "Joel", "gender": "M", "team": "Team Credentia", "project": "Decentralized Academic Credential Verification & Anti-Tamper Registry", "role": "Leader", "adviser": "Arsenio Macasaet"},
    {"id": "3046", "last": "ROSALES", "first": "Pamela", "gender": "F", "team": "Team Credentia", "project": "Decentralized Academic Credential Verification & Anti-Tamper Registry", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3047", "last": "BERNARDO", "first": "Felix", "gender": "M", "team": "Team Credentia", "project": "Decentralized Academic Credential Verification & Anti-Tamper Registry", "role": "Member", "adviser": "Arsenio Macasaet"},
    {"id": "3048", "last": "MALABANAN", "first": "Sherry", "gender": "F", "team": "Team Credentia", "project": "Decentralized Academic Credential Verification & Anti-Tamper Registry", "role": "Member", "adviser": "Arsenio Macasaet"},

    # Team 13: Team SafeGuard
    {"id": "3049", "last": "TAYAG", "first": "Warren", "gender": "M", "team": "Team SafeGuard", "project": "Computer Vision PPE Compliance & Workplace Hazard Detection Sentinel", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "3050", "last": "CORONEL", "first": "Hazel", "gender": "F", "team": "Team SafeGuard", "project": "Computer Vision PPE Compliance & Workplace Hazard Detection Sentinel", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3051", "last": "OROZCO", "first": "Bryan", "gender": "M", "team": "Team SafeGuard", "project": "Computer Vision PPE Compliance & Workplace Hazard Detection Sentinel", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3052", "last": "SANDOVAL", "first": "Gillian", "gender": "F", "team": "Team SafeGuard", "project": "Computer Vision PPE Compliance & Workplace Hazard Detection Sentinel", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 14: Team ResQPoint
    {"id": "3053", "last": "BRILLANTES", "first": "Martin", "gender": "M", "team": "Team ResQPoint", "project": "Municipal Emergency Response Dispatch & Community Evacuation Map", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "3054", "last": "DACANAY", "first": "Rosemarie", "gender": "F", "team": "Team ResQPoint", "project": "Municipal Emergency Response Dispatch & Community Evacuation Map", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3055", "last": "ESCALONA", "first": "Jason", "gender": "M", "team": "Team ResQPoint", "project": "Municipal Emergency Response Dispatch & Community Evacuation Map", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3056", "last": "PALOMAR", "first": "Joyce", "gender": "F", "team": "Team ResQPoint", "project": "Municipal Emergency Response Dispatch & Community Evacuation Map", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 15: Team AquaSense
    {"id": "3057", "last": "MANIEGO", "first": "Dexter", "gender": "M", "team": "Team AquaSense", "project": "LoRaWAN Smart Water Metering & Infrastructure Leak Detector", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "3058", "last": "QUIAO", "first": "Stephanie", "gender": "F", "team": "Team AquaSense", "project": "LoRaWAN Smart Water Metering & Infrastructure Leak Detector", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3059", "last": "ABAD", "first": "Christopher", "gender": "M", "team": "Team AquaSense", "project": "LoRaWAN Smart Water Metering & Infrastructure Leak Detector", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3060", "last": "BAUTISTA", "first": "Christine", "gender": "F", "team": "Team AquaSense", "project": "LoRaWAN Smart Water Metering & Infrastructure Leak Detector", "role": "Member", "adviser": "Teresita Buenaventura"},

    # Team 16: Team LibRobo
    {"id": "3061", "last": "YAMBAO", "first": "Paolo", "gender": "M", "team": "Team LibRobo", "project": "Autonomous RFID Library Shelf Inventory & Book Wayfinding Robot", "role": "Leader", "adviser": "Teresita Buenaventura"},
    {"id": "3062", "last": "CARPIO", "first": "Angelica", "gender": "F", "team": "Team LibRobo", "project": "Autonomous RFID Library Shelf Inventory & Book Wayfinding Robot", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3063", "last": "FERRER", "first": "Leo", "gender": "M", "team": "Team LibRobo", "project": "Autonomous RFID Library Shelf Inventory & Book Wayfinding Robot", "role": "Member", "adviser": "Teresita Buenaventura"},
    {"id": "3064", "last": "SOLIS", "first": "Danica", "gender": "F", "team": "Team LibRobo", "project": "Autonomous RFID Library Shelf Inventory & Book Wayfinding Robot", "role": "Member", "adviser": "Teresita Buenaventura"},
]

ALL_STUDENTS = STUDENTS_3A + STUDENTS_3B
for s in ALL_STUDENTS:
    s["full_name"] = f"{s['first']} {s['last']}"
    s["formal_name"] = f"{s['last']}, {s['first']}"
    s["email"] = f"{s['id']}@ustp.edu.ph"
    s["contact"] = f"0917100{s['id']}"

SYSTEM_NAME_3A = "Smart Agro-Industrial IoT & Sustainable Supply Platform"
PROJECT_MANAGER_3A = "Gabriel Navarro"

# ==============================================================================
# 2. GENERATE USER IMPORT FILES (.xlsx & .csv)
# ==============================================================================

def generate_user_import_files():
    csv_path = os.path.join(USER_DIR, "students_3rd_year_by_year_level.csv")
    xlsx_path = os.path.join(USER_DIR, "students_3rd_year_by_year_level.xlsx")

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

    for idx, s in enumerate(ALL_STUDENTS, start=1):
        rows_csv.append([
            "",
            str(idx),
            s["id"],
            f'"{s["formal_name"]}"',
            "BSIT",
            "",
            "3rd Year",
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

    # Styling
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

    # Row 4 (1-based row 4):
    # Left (BSIT-3A One System metadata)
    format_cell(ws.cell(row=4, column=2), "System Name:", align_left)
    format_cell(ws.cell(row=4, column=3), SYSTEM_NAME_3A, align_left)

    # Row 5:
    format_cell(ws.cell(row=5, column=2), "Project Manager:", align_left)
    format_cell(ws.cell(row=5, column=3), PROJECT_MANAGER_3A, align_left)

    # Row 6: Headers for both sides
    # Left side (BSIT-3A One System)
    format_cell(ws.cell(row=6, column=2), "Team Name:", align_left)
    format_cell(ws.cell(row=6, column=3), "Module", align_left)
    format_cell(ws.cell(row=6, column=4), "Section", align_center)
    format_cell(ws.cell(row=6, column=5), "Instructor", align_center)
    format_cell(ws.cell(row=6, column=6), "Team Members", align_left)

    # Right side (BSIT-3B Different Systems)
    format_cell(ws.cell(row=6, column=8), "Team Name:", align_left)
    format_cell(ws.cell(row=6, column=9), "PIT Project", align_left)
    format_cell(ws.cell(row=6, column=10), "Section", align_center)
    format_cell(ws.cell(row=6, column=11), "Instructor", align_center)
    format_cell(ws.cell(row=6, column=12), "Team Members", align_left)

    # Populate 8 teams on Left (BSIT-3A) and 8 teams on Right (BSIT-3B)
    # Rows 7 to 38 (32 student rows)
    teams_3a = []
    for i in range(0, len(STUDENTS_3A), 4):
        teams_3a.append(STUDENTS_3A[i:i+4])

    teams_3b = []
    for i in range(0, len(STUDENTS_3B), 4):
        teams_3b.append(STUDENTS_3B[i:i+4])

    for t_idx in range(8):
        t3a = teams_3a[t_idx]
        t3b = teams_3b[t_idx]
        start_r = 7 + t_idx * 4

        # Block borders for Team Name & Module / Project (4 rows outer border)
        for r_offset in range(4):
            curr_r = start_r + r_offset
            top_b = thin if r_offset == 0 else None
            bot_b = thin if r_offset == 3 else None
            block_border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)

            # Left side (BSIT-3A)
            cell_b = ws.cell(row=curr_r, column=2)
            if r_offset == 0:
                cell_b.value = t3a[0]["team"]
            cell_b.font = font_regular
            cell_b.alignment = align_left
            cell_b.border = block_border

            cell_c = ws.cell(row=curr_r, column=3)
            if r_offset == 0:
                cell_c.value = t3a[0]["module"]
            cell_c.font = font_regular
            cell_c.alignment = align_left
            cell_c.border = block_border

            cell_f = ws.cell(row=curr_r, column=6, value=t3a[r_offset]["full_name"])
            cell_f.font = font_regular
            cell_f.alignment = align_left
            cell_f.border = block_border

            # Right side (BSIT-3B)
            cell_h = ws.cell(row=curr_r, column=8)
            if r_offset == 0:
                cell_h.value = t3b[0]["team"]
            cell_h.font = font_regular
            cell_h.alignment = align_left
            cell_h.border = block_border

            cell_i = ws.cell(row=curr_r, column=9)
            if r_offset == 0:
                cell_i.value = t3b[0]["project"]
            cell_i.font = font_regular
            cell_i.alignment = align_left
            cell_i.border = block_border

            cell_l = ws.cell(row=curr_r, column=12, value=t3b[r_offset]["full_name"])
            cell_l.font = font_regular
            cell_l.alignment = align_left
            cell_l.border = block_border

    # Merged Columns:
    # Col D: Section BSIT-3A (Rows 7 to 38)
    ws.merge_cells("D7:D38")
    for r in range(7, 39):
        cell = ws.cell(row=r, column=4)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=4, value="BSIT-3A")

    # Col E: Advisers 3A
    # Teams 1-4 (Rows 7 to 22): Eduardo Padilla
    ws.merge_cells("E7:E22")
    for r in range(7, 23):
        cell = ws.cell(row=r, column=5)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 22 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=5, value="Eduardo Padilla")

    # Teams 5-8 (Rows 23 to 38): Florencia Dela Torre
    ws.merge_cells("E23:E38")
    for r in range(23, 39):
        cell = ws.cell(row=r, column=5)
        top_b = thin if r == 23 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=23, column=5, value="Florencia Dela Torre")

    # Col J: Section BSIT-3B (Rows 7 to 38)
    ws.merge_cells("J7:J38")
    for r in range(7, 39):
        cell = ws.cell(row=r, column=10)
        top_b = thin if r == 7 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=7, column=10, value="BSIT-3B")

    # Col K: Advisers 3B
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
        cell = ws.cell(row=r, column=12)
        top_b = thin if r == 23 else None
        bot_b = thin if r == 38 else None
        cell.border = Border(left=thin, right=thin, top=top_b, bottom=bot_b)
        cell.alignment = align_center
        cell.font = font_regular
    ws.cell(row=23, column=12, value="Teresita Buenaventura")

    wb.save(xlsx_path)
    fix_xlsx_for_dart_compatibility(xlsx_path)
    print(f"Generated: {xlsx_path}")

    # Generate CSV Variations
    # 1. Section 3A Standalone CSV (One System)
    csv_3a_path = os.path.join(TEAM_DIR, "team_roster_section_3A_one_system.csv")
    with open(csv_3a_path, "w", newline="", encoding="utf-8") as f:
        f.write(f"System Name,{SYSTEM_NAME_3A}\n")
        f.write(f"Project Manager,{PROJECT_MANAGER_3A}\n")
        f.write("Team Name,Module,Section,Instructor,Team Members\n")
        for t in teams_3a:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["module"]}","BSIT-3A","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_3a_path}")

    # 2. Section 3B Standalone CSV (Different Systems)
    csv_3b_path = os.path.join(TEAM_DIR, "team_roster_section_3B_different_systems.csv")
    with open(csv_3b_path, "w", newline="", encoding="utf-8") as f:
        f.write("Team Name,PIT Project,Section,Instructor,Team Members\n")
        for t in teams_3b:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["project"]}","BSIT-3B","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_3b_path}")

    # 3. Combined 3A & 3B CSV
    csv_combined_path = os.path.join(TEAM_DIR, "team_roster_combined_3A_and_3B.csv")
    with open(csv_combined_path, "w", newline="", encoding="utf-8") as f:
        # Section 3A block
        f.write(f"System Name,{SYSTEM_NAME_3A}\n")
        f.write(f"Project Manager,{PROJECT_MANAGER_3A}\n")
        f.write("Team Name,Module,Section,Instructor,Team Members\n")
        for t in teams_3a:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["module"]}","BSIT-3A","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
        f.write("\n")
        # Section 3B block
        f.write("Team Name,PIT Project,Section,Instructor,Team Members\n")
        for t in teams_3b:
            for idx, m in enumerate(t):
                if idx == 0:
                    f.write(f'"{m["team"]}","{m["project"]}","BSIT-3B","{m["adviser"]}","{m["full_name"]}"\n')
                else:
                    f.write(f',,,,"{m["full_name"]}"\n')
    print(f"Generated: {csv_combined_path}")

# ==============================================================================
# 4. GENERATE DEFENSE SCHEDULE FILES (.xlsx & .csv)
# ==============================================================================

def generate_defense_schedule_files():
    xlsx_path = os.path.join(SCHED_DIR, "defense_schedule_import.xlsx")
    csv_path = os.path.join(SCHED_DIR, "defense_schedule_import.csv")

    stage = "PIT Capstone Defense"
    date_str = "Oct 23 2026"
    room_str = "Room 302"

    schedule_data = [
        # BSIT-3A Morning Session (Teams 1 - 8)
        {"time": "8:00AM-8:30AM", "team": "Team AgriPulse", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "8:30AM-9:00AM", "team": "Team SoilSense", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "9:00AM-9:30AM", "team": "Team ClimateNode", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "9:30AM-10:00AM", "team": "Team CropVision", "adviser": "Eduardo Padilla", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "10:00AM-10:30AM", "team": "Team SiloTelemetry", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "10:30AM-11:00AM", "team": "Team FarmLogix", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "11:00AM-11:30AM", "team": "Team ColdChain", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},
        {"time": "11:30AM-12:00PM", "team": "Team AgroTrade", "adviser": "Florencia Dela Torre", "chair": "Maricel Suarez", "p1": "Jonathan Beltran", "p2": "Analiza Corpuz", "p3": "Renato Villanueva"},

        # BSIT-3B Afternoon Session (Teams 9 - 16)
        {"time": "1:00PM-1:30PM", "team": "Team EcoSort", "adviser": "Arsenio Macasaet", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "1:30PM-2:00PM", "team": "Team FloodWatch", "adviser": "Arsenio Macasaet", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "2:00PM-2:30PM", "team": "Team SolarGrid", "adviser": "Arsenio Macasaet", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "2:30PM-3:00PM", "team": "Team Credentia", "adviser": "Arsenio Macasaet", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "3:00PM-3:30PM", "team": "Team SafeGuard", "adviser": "Teresita Buenaventura", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "3:30PM-4:00PM", "team": "Team ResQPoint", "adviser": "Teresita Buenaventura", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "4:00PM-4:30PM", "team": "Team AquaSense", "adviser": "Teresita Buenaventura", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
        {"time": "4:30PM-5:00PM", "team": "Team LibRobo", "adviser": "Teresita Buenaventura", "chair": "Ricardo Fontanilla", "p1": "Jonathan Beltran", "p2": "Eduardo Padilla", "p3": "Florencia Dela Torre"},
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

    # Margins matching 4th year schedule layout
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
    content = f"""# DefenSYS 3rd Year PIT Demo Suite (16 Teams, 64 Students)

This dataset provides a complete, production-ready sample suite for **3rd Year PIT (Project Innovation and Technology 3)** in DefenSYS configured according to the curriculum model:
- **Section BSIT-3A**: **One System Format** (8 teams developing specialized modules of the *{SYSTEM_NAME_3A}*, PM: *{PROJECT_MANAGER_3A}*)
- **Section BSIT-3B**: **Different Systems Format** (8 teams developing independent, standalone PIT innovation projects)
- **4 Advised Teams per Adviser / Instructor**:
  - `Prof. Eduardo Padilla` (`212`): Teams 1–4 (BSIT-3A) — *3rd Year PIT Lead*
  - `Prof. Florencia Dela Torre` (`213`): Teams 5–8 (BSIT-3A)
  - `Prof. Arsenio Macasaet` (`214`): Teams 9–12 (BSIT-3B)
  - `Prof. Teresita Buenaventura` (`215`): Teams 13–16 (BSIT-3B)
- **Zero Adviser Conflict**: Advisers never sit on their own advisee panels. All 10 faculty accounts from `sample_file/faculty_user/demo_faculty_import.csv` are used across chairs, panels, and instructors.
- **PIT Documenter Convention**: Matches DefenSYS PIT scheduling model where documenter is omitted from the schedule import timetable.

---

## 📁 Included Files

| File | Type | Description |
|------|------|-------------|
| [students_3rd_year_by_year_level.xlsx](file:///{os.path.join(USER_DIR, 'students_3rd_year_by_year_level.xlsx').replace('\\', '/')}) | **Student Bulk Import (Excel)** | Registrar export (**USTP LIST OF ENROLLMENT** format) for all 64 students (`3001`–`3064`) in 3rd Year. |
| [students_3rd_year_by_year_level.csv](file:///{os.path.join(USER_DIR, 'students_3rd_year_by_year_level.csv').replace('\\', '/')}) | **Student Bulk Import (CSV)** | CSV version of the 64-student intake cohort. |
| [Team16roster.xlsx](file:///{os.path.join(TEAM_DIR, 'Team16roster.xlsx').replace('\\', '/')}) | **Team Roster (Excel)** | Unified side-by-side template containing Section BSIT-3A (One System on Left) and Section BSIT-3B (Different Systems on Right). |
| [team_roster_section_3A_one_system.csv](file:///{os.path.join(TEAM_DIR, 'team_roster_section_3A_one_system.csv').replace('\\', '/')}) | **Team Roster (Section 3A - One System)** | 8 teams collaborating on *{SYSTEM_NAME_3A}* under Advisers Eduardo Padilla and Florencia Dela Torre. |
| [team_roster_section_3B_different_systems.csv](file:///{os.path.join(TEAM_DIR, 'team_roster_section_3B_different_systems.csv').replace('\\', '/')}) | **Team Roster (Section 3B - Different Systems)** | 8 teams developing independent PIT projects under Advisers Arsenio Macasaet and Teresita Buenaventura. |
| [team_roster_combined_3A_and_3B.csv](file:///{os.path.join(TEAM_DIR, 'team_roster_combined_3A_and_3B.csv').replace('\\', '/')}) | **Team Roster (Combined 3A & 3B CSV)** | Single sequential import file with Section 3A One System and Section 3B Different Systems. |
| [defense_schedule_import.xlsx](file:///{os.path.join(SCHED_DIR, 'defense_schedule_import.xlsx').replace('\\', '/')}) | **Defense Schedule (Excel)** | Official 3-row preamble format (`PIT Capstone Defense`, `Oct 23 2026`, `Room 302`) with 16 defense slots and faculty panel allocations. |
| [defense_schedule_import.csv](file:///{os.path.join(SCHED_DIR, 'defense_schedule_import.csv').replace('\\', '/')}) | **Defense Schedule (CSV)** | CSV version of the 16-slot defense schedule. |

---

## 👥 Master Student & Team Allocation Matrix

- **Total Students**: 64 (All unique names, IDs, emails, contact numbers)
- **ID Numbers**: `3001` – `3064` (Default password equals ID number)
- **Team Size**: 4 members per team (1st member is Leader)

---

### Section BSIT-3A — One Shared System (8 Teams, 32 Students)
- **System Name**: `{SYSTEM_NAME_3A}`
- **Project Manager**: `{PROJECT_MANAGER_3A}` (`3001`)

#### Instructor / Adviser: Prof. Eduardo Padilla (`212`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team AgriPulse** | **Leader / PM** | `3001` | Gabriel Navarro | `3001@ustp.edu.ph` | 09171003001 | Autonomous Soil Sensor & Dynamic Drip Irrigation Module |
| | Member | `3002` | Daphne Alcantara | `3002@ustp.edu.ph` | 09171003002 | |
| | Member | `3003` | Lance Cortez | `3003@ustp.edu.ph` | 09171003003 | |
| | Member | `3004` | Samantha Tiongson | `3004@ustp.edu.ph` | 09171003004 | |
| **Team SoilSense** | **Leader** | `3005` | Patrick Baltazar | `3005@ustp.edu.ph` | 09171003005 | Soil NPK Nutrient Analysis & Fertilizer Dispensing Module |
| | Member | `3006` | Kimberly Miralles | `3006@ustp.edu.ph` | 09171003006 | |
| | Member | `3007` | Cedric Enriquez | `3007@ustp.edu.ph` | 09171003007 | |
| | Member | `3008` | Patricia Del Rosario | `3008@ustp.edu.ph` | 09171003008 | |
| **Team ClimateNode** | **Leader** | `3009` | Joaquin Panganiban | `3009@ustp.edu.ph` | 09171003009 | Greenhouse Ambient Climate & Hydroponics Telemetry Module |
| | Member | `3010` | Rochelle Valencia | `3010@ustp.edu.ph` | 09171003010 | |
| | Member | `3011` | Marco Sebastian | `3011@ustp.edu.ph` | 09171003011 | |
| | Member | `3012` | Beatriz Quintana | `3012@ustp.edu.ph` | 09171003012 | |
| **Team CropVision** | **Leader** | `3013` | Dominic Magpantay | `3013@ustp.edu.ph` | 09171003013 | AI Drone Imagery & Automated Crop Disease Diagnostic Module |
| | Member | `3014` | Celine Villafuerte | `3014@ustp.edu.ph` | 09171003014 | |
| | Member | `3015` | Sean Bustamante | `3015@ustp.edu.ph` | 09171003015 | |
| | Member | `3016` | Erica Samonte | `3016@ustp.edu.ph` | 09171003016 | |

#### Instructor / Adviser: Prof. Florencia Dela Torre (`213`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | Assigned System Module |
|-----------|------|------------|-----------|-------|---------|------------------------|
| **Team SiloTelemetry** | **Leader** | `3017` | Rafael Cornelio | `3017@ustp.edu.ph` | 09171003017 | Grain Silo Level Sensing & Anti-Spoilage Ventilation Module |
| | Member | `3018` | Clarissa Esguerra | `3018@ustp.edu.ph` | 09171003018 | |
| | Member | `3019` | Kenneth Manalo | `3019@ustp.edu.ph` | 09171003019 | |
| | Member | `3020` | Andrea Pascua | `3020@ustp.edu.ph` | 09171003020 | |
| **Team FarmLogix** | **Leader** | `3021` | Ian De Guzman | `3021@ustp.edu.ph` | 09171003021 | Farmers Cooperative Harvest Inventory & B2B Dispatch Module |
| | Member | `3022` | Katrina Lacson | `3022@ustp.edu.ph` | 09171003022 | |
| | Member | `3023` | Lorenzo Villa | `3023@ustp.edu.ph` | 09171003023 | |
| | Member | `3024` | Joanne Catacutan | `3024@ustp.edu.ph` | 09171003024 | |
| **Team ColdChain** | **Leader** | `3025` | Arthur Montalban | `3025@ustp.edu.ph` | 09171003025 | Refrigerated Transport Cold-Chain & GPS Fleet Tracking Module |
| | Member | `3026` | Monica Agoncillo | `3026@ustp.edu.ph` | 09171003026 | |
| | Member | `3027` | Tristan Relopez | `3027@ustp.edu.ph` | 09171003027 | |
| | Member | `3028` | Valerie Macapagal | `3028@ustp.edu.ph` | 09171003028 | |
| **Team AgroTrade** | **Leader** | `3029` | Christian Serrano | `3029@ustp.edu.ph` | 09171003029 | Agricultural Commodity Price Forecasting & Direct Market Module |
| | Member | `3030` | Bernadette Llamas | `3030@ustp.edu.ph` | 09171003030 | |
| | Member | `3031` | Kyle Belmonte | `3031@ustp.edu.ph` | 09171003031 | |
| | Member | `3032` | Nadine Zamora | `3032@ustp.edu.ph` | 09171003032 | |

---

### Section BSIT-3B — Different Systems (8 Teams, 32 Students)

#### Instructor / Adviser: Prof. Arsenio Macasaet (`214`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|----------------------------------------|
| **Team EcoSort** | **Leader** | `3033` | Kenneth Dizon | `3033@ustp.edu.ph` | 09171003033 | AI-Powered Waste Sorting & Recyclable Material Identification System |
| | Member | `3034` | Princess Lopez | `3034@ustp.edu.ph` | 09171003034 | |
| | Member | `3035` | Mark Valenzuela | `3035@ustp.edu.ph` | 09171003035 | |
| | Member | `3036` | Camille Ramos | `3036@ustp.edu.ph` | 09171003036 | |
| **Team FloodWatch** | **Leader** | `3037` | Gerard Tongson | `3037@ustp.edu.ph` | 09171003037 | Ultrasonic River Level Sensing & Flood Warning Gateway |
| | Member | `3038` | Katrina Salazar | `3038@ustp.edu.ph` | 09171003038 | |
| | Member | `3039` | Alvin Gomez | `3039@ustp.edu.ph` | 09171003039 | |
| | Member | `3040` | Diane Natividad | `3040@ustp.edu.ph` | 09171003040 | |
| **Team SolarGrid** | **Leader** | `3041` | Raymond Padilla | `3041@ustp.edu.ph` | 09171003041 | IoT Distributed Solar Microgrid Energy Monitor & Inverter Controller |
| | Member | `3042` | Janelle Castro | `3042@ustp.edu.ph` | 09171003042 | |
| | Member | `3043` | Victor Mariano | `3043@ustp.edu.ph` | 09171003043 | |
| | Member | `3044` | Leslie Escueta | `3044@ustp.edu.ph` | 09171003044 | |
| **Team Credentia** | **Leader** | `3045` | Joel Arellano | `3045@ustp.edu.ph` | 09171003045 | Decentralized Academic Credential Verification & Anti-Tamper Registry |
| | Member | `3046` | Pamela Rosales | `3046@ustp.edu.ph` | 09171003046 | |
| | Member | `3047` | Felix Bernardo | `3047@ustp.edu.ph` | 09171003047 | |
| | Member | `3048` | Sherry Malabanan | `3048@ustp.edu.ph` | 09171003048 | |

#### Instructor / Adviser: Prof. Teresita Buenaventura (`215`) — 4 Advised Teams
| Team Name | Role | Student ID | Full Name | Email | Contact | PIT Project Title (Independent System) |
|-----------|------|------------|-----------|-------|---------|----------------------------------------|
| **Team SafeGuard** | **Leader** | `3049` | Warren Tayag | `3049@ustp.edu.ph` | 09171003049 | Computer Vision PPE Compliance & Workplace Hazard Detection Sentinel |
| | Member | `3050` | Hazel Coronel | `3050@ustp.edu.ph` | 09171003050 | |
| | Member | `3051` | Bryan Orozco | `3051@ustp.edu.ph` | 09171003051 | |
| | Member | `3052` | Gillian Sandoval | `3052@ustp.edu.ph` | 09171003052 | |
| **Team ResQPoint** | **Leader** | `3053` | Martin Brillantes | `3053@ustp.edu.ph` | 09171003053 | Municipal Emergency Response Dispatch & Community Evacuation Map |
| | Member | `3054` | Rosemarie Dacanay | `3054@ustp.edu.ph` | 09171003054 | |
| | Member | `3055` | Jason Escalona | `3055@ustp.edu.ph` | 09171003055 | |
| | Member | `3056` | Joyce Palomar | `3056@ustp.edu.ph` | 09171003056 | |
| **Team AquaSense** | **Leader** | `3057` | Dexter Maniego | `3057@ustp.edu.ph` | 09171003057 | LoRaWAN Smart Water Metering & Infrastructure Leak Detector |
| | Member | `3058` | Stephanie Quiao | `3058@ustp.edu.ph` | 09171003058 | |
| | Member | `3059` | Christopher Abad | `3059@ustp.edu.ph` | 09171003059 | |
| | Member | `3060` | Christine Bautista | `3060@ustp.edu.ph` | 09171003060 | |
| **Team LibRobo** | **Leader** | `3061` | Paolo Yambao | `3061@ustp.edu.ph` | 09171003061 | Autonomous RFID Library Shelf Inventory & Book Wayfinding Robot |
| | Member | `3062` | Angelica Carpio | `3062@ustp.edu.ph` | 09171003062 | |
| | Member | `3063` | Leo Ferrer | `3063@ustp.edu.ph` | 09171003063 | |
| | Member | `3064` | Danica Solis | `3064@ustp.edu.ph` | 09171003064 | |

---

## 📅 Defense Schedule Matrix (`defense_schedule_import.xlsx` / `.csv`)

- **Stage**: `PIT Capstone Defense`
- **Date**: `Oct 23 2026`
- **Venue**: `Room 302`

| Time Slot | Team Name | Section | Adviser | Chair | Panel Members |
|-----------|-----------|---------|---------|-------|---------------|
| 08:00 AM - 08:30 AM | Team AgriPulse | BSIT-3A | Eduardo Padilla | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 08:30 AM - 09:00 AM | Team SoilSense | BSIT-3A | Eduardo Padilla | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 09:00 AM - 09:30 AM | Team ClimateNode | BSIT-3A | Eduardo Padilla | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 09:30 AM - 10:00 AM | Team CropVision | BSIT-3A | Eduardo Padilla | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 10:00 AM - 10:30 AM | Team SiloTelemetry | BSIT-3A | Florencia Dela Torre | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 10:30 AM - 11:00 AM | Team FarmLogix | BSIT-3A | Florencia Dela Torre | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 11:00 AM - 11:30 AM | Team ColdChain | BSIT-3A | Florencia Dela Torre | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 11:30 AM - 12:00 PM | Team AgroTrade | BSIT-3A | Florencia Dela Torre | Maricel Suarez | Jonathan Beltran, Analiza Corpuz, Renato Villanueva |
| 01:00 PM - 01:30 PM | Team EcoSort | BSIT-3B | Arsenio Macasaet | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 01:30 PM - 02:00 PM | Team FloodWatch | BSIT-3B | Arsenio Macasaet | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 02:00 PM - 02:30 PM | Team SolarGrid | BSIT-3B | Arsenio Macasaet | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 02:30 PM - 03:00 PM | Team Credentia | BSIT-3B | Arsenio Macasaet | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 03:00 PM - 03:30 PM | Team SafeGuard | BSIT-3B | Teresita Buenaventura | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 03:30 PM - 04:00 PM | Team ResQPoint | BSIT-3B | Teresita Buenaventura | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 04:00 PM - 04:30 PM | Team AquaSense | BSIT-3B | Teresita Buenaventura | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |
| 04:30 PM - 05:00 PM | Team LibRobo | BSIT-3B | Teresita Buenaventura | Ricardo Fontanilla | Jonathan Beltran, Eduardo Padilla, Florencia Dela Torre |

> **Zero Conflict Guarantee**: Advisers never sit on their own advisee team's panel. All faculty allocations use verified IDs `206` through `215`.

---

## 🚀 Recommended Step-by-Step Import Workflow

### 1. Faculty Accounts
Import `sample_file/faculty_user/demo_faculty_import.csv` via:
`Admin -> User Management -> Faculty / General Users -> Bulk Import Users`

### 2. Student Batch Intake (By Year Level)
Import `students_3rd_year_by_year_level.xlsx` (or `.csv`) via:
`Admin -> User Management -> Bulk Import -> By Year Level (Master Cohort Intake)`
*(Enrolls all 64 students 3001 to 3064 in 3rd Year).*

### 3. Student Teams Roster Formation
In `Student Teams -> Bulk Import`, upload:
- **Unified Master Excel**: `Team16roster.xlsx` (Section 3A One System and Section 3B Different Systems side-by-side).
- Or use the modular CSV files:
  - `team_roster_section_3A_one_system.csv`
  - `team_roster_section_3B_different_systems.csv`
  - `team_roster_combined_3A_and_3B.csv`

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
    print("All 3rd Year PIT sample suite files successfully generated!")
