"""
DefenSYS Realistic Test Data & DSS Manuscript Generator
Generates:
1. Complete directory structure under sample_file/All Year all sem test/ for AY 2025-2026 (1st and 2nd semesters).
2. Defense schedules with 3 stages for Capstone (Concept Proposal, Project Proposal, Colloquium) and 3 unique events for PITs.
3. Strict faculty references from demo_faculty_import.csv (IDs 206 to 215).
4. Master unique_projects_curriculum_catalog.csv and .json for DSS curriculum analytics.
5. High-quality 5-page ReportLab PDF manuscripts for every project under sample_file/Project_Manuscripts/.
"""

import os
import csv
import json
import re
from typing import List, Dict, Any

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
    HRFlowable,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_JUSTIFY
from reportlab.pdfgen import canvas


# ==============================================================================
# 1. ROSTER DEFINITIONS
# ==============================================================================

FACULTY = [
    {"id": "206", "name": "Ricardo Fontanilla", "first": "Ricardo", "last": "Fontanilla", "email": "206@ustp.edu.ph", "role": "PIT Lead 1st Year"},
    {"id": "207", "name": "Maricel Suarez", "first": "Maricel", "last": "Suarez", "email": "207@ustp.edu.ph", "role": "faculty"},
    {"id": "208", "name": "Jonathan Beltran", "first": "Jonathan", "last": "Beltran", "email": "208@ustp.edu.ph", "role": "faculty"},
    {"id": "209", "name": "Analiza Corpuz", "first": "Analiza", "last": "Corpuz", "email": "209@ustp.edu.ph", "role": "faculty"},
    {"id": "210", "name": "Renato Villanueva", "first": "Renato", "last": "Villanueva", "email": "210@ustp.edu.ph", "role": "faculty"},
    {"id": "211", "name": "Cecilia Magbanua", "first": "Cecilia", "last": "Magbanua", "email": "211@ustp.edu.ph", "role": "faculty"},
    {"id": "212", "name": "Eduardo Padilla", "first": "Eduardo", "last": "Padilla", "email": "212@ustp.edu.ph", "role": "faculty"},
    {"id": "213", "name": "Florencia Dela Torre", "first": "Florencia", "last": "Dela Torre", "email": "213@ustp.edu.ph", "role": "faculty"},
    {"id": "214", "name": "Arsenio Macasaet", "first": "Arsenio", "last": "Macasaet", "email": "214@ustp.edu.ph", "role": "faculty"},
    {"id": "215", "name": "Teresita Buenaventura", "first": "Teresita", "last": "Buenaventura", "email": "215@ustp.edu.ph", "role": "faculty"},
]

STUDENTS_1ST_YEAR = [
    {"num": 1, "id": "1011", "last": "RIVERA", "first": "James", "gender": "M", "email": "1011@ustp.edu.ph", "contact": "9170001011"},
    {"num": 2, "id": "1012", "last": "LIM", "first": "Sofia", "gender": "F", "email": "1012@ustp.edu.ph", "contact": "9170001012"},
    {"num": 3, "id": "1013", "last": "TORRES", "first": "Miguel", "gender": "M", "email": "1013@ustp.edu.ph", "contact": "9170001013"},
    {"num": 4, "id": "1014", "last": "NGUYEN", "first": "Chloe", "gender": "F", "email": "1014@ustp.edu.ph", "contact": "9170001014"},
    {"num": 5, "id": "1015", "last": "ALCANTARA", "first": "Lucas", "gender": "M", "email": "1015@ustp.edu.ph", "contact": "9170001015"},
    {"num": 6, "id": "1016", "last": "SANTOS", "first": "Elena", "gender": "F", "email": "1016@ustp.edu.ph", "contact": "9170001016"},
    {"num": 7, "id": "1017", "last": "GARCIA", "first": "Mateo", "gender": "M", "email": "1017@ustp.edu.ph", "contact": "9170001017"},
    {"num": 8, "id": "1018", "last": "DIAZ", "first": "Olivia", "gender": "F", "email": "1018@ustp.edu.ph", "contact": "9170001018"},
    {"num": 9, "id": "1019", "last": "CRUZ", "first": "Gabriel", "gender": "M", "email": "1019@ustp.edu.ph", "contact": "9170001019"},
    {"num": 10, "id": "1020", "last": "REYES", "first": "Isabella", "gender": "F", "email": "1020@ustp.edu.ph", "contact": "9170001020"},
    {"num": 11, "id": "1021", "last": "LEE", "first": "Daniel", "gender": "M", "email": "1021@ustp.edu.ph", "contact": "9170001021"},
    {"num": 12, "id": "1022", "last": "MARTINEZ", "first": "Ava", "gender": "F", "email": "1022@ustp.edu.ph", "contact": "9170001022"},
]

STUDENTS_2ND_YEAR = [
    {"num": 1, "id": "2011", "last": "KIM", "first": "Darren", "gender": "M", "email": "2011@ustp.edu.ph", "contact": "9170002011"},
    {"num": 2, "id": "2012", "last": "CRUZ", "first": "Isabel", "gender": "F", "email": "2012@ustp.edu.ph", "contact": "9170002012"},
    {"num": 3, "id": "2013", "last": "RAMOS", "first": "Noah", "gender": "M", "email": "2013@ustp.edu.ph", "contact": "9170002013"},
    {"num": 4, "id": "2014", "last": "FERNANDEZ", "first": "Leah", "gender": "F", "email": "2014@ustp.edu.ph", "contact": "9170002014"},
    {"num": 5, "id": "2015", "last": "LOPEZ", "first": "Nathan", "gender": "M", "email": "2015@ustp.edu.ph", "contact": "9170002015"},
    {"num": 6, "id": "2016", "last": "VALENZUELA", "first": "Mia", "gender": "F", "email": "2016@ustp.edu.ph", "contact": "9170002016"},
    {"num": 7, "id": "2017", "last": "MENDOZA", "first": "Leo", "gender": "M", "email": "2017@ustp.edu.ph", "contact": "9170002017"},
    {"num": 8, "id": "2018", "last": "CASTILLO", "first": "Chloe", "gender": "F", "email": "2018@ustp.edu.ph", "contact": "9170002018"},
    {"num": 9, "id": "2019", "last": "AQUINO", "first": "Oliver", "gender": "M", "email": "2019@ustp.edu.ph", "contact": "9170002019"},
    {"num": 10, "id": "2020", "last": "CORPUZ", "first": "Emma", "gender": "F", "email": "2020@ustp.edu.ph", "contact": "9170002020"},
    {"num": 11, "id": "2021", "last": "RIVERA", "first": "Ethan", "gender": "M", "email": "2021@ustp.edu.ph", "contact": "9170002021"},
    {"num": 12, "id": "2022", "last": "SY", "first": "Sophia", "gender": "F", "email": "2022@ustp.edu.ph", "contact": "9170002022"},
]

STUDENTS_3RD_YEAR = [
    {"num": 1, "id": "3011", "last": "REYES", "first": "Carlos", "gender": "M", "email": "4081@ustp.edu.ph", "contact": "9170004081"},
    {"num": 2, "id": "3012", "last": "SANTOS", "first": "Maria", "gender": "F", "email": "4082@ustp.edu.ph", "contact": "9170004082"},
    {"num": 3, "id": "3013", "last": "DELA CRUZ", "first": "Juan", "gender": "M", "email": "4083@ustp.edu.ph", "contact": "9170004083"},
    {"num": 4, "id": "3014", "last": "MENDOZA", "first": "Ana", "gender": "F", "email": "4084@ustp.edu.ph", "contact": "9170004084"},
    {"num": 5, "id": "3015", "last": "GARCIA", "first": "Jose", "gender": "M", "email": "4085@ustp.edu.ph", "contact": "9170004085"},
    {"num": 6, "id": "3016", "last": "TORRES", "first": "Liza", "gender": "F", "email": "4086@ustp.edu.ph", "contact": "9170004086"},
    {"num": 7, "id": "3017", "last": "VILLANUEVA", "first": "Marco", "gender": "M", "email": "4087@ustp.edu.ph", "contact": "9170004087"},
    {"num": 8, "id": "3018", "last": "FLORES", "first": "Nina", "gender": "F", "email": "4088@ustp.edu.ph", "contact": "9170004088"},
    {"num": 9, "id": "3019", "last": "RAMOS", "first": "Diego", "gender": "M", "email": "4089@ustp.edu.ph", "contact": "9170004089"},
    {"num": 10, "id": "3020", "last": "CRUZ", "first": "Patricia", "gender": "F", "email": "4090@ustp.edu.ph", "contact": "9170004090"},
    {"num": 11, "id": "3021", "last": "BAUTISTA", "first": "Ryan", "gender": "M", "email": "4091@ustp.edu.ph", "contact": "9170004091"},
    {"num": 12, "id": "3022", "last": "AQUINO", "first": "Sophia", "gender": "F", "email": "4092@ustp.edu.ph", "contact": "9170004092"},
]

STUDENTS_4TH_YEAR = [
    {"num": 1, "id": "4011", "last": "VILLAR", "first": "Marcus", "gender": "M", "email": "4011@ustp.edu.ph", "contact": "9170004011"},
    {"num": 2, "id": "4012", "last": "ONG", "first": "Patricia", "gender": "F", "email": "4012@ustp.edu.ph", "contact": "9170004012"},
    {"num": 3, "id": "4013", "last": "SALAZAR", "first": "Ethan", "gender": "M", "email": "4013@ustp.edu.ph", "contact": "9170004013"},
    {"num": 4, "id": "4014", "last": "CASTILLO", "first": "Zoe", "gender": "F", "email": "4014@ustp.edu.ph", "contact": "9170004014"},
    {"num": 5, "id": "4015", "last": "TORRES", "first": "Ryan", "gender": "M", "email": "4015@ustp.edu.ph", "contact": "9170004015"},
    {"num": 6, "id": "4016", "last": "VILLANUEVA", "first": "Nina", "gender": "F", "email": "4016@ustp.edu.ph", "contact": "9170004016"},
    {"num": 7, "id": "4017", "last": "GARCIA", "first": "Diego", "gender": "M", "email": "4017@ustp.edu.ph", "contact": "9170004017"},
    {"num": 8, "id": "4018", "last": "RAMOS", "first": "Patricia", "gender": "F", "email": "4018@ustp.edu.ph", "contact": "9170004018"},
    {"num": 9, "id": "4019", "last": "BAUTISTA", "first": "Carlos", "gender": "M", "email": "4019@ustp.edu.ph", "contact": "9170004019"},
    {"num": 10, "id": "4020", "last": "SANTOS", "first": "Sophia", "gender": "F", "email": "4020@ustp.edu.ph", "contact": "9170004020"},
    {"num": 11, "id": "4021", "last": "CRUZ", "first": "Miguel", "gender": "M", "email": "4021@ustp.edu.ph", "contact": "9170004021"},
    {"num": 12, "id": "4022", "last": "ALCANTARA", "first": "Isabella", "gender": "F", "email": "4022@ustp.edu.ph", "contact": "9170004022"},
]


# ==============================================================================
# 2. REPORTLAB NUMBERED CANVAS (EXACT 5 PAGES)
# ==============================================================================

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_footer(num_pages)
            canvas.Canvas.showPage(self)
        canvas.Canvas.save(self)

    def draw_footer(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))
        # Header banner on page 2+
        if self._pageNumber > 1:
            self.drawString(54, 750, "DefenSYS Technical Manuscript Series  •  Academic Year 2025–2026")
            self.setStrokeColor(colors.HexColor("#CBD5E1"))
            self.setLineWidth(0.5)
            self.line(54, 742, self._pagesize[0] - 54, 742)
        
        # Footer
        footer_text = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(self._pagesize[0] - 54, 34, footer_text)
        self.drawString(54, 34, "CONFIDENTIAL  |  USTP Department of Information Technology  |  DefenSYS DSS Repository")
        self.setStrokeColor(colors.HexColor("#E2E8F0"))
        self.setLineWidth(0.5)
        self.line(54, 46, self._pagesize[0] - 54, 46)
        self.restoreState()


# ==============================================================================
# 3. PDF MANUSCRIPT BUILDER
# ==============================================================================

def generate_manuscript_pdf(proj: Dict[str, Any], filepath: str):
    """
    Generates an authentic 5-page PDF manuscript matching
    'can you make a manuscript for alumni career track....pdf'.
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    doc = SimpleDocTemplate(
        filepath,
        pagesize=letter,
        leftMargin=54,
        rightMargin=54,
        topMargin=54,
        bottomMargin=54,
    )
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=18,
        leading=22,
        textColor=colors.HexColor('#7F1D1D'),
        alignment=TA_LEFT,
        spaceAfter=6,
    )
    subtitle_style = ParagraphStyle(
        'DocSub',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10,
        leading=13,
        textColor=colors.HexColor('#475569'),
        spaceAfter=10,
    )
    h1_style = ParagraphStyle(
        'DocH1',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=12,
        leading=15,
        textColor=colors.HexColor('#1E293B'),
        spaceBefore=8,
        spaceAfter=4,
    )
    h2_style = ParagraphStyle(
        'DocH2',
        parent=styles['Heading2'],
        fontName='Helvetica-Bold',
        fontSize=9.5,
        leading=12,
        textColor=colors.HexColor('#334155'),
        spaceBefore=6,
        spaceAfter=3,
    )
    body_style = ParagraphStyle(
        'DocBody',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=11,
        textColor=colors.HexColor('#1E293B'),
        alignment=TA_JUSTIFY,
        spaceAfter=4,
    )
    bullet_style = ParagraphStyle(
        'DocBullet',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=11,
        textColor=colors.HexColor('#1E293B'),
        leftIndent=12,
        spaceAfter=2.5,
    )
    table_cell = ParagraphStyle(
        'TableCell',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7,
        leading=9,
        textColor=colors.HexColor('#0F172A'),
    )
    table_cell_bold = ParagraphStyle(
        'TableCellBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=7,
        leading=9,
        textColor=colors.HexColor('#0F172A'),
    )

    story = []

    # -------------------------------------------------------------------------
    # PAGE 1: TITLE, METADATA, ABSTRACT, SECTION 1 (INTRODUCTION)
    # -------------------------------------------------------------------------
    story.append(Paragraph(proj['title'].upper(), title_style))
    story.append(Paragraph(
        f"<b>Team:</b> {proj['team_name']} &nbsp;|&nbsp; "
        f"<b>Track:</b> {proj['track']} &nbsp;|&nbsp; "
        f"<b>Level:</b> {proj['year_level']} ({proj['semester']}, AY 2025–2026)<br/>"
        f"<b>Adviser:</b> {proj['adviser']} &nbsp;|&nbsp; "
        f"<b>Members:</b> {', '.join(proj['members'])}",
        subtitle_style
    ))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor('#7F1D1D'), spaceAfter=8))

    abstract_text = (
        f"<b>ABSTRACT:</b> {proj['abstract']} "
        f"The system leverages an integrated stack centered on <b>{proj['stack']}</b>, "
        f"operating in the <b>{proj['domain']}</b> domain. Designed to satisfy prerequisite competencies for "
        f"<b>{proj['prereq_course']}</b>, the architecture aligns with high-demand <b>{proj['career_track']}</b> roles. "
        f"Experimental evaluation demonstrates significant improvements in operational throughput, accuracy, and compliance."
    )
    abstract_table = Table([[Paragraph(abstract_text, body_style)]], colWidths=[504])
    abstract_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC')),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor('#CBD5E1')),
        ('PADDING', (0,0), (-1,-1), 7),
    ]))
    story.append(abstract_table)
    story.append(Spacer(1, 4))

    keywords_p = Paragraph(f"<b>Keywords:</b> {', '.join(proj['keywords'])}", body_style)
    story.append(keywords_p)
    story.append(Spacer(1, 4))

    story.append(Paragraph("1. Introduction", h1_style))
    story.append(Paragraph("1.1 Overview & Background", h2_style))
    story.append(Paragraph(
        f"{proj['title']} represents an institutional technology solution developed within the "
        f"Department of Information Technology for Academic Year 2025–2026. "
        f"Contemporary academic and operational frameworks require automated, scalable, and secure systems to "
        f"eliminate paper-intensive workflows and optimize decision-making in the {proj['domain']} domain.",
        body_style
    ))

    story.append(Paragraph("1.2 Problem Statement", h2_style))
    story.append(Paragraph(
        f"Traditional methodologies in this operational area rely on fragmented manual tracking, asynchronous spreadsheets, "
        f"and decentralized records. This results in: (a) severe reporting latency exceeding standard institutional service level agreements; "
        f"(b) frequent transcription inaccuracies and lack of data validation; (c) high security vulnerabilities and auditing deficits; and "
        f"(d) inability to derive predictive intelligence for academic and administrative leadership.",
        body_style
    ))

    story.append(Paragraph("1.3 Project Objectives", h2_style))
    story.append(Paragraph(f"• Develop a robust, end-to-end architecture built upon {proj['stack']}.", bullet_style))
    story.append(Paragraph(f"• Implement automated intelligence workflows incorporating {proj['keywords'][0]} and {proj['keywords'][1]}.", bullet_style))
    story.append(Paragraph(f"• Provide role-based interfaces for administrators, evaluators, and student stakeholders.", bullet_style))
    story.append(Paragraph(f"• Validate system compliance and fault tolerance in accordance with university evaluation criteria.", bullet_style))

    story.append(PageBreak())

    # -------------------------------------------------------------------------
    # PAGE 2: SECTION 2 (SYSTEM ARCHITECTURE & METHODOLOGY)
    # -------------------------------------------------------------------------
    story.append(Spacer(1, 15))
    story.append(Paragraph("2. System Architecture & Methodology", h1_style))
    story.append(Paragraph("2.1 Architectural Blueprint & Layered Topology", h2_style))
    story.append(Paragraph(
        f"The architecture of {proj['title']} follows an enterprise-grade multi-tier paradigm designed for high availability, "
        f"decoupled maintainability, and horizontal scalability. The client presentation tier interfaces with backend microservices "
        f"over TLS-encrypted RESTful JSON endpoints. High-throughput state persistence is achieved through relational schema "
        f"design with strict foreign key constraints and transactional integrity.",
        body_style
    ))

    story.append(Paragraph("2.2 Technology Stack Breakdown", h2_style))
    tech_table_data = [
        [Paragraph("Tier / Component", table_cell_bold), Paragraph("Technology Selection", table_cell_bold), Paragraph("Architectural Rationale", table_cell_bold)],
        [Paragraph("Client Presentation", table_cell), Paragraph(proj['frontend_tech'], table_cell), Paragraph("Provides reactive component lifecycle, cross-platform responsiveness, and rich UX state management.", table_cell)],
        [Paragraph("Application Logic", table_cell), Paragraph(proj['backend_tech'], table_cell), Paragraph("Enforces strict business rules, role-based authorization scopes, and ACID database transactions.", table_cell)],
        [Paragraph("Persistence Layer", table_cell), Paragraph(proj['database_tech'], table_cell), Paragraph("Structured relational models with indexed query lookups, audit trails, and backup failover.", table_cell)],
        [Paragraph("Security & Auth", table_cell), Paragraph("OAuth 2.0 / JWT Bearer Tokens", table_cell), Paragraph("Stateless cryptographic signature validation ensuring zero unauthorized token tampering.", table_cell)],
        [Paragraph("DevOps & Hosting", table_cell), Paragraph("Docker Containers / Cloud VM", table_cell), Paragraph("Reproducible container image orchestration with automated CI/CD health telemetry.", table_cell)],
    ]
    tech_table = Table(tech_table_data, colWidths=[110, 140, 254])
    tech_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#F1F5F9')),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor('#94A3B8')),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#CBD5E1')),
        ('PADDING', (0,0), (-1,-1), 4.5),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ]))
    story.append(tech_table)
    story.append(Spacer(1, 6))

    story.append(Paragraph("2.3 Data Pipeline & Processing Methodology", h2_style))
    story.append(Paragraph(
        f"Incoming telemetry and transactional submissions undergo strict sanitization before persistence. "
        f"When inputs match defined events, asynchronous workers trigger analytical scoring pipelines utilizing "
        f"<b>{', '.join(proj['keywords'][:3])}</b> algorithms. All generated outputs are logged to audit registries "
        f"meeting ISO/IEC 27001 compliance standards.",
        body_style
    ))

    story.append(PageBreak())

    # -------------------------------------------------------------------------
    # PAGE 3: SECTION 3 (KEY FUNCTIONAL MODULES & WORKFLOWS)
    # -------------------------------------------------------------------------
    story.append(Spacer(1, 15))
    story.append(Paragraph("3. Key Functional Modules & System Workflows", h1_style))
    story.append(Paragraph("3.1 Core Subsystem Specifications", h2_style))
    story.append(Paragraph(
        f"The platform implements three dedicated functional subsystems engineered to solve the operational bottlenecks "
        f"identified in Section 1. Each subsystem maintains independent state controllers while sharing unified session context.",
        body_style
    ))

    story.append(Paragraph(f"• <b>Subsystem A: {proj['module_1_name']}</b>", h2_style))
    story.append(Paragraph(f"{proj['module_1_desc']}", body_style))

    story.append(Paragraph(f"• <b>Subsystem B: {proj['module_2_name']}</b>", h2_style))
    story.append(Paragraph(f"{proj['module_2_desc']}", body_style))

    story.append(Paragraph(f"• <b>Subsystem C: {proj['module_3_name']}</b>", h2_style))
    story.append(Paragraph(f"{proj['module_3_desc']}", body_style))

    story.append(Paragraph("3.2 User Interaction Workflow & Security Governance", h2_style))
    story.append(Paragraph(
        f"User requests originate from authenticated clients bearing signed JWT bearer tokens. The API gateway evaluates "
        f"role permissions (Student, Lead, Panelist, or Administrator) before delegating requests to controller services. "
        f"Any attempt to bypass stage progression gates or modify immutable audit records triggers instantaneous system alerts.",
        body_style
    ))

    story.append(PageBreak())

    # -------------------------------------------------------------------------
    # PAGE 4: SECTION 4 (DATA SCHEMA & RELATIONAL SPECIFICATIONS)
    # -------------------------------------------------------------------------
    story.append(Spacer(1, 15))
    story.append(Paragraph("4. Data Schema & Relational Specifications", h1_style))
    story.append(Paragraph("4.1 Entity Relationship Model Design", h2_style))
    story.append(Paragraph(
        f"To maintain relational consistency and accommodate high query frequency, the database schema utilizes normalized "
        f"third normal form (3NF) relational tables. The primary entities and their respective constraints are tabulated below:",
        body_style
    ))

    schema_data = [
        [Paragraph("Entity / Column", table_cell_bold), Paragraph("Data Type", table_cell_bold), Paragraph("Key / Constraints", table_cell_bold), Paragraph("Description", table_cell_bold)],
        [Paragraph("record_id", table_cell), Paragraph("BIGSERIAL", table_cell), Paragraph("PRIMARY KEY", table_cell), Paragraph("Synthetic surrogate key identifying each unique transactional record.", table_cell)],
        [Paragraph("entity_uuid", table_cell), Paragraph("UUID v4", table_cell), Paragraph("UNIQUE, NOT NULL", table_cell), Paragraph("Cryptographically secure external identifier for API transmission.", table_cell)],
        [Paragraph("team_identifier", table_cell), Paragraph("VARCHAR(120)", table_cell), Paragraph("INDEXED, NOT NULL", table_cell), Paragraph("Unique foreign reference mapping directly to registered student cohorts.", table_cell)],
        [Paragraph("metric_score", table_cell), Paragraph("DECIMAL(5,2)", table_cell), Paragraph("CHECK (0.00 TO 100.00)", table_cell), Paragraph("Evaluated proficiency or telemetry score validated by institutional rubric.", table_cell)],
        [Paragraph("feature_vector", table_cell), Paragraph("JSONB", table_cell), Paragraph("DEFAULT '{}'", table_cell), Paragraph("Structured payload storing machine-readable telemetry and model weights.", table_cell)],
        [Paragraph("status_flag", table_cell), Paragraph("VARCHAR(32)", table_cell), Paragraph("CHECK IN (valid_states)", table_cell), Paragraph("Lifecycle state tracking: Draft, Submitted, Under Review, or Approved.", table_cell)],
        [Paragraph("created_at", table_cell), Paragraph("TIMESTAMPTZ", table_cell), Paragraph("DEFAULT NOW()", table_cell), Paragraph("Immutable creation timestamp populated directly by database engine.", table_cell)],
        [Paragraph("updated_at", table_cell), Paragraph("TIMESTAMPTZ", table_cell), Paragraph("ON UPDATE NOW()", table_cell), Paragraph("Audit timestamp updated automatically on every mutation.", table_cell)],
    ]
    schema_table = Table(schema_data, colWidths=[100, 75, 115, 214])
    schema_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#F1F5F9')),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor('#94A3B8')),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#CBD5E1')),
        ('PADDING', (0,0), (-1,-1), 4),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ]))
    story.append(schema_table)
    story.append(Spacer(1, 6))

    story.append(Paragraph("4.2 Indexing & Performance Optimization", h2_style))
    story.append(Paragraph(
        f"Composite indexes are deployed across `(team_identifier, status_flag)` to accelerate dashboard aggregation queries. "
        f"JSONB payloads utilize GIN indexing to enable sub-millisecond keyword extraction for the Decision Support System (DSS).",
        body_style
    ))

    story.append(PageBreak())

    # -------------------------------------------------------------------------
    # PAGE 5: SECTION 5 (ROADMAP, CURRICULUM IMPACT & CONCLUSION)
    # -------------------------------------------------------------------------
    story.append(Spacer(1, 15))
    story.append(Paragraph("5. Implementation Roadmap & Curriculum Alignment", h1_style))
    story.append(Paragraph("5.1 14-Week Engineering Roadmap", h2_style))

    roadmap_data = [
        [Paragraph("Phase & Duration", table_cell_bold), Paragraph("Deliverables & Core Milestones", table_cell_bold), Paragraph("Evaluation Gate", table_cell_bold)],
        [Paragraph("Phase 1 (W1–W4)", table_cell), Paragraph("Problem domain formulation, SRS documentation, Figma UI prototyping, initial database migration.", table_cell), Paragraph("Concept Proposal / Pitch", table_cell)],
        [Paragraph("Phase 2 (W5–W8)", table_cell), Paragraph(f"Backend API integration, authentication security pipeline, {proj['keywords'][0]} engine implementation.", table_cell), Paragraph("Prototype Milestone Defense", table_cell)],
        [Paragraph("Phase 3 (W9–W11)", table_cell), Paragraph("System integration, end-to-end UI responsiveness, user acceptance testing (UAT), audit trail testing.", table_cell), Paragraph("Colloquium / Tech Expo", table_cell)],
        [Paragraph("Phase 4 (W12–W14)", table_cell), Paragraph("Performance benchmarking, security penetration review, final manuscript compilation, institutional deployment.", table_cell), Paragraph("Final Institutional Sign-off", table_cell)],
    ]
    roadmap_table = Table(roadmap_data, colWidths=[100, 260, 144])
    roadmap_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#F1F5F9')),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor('#94A3B8')),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#CBD5E1')),
        ('PADDING', (0,0), (-1,-1), 4.5),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ]))
    story.append(roadmap_table)
    story.append(Spacer(1, 8))

    story.append(Paragraph("5.2 Decision Support System (DSS) & Prerequisite Alignment", h2_style))
    story.append(Paragraph(
        f"This project provides direct empirical validation for the university curriculum by testing student mastery of "
        f"<b>{proj['prereq_course']}</b>. The technology choices support career readiness for <b>{proj['career_track']}</b> "
        f"roles. DefenSYS curriculum analytics tracks keyword frequencies ({', '.join(proj['keywords'][:4])}) to confirm that "
        f"learning outcomes meet ABET and CHED accreditation standards.",
        body_style
    ))
    story.append(Spacer(1, 6))

    story.append(Paragraph("5.3 Conclusion & Future Directions", h2_style))
    story.append(Paragraph(
        f"In conclusion, {proj['title']} successfully demonstrates the viability of modern software engineering principles "
        f"applied to real-world institutional challenges. Future enhancements will explore distributed cloud scalability, "
        f"real-time federated intelligence, and broader multi-campus deployments.",
        body_style
    ))

    doc.build(story, canvasmaker=NumberedCanvas)


# ==============================================================================
# 4. MASTER CATALOG OF ALL PROJECTS
# ==============================================================================

def get_all_projects() -> List[Dict[str, Any]]:
    projects = []

    # 1ST YEAR - 1ST SEMESTER (PIT - 3 EVENTS, 3 UNIQUE TEAMS/PROJECTS PER EVENT)
    projects.append({
        "id": "1Y-1S-E1-T1", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Concept Pitch", "date": "10/24/2025", "room": "Room 301", "time": "9:00AM-9:30AM",
        "team_name": "Team NovaPath", "title": "Campus Wayfinder App", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["James Rivera", "Sofia Lim", "Miguel Torres", "Chloe Nguyen"],
        "stack": "Flutter / Mobile", "domain": "Mobile & Ubiquitous Computing",
        "prereq_course": "IT222 Mobile Application Development", "career_track": "Mobile App Developer",
        "keywords": ["flutter", "mobile", "dart", "geolocation", "mobile app", "android", "ios", "tracker app"],
        "frontend_tech": "Flutter 3.x / Dart Mobile Framework", "backend_tech": "Django REST Framework / Python 3.12",
        "database_tech": "PostgreSQL 16 with PostGIS Spatial Extensions",
        "module_1_name": "Interactive Campus Geolocation Engine",
        "module_1_desc": "Provides GPS indoor/outdoor vector pathfinding across university buildings and facilities.",
        "module_2_name": "Classroom Schedule & Room Locator",
        "module_2_desc": "Synchronizes enrolled student timetables with geographical room coordinates.",
        "module_3_name": "Crowd Density & Accessibility Router",
        "module_3_desc": "Calculates wheelchair-accessible and low-congestion navigation routes across campus.",
        "abstract": "An intelligent mobile geolocation platform assisting freshmen and visitors in navigating campus facilities with sub-meter spatial precision.",
    })
    projects.append({
        "id": "1Y-1S-E1-T2", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Concept Pitch", "date": "10/24/2025", "room": "Room 301", "time": "9:30AM-10:00AM",
        "team_name": "Team CyberShield", "title": "Secure Vault Authentication Gateway", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Lucas Alcantara", "Elena Santos", "Mateo Garcia", "Olivia Diaz"],
        "stack": "Django / Python", "domain": "Cybersecurity & Network Systems",
        "prereq_course": "IT313 Information Assurance & Security", "career_track": "Security Operations Analyst",
        "keywords": ["security", "cryptography", "firewall", "encryption", "auth", "vulnerability", "audit", "network"],
        "frontend_tech": "Vue.js 3 / TailwindCSS Security Dashboard", "backend_tech": "Python / FastAPI with OpenSSL Cryptography",
        "database_tech": "PostgreSQL with AES-256 Column Encryption",
        "module_1_name": "Multi-Factor Cryptographic Authenticator",
        "module_1_desc": "Issues hardware token and TOTP challenge-response verification for elevated administrative roles.",
        "module_2_name": "Audit Log Integrity Verification",
        "module_2_desc": "Maintains tamper-proof SHA-256 merkle hash chains across system event logs.",
        "module_3_name": "Brute-Force & Anomaly Firewall",
        "module_3_desc": "Enforces rate limiting and dynamic IP greylisting based on suspicious login signatures.",
        "abstract": "A zero-trust cryptographic gateway enforcing multi-factor biometric authentication and immutable event logging for institutional assets.",
    })
    projects.append({
        "id": "1Y-1S-E1-T3", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Concept Pitch", "date": "10/24/2025", "room": "Room 301", "time": "10:00AM-10:30AM",
        "team_name": "Team EcoSense", "title": "Smart Classroom Climate Monitor", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Gabriel Cruz", "Isabella Reyes", "Daniel Lee", "Ava Martinez"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "Embedded Systems Engineer",
        "keywords": ["iot", "arduino", "esp32", "sensor", "embedded", "smart home", "automation", "actuator"],
        "frontend_tech": "React Dashboard with WebSockets Telemetry", "backend_tech": "Node.js MQTT Broker & TimeSeries Engine",
        "database_tech": "InfluxDB TimeSeries & SQLite Metadata Store",
        "module_1_name": "Ambient Telemetry Ingestion Node",
        "module_1_desc": "Reads temperature, humidity, and CO2 concentrations every 5 seconds via ESP32 microcontrollers.",
        "module_2_name": "Automated Actuator Controller",
        "module_2_desc": "Activates ventilation and HVAC fans when air quality drops below occupational standards.",
        "module_3_name": "Classroom Energy Optimization Analyzer",
        "module_3_desc": "Generates power consumption analytics correlating occupancy metrics with electricity usage.",
        "abstract": "An IoT embedded telemetry system continuously monitoring classroom ambient variables and automating environmental air circulation.",
    })

    # Event 2: 1st Year Prototype Defense
    projects.append({
        "id": "1Y-1S-E2-T1", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Prototype Defense", "date": "11/14/2025", "room": "Room 302", "time": "9:00AM-9:30AM",
        "team_name": "Team DataPulse", "title": "Student Grade Analytics Dashboard", "adviser": "Analiza Corpuz",
        "chair": "Jonathan Beltran", "panelist": "Renato Villanueva", "documenter": "Cecilia Magbanua",
        "members": ["James Rivera", "Sofia Lim", "Miguel Torres", "Chloe Nguyen"],
        "stack": "Django / Python", "domain": "Data Analytics & BI",
        "prereq_course": "IT221 Data Analysis & Visualization", "career_track": "Data Analyst / BI Specialist",
        "keywords": ["analytics", "dashboard", "visualization", "mining", "grade tracker", "forecasting", "reporting", "big data"],
        "frontend_tech": "Chart.js / HTML5 Responsive Grid", "backend_tech": "Django / Python Pandas & NumPy Analytics Engine",
        "database_tech": "PostgreSQL 16 with Materialized Views",
        "module_1_name": "Academic Performance Visualizer",
        "module_1_desc": "Renders GPA trajectory, standard deviation curves, and subject mastery distributions.",
        "module_2_name": "Early Warning Attrition Identifier",
        "module_2_desc": "Flags students failing prerequisite courses for prioritized faculty academic counseling.",
        "module_3_name": "Cohort Comparative Analytics",
        "module_3_desc": "Aggregates sectional exam passing rates to assist curriculum coordinators with syllabus calibration.",
        "abstract": "An educational data analytics platform computing competency distributions and predictive grade forecasts for departmental review.",
    })
    projects.append({
        "id": "1Y-1S-E2-T2", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Prototype Defense", "date": "11/14/2025", "room": "Room 302", "time": "9:30AM-10:00AM",
        "team_name": "Team WebCraft", "title": "Campus Peer Tutoring Marketplace", "adviser": "Analiza Corpuz",
        "chair": "Jonathan Beltran", "panelist": "Renato Villanueva", "documenter": "Cecilia Magbanua",
        "members": ["Lucas Alcantara", "Elena Santos", "Mateo Garcia", "Olivia Diaz"],
        "stack": "React / Node.js", "domain": "Web Applications & Platforms",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "Full-Stack Web Developer",
        "keywords": ["web", "react", "node", "javascript", "tutor", "booking", "quiz", "builder"],
        "frontend_tech": "React 18 / Vite / Tailwind UI", "backend_tech": "Node.js / Express.js REST Microservices",
        "database_tech": "MongoDB Atlas with Mongoose ODM",
        "module_1_name": "Tutor Discovery & Slot Booking",
        "module_1_desc": "Allows students to search certified student tutors by course code and reserve interactive time slots.",
        "module_2_name": "Collaborative Virtual Whiteboard",
        "module_2_desc": "WebRTC-based real-time canvas for collaborative mathematical problem-solving.",
        "module_3_name": "Session Rating & Feedback Portal",
        "module_3_desc": "Captures double-blind student evaluations to maintain quality assurance across peer tutors.",
        "abstract": "A collaborative web platform connecting undergraduate peers for structured tutoring sessions and skill reinforcement.",
    })
    projects.append({
        "id": "1Y-1S-E2-T3", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Prototype Defense", "date": "11/14/2025", "room": "Room 302", "time": "10:00AM-10:30AM",
        "team_name": "Team CloudSync", "title": "Institutional File Storage & Sync Service", "adviser": "Analiza Corpuz",
        "chair": "Jonathan Beltran", "panelist": "Renato Villanueva", "documenter": "Cecilia Magbanua",
        "members": ["Gabriel Cruz", "Isabella Reyes", "Daniel Lee", "Ava Martinez"],
        "stack": "Cloud / AWS", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT311 Cloud Architecture & Enterprise Systems", "career_track": "Cloud Solutions Architect",
        "keywords": ["cloud", "storage", "file", "sync", "aws", "docker", "saas", "portal"],
        "frontend_tech": "Angular 17 Enterprise Admin Shell", "backend_tech": "Go (Golang) High-Concurrency File Streamer",
        "database_tech": "Amazon S3 Object Storage & PostgreSQL Metadata",
        "module_1_name": "Chunked Resumable Upload Daemon",
        "module_1_desc": "Transfers multi-gigabyte research archives reliably over unstable university Wi-Fi links.",
        "module_2_name": "Role-Based Access Governance",
        "module_2_desc": "Restricts department document visibility through granular file permissions and expiring signed URLs.",
        "module_3_name": "Versioned Document Archive",
        "module_3_desc": "Maintains immutable delta snapshots preventing accidental student overwrite of official capstone drafts.",
        "abstract": "A high-performance cloud storage synchronization system featuring chunked data uploads and automated file revision snapshots.",
    })

    # Event 3: 1st Year Tech Expo
    projects.append({
        "id": "1Y-1S-E3-T1", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Tech Expo", "date": "12/12/2025", "room": "Smart Room", "time": "9:00AM-9:30AM",
        "team_name": "Team GeoSpatial", "title": "Barangay Disaster Evacuation Mapping System", "adviser": "Eduardo Padilla",
        "chair": "Renato Villanueva", "panelist": "Florencia Dela Torre", "documenter": "Cecilia Magbanua",
        "members": ["James Rivera", "Sofia Lim", "Miguel Torres", "Chloe Nguyen"],
        "stack": "GIS / Mapping", "domain": "GIS & Smart Community",
        "prereq_course": "IT322 Geographic Information Systems", "career_track": "GIS & Geomatics Specialist",
        "keywords": ["gis", "map", "mapping", "geo", "spatial", "disaster", "evacuation", "barangay", "location"],
        "frontend_tech": "Leaflet.js / OpenStreetMap Mobile Web", "backend_tech": "Python GeoDjango / GDAL Engine",
        "database_tech": "PostGIS Spatial Database",
        "module_1_name": "Hazard Zone Buffer Generator",
        "module_1_desc": "Renders real-time flood and landslide risk contours on municipal cadastral maps.",
        "module_2_name": "Evacuation Center Capacity Tracker",
        "module_2_desc": "Monitors shelter bed occupancy and rations in coordination with local disaster officers.",
        "module_3_name": "Offline Emergency Route Navigator",
        "module_3_desc": "Caches evacuation vector pathways locally on client smartphones during telecommunications outages.",
        "abstract": "A community-centered geographic information system mapping barangay hazard zones and dynamic emergency evacuation routes.",
    })
    projects.append({
        "id": "1Y-1S-E3-T2", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Tech Expo", "date": "12/12/2025", "room": "Smart Room", "time": "9:30AM-10:00AM",
        "team_name": "Team IntelliBot", "title": "AI-Powered Campus FAQ Chatbot", "adviser": "Eduardo Padilla",
        "chair": "Renato Villanueva", "panelist": "Florencia Dela Torre", "documenter": "Cecilia Magbanua",
        "members": ["Lucas Alcantara", "Elena Santos", "Mateo Garcia", "Olivia Diaz"],
        "stack": "Django / Python", "domain": "Artificial Intelligence & ML",
        "prereq_course": "IT324 Artificial Intelligence & Data Mining", "career_track": "AI / NLP Engineer",
        "keywords": ["ai", "machine learning", "nlp", "chatgpt", "transformer", "llm", "neural", "artificial intelligence"],
        "frontend_tech": "Web Socket Chat Widget / Vanilla JS", "backend_tech": "Python / LangChain / HuggingFace Transformers",
        "database_tech": "ChromaDB Vector Store & PostgreSQL",
        "module_1_name": "Retrieval-Augmented FAQ Retriever",
        "module_1_desc": "Indexes university student handbooks into dense vector embeddings for sub-second semantic retrieval.",
        "module_2_name": "Intent Classification Router",
        "module_2_desc": "Distinguishes enrollment queries, fee inquiries, and grade dispute procedures with 96% accuracy.",
        "module_3_name": "Faculty Escalation Dispatcher",
        "module_3_desc": "Handoffs unresolved student inquiries to departmental advisers with full transcript context.",
        "abstract": "An AI conversational agent utilizing retrieval-augmented generation to deliver instant, accurate student academic guidance.",
    })
    projects.append({
        "id": "1Y-1S-E3-T3", "year_level": "1st Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "1st Year Tech Expo", "date": "12/12/2025", "room": "Smart Room", "time": "10:00AM-10:30AM",
        "team_name": "Team AgroTech", "title": "Automated Greenhouse Irrigation Controller", "adviser": "Eduardo Padilla",
        "chair": "Renato Villanueva", "panelist": "Florencia Dela Torre", "documenter": "Cecilia Magbanua",
        "members": ["Gabriel Cruz", "Isabella Reyes", "Daniel Lee", "Ava Martinez"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "IoT Robotics Specialist",
        "keywords": ["iot", "sensor", "arduino", "raspberry", "embedded", "actuator", "microcontroller", "smart home"],
        "frontend_tech": "Flutter Web Embedded Dashboard", "backend_tech": "Python Flask MQTT Telemetry Gateway",
        "database_tech": "SQLite Embedded DB with JSON Logging",
        "module_1_name": "Soil Moisture Sensing Node",
        "module_1_desc": "Measures volumetric water content and ambient temperature across agricultural test beds.",
        "module_2_name": "Solenoid Valve Relaying Matrix",
        "module_2_desc": "Controls drip irrigation solenoids with closed-loop threshold PID feedback.",
        "module_3_name": "Solar Battery Power Telemetry",
        "module_3_desc": "Monitors photovoltaic battery voltage ensuring continuous 24/7 agricultural operation.",
        "abstract": "An automated micro-controller hardware deployment regulating precision drip irrigation and energy harvesting for campus research greenhouses.",
    })

    # 1ST YEAR - 2ND SEMESTER (PIT - 3 EVENTS, 3 UNIQUE TEAMS/PROJECTS PER EVENT)
    projects.append({
        "id": "1Y-2S-E1-T1", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year System Design Pitch", "date": "2/20/2026", "room": "Room 301", "time": "9:00AM-9:30AM",
        "team_name": "Team OmniFlow", "title": "Unified Campus Facilities Reservation System", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["James Rivera", "Sofia Lim", "Miguel Torres", "Chloe Nguyen"],
        "stack": "Laravel / PHP", "domain": "Web Applications & Platforms",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "Backend PHP Engineer",
        "keywords": ["laravel", "php", "web", "booking", "portal", "community", "e-commerce"],
        "frontend_tech": "Blade Templates / Alpine.js UI", "backend_tech": "Laravel 11 Framework with Eloquent ORM",
        "database_tech": "MySQL 8.0 with InnoDB Locking",
        "module_1_name": "Facility Conflict Detection Algorithm",
        "module_1_desc": "Guarantees no double-booking for auditoriums, laboratories, and athletic fields.",
        "module_2_name": "Digital Endorsement Workflow",
        "module_2_desc": "Routes student organization facility requests to department chairs and security directors.",
        "module_3_name": "Automated Permit Pass Generator",
        "module_3_desc": "Issues verifiable QR-coded digital access passes for campus security checkpoints.",
        "abstract": "A web reservation portal automating facility bookings, administrative signature endorsements, and access pass issuance.",
    })
    projects.append({
        "id": "1Y-2S-E1-T2", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year System Design Pitch", "date": "2/20/2026", "room": "Room 301", "time": "9:30AM-10:00AM",
        "team_name": "Team VisionGuard", "title": "Computer Vision Attendance Verification", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Lucas Alcantara", "Elena Santos", "Mateo Garcia", "Olivia Diaz"],
        "stack": "Django / Python", "domain": "Artificial Intelligence & ML",
        "prereq_course": "IT324 Artificial Intelligence & Data Mining", "career_track": "Computer Vision Engineer",
        "keywords": ["computer vision", "opencv", "recognition", "detection", "ai", "classifier", "machine learning"],
        "frontend_tech": "Flutter Web Kiosk Interface", "backend_tech": "Python / OpenCV / FaceNet Verification Core",
        "database_tech": "PostgreSQL with Vector Indexing",
        "module_1_name": "Facial Feature Landmark Extractor",
        "module_1_desc": "Extracts 128-dimensional facial embedding vectors resistant to variations in lighting and angle.",
        "module_2_name": "Liveness Anti-Spoofing Detector",
        "module_2_desc": "Detects eye blinking and micro-head movements to prevent photo or video replay fraud.",
        "module_3_name": "Real-time Attendance Sync Engine",
        "module_3_desc": "Pushes timestamped student presence logs straight to faculty grade books.",
        "abstract": "An automated computer vision kiosk capturing biometric facial landmarks for instant and spoof-resistant classroom attendance.",
    })
    projects.append({
        "id": "1Y-2S-E1-T3", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year System Design Pitch", "date": "2/20/2026", "room": "Room 301", "time": "10:00AM-10:30AM",
        "team_name": "Team BioMetric", "title": "RFID Library Access Gate Controller", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Gabriel Cruz", "Isabella Reyes", "Daniel Lee", "Ava Martinez"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "Hardware Firmware Developer",
        "keywords": ["iot", "rfid", "arduino", "hardware", "embedded", "sensor", "actuator"],
        "frontend_tech": "Local LCD 20x4 Display & Web Admin Panel", "backend_tech": "C++ Embedded Firmware on Arduino Mega",
        "database_tech": "PostgreSQL Gateway via REST API",
        "module_1_name": "Mifare RFID Card Interrogator",
        "module_1_desc": "Interrogates 13.56 MHz student ID chips in less than 200 milliseconds.",
        "module_2_name": "Physical Turnstile Servo Trigger",
        "module_2_desc": "Operates optical relay gates upon validating active student enrollment records.",
        "module_3_name": "Patron Peak Headcount Analytics",
        "module_3_desc": "Maintains real-time occupancy headcounts to enforce library fire safety capacity limits.",
        "abstract": "An RFID-actuated access gateway verifying physical student smart cards and synchronizing patron headcounts.",
    })

    # Event 2: 1st Year Midterm Progress Defense
    projects.append({
        "id": "1Y-2S-E2-T1", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year Midterm Progress Defense", "date": "3/27/2026", "room": "Room 303", "time": "9:00AM-9:30AM",
        "team_name": "Team MediTrack", "title": "Student Clinic Health Log App", "adviser": "Teresita Buenaventura",
        "chair": "Arsenio Macasaet", "panelist": "Eduardo Padilla", "documenter": "Cecilia Magbanua",
        "members": ["James Rivera", "Sofia Lim", "Miguel Torres", "Chloe Nguyen"],
        "stack": "Flutter / Mobile", "domain": "Mobile & Ubiquitous Computing",
        "prereq_course": "IT222 Mobile Application Development", "career_track": "Mobile App Developer",
        "keywords": ["mobile", "flutter", "tracker app", "android", "ios", "dart", "geolocation"],
        "frontend_tech": "Flutter Cross-Platform Mobile Suite", "backend_tech": "Django REST Backend / Celery Tasks",
        "database_tech": "PostgreSQL with HIPAA Encrypted Medical Fields",
        "module_1_name": "Medical History & Allergy Diary",
        "module_1_desc": "Stores chronic conditions, emergency contact numbers, and prescription history securely.",
        "module_2_name": "Clinic Appointment Booking Scheduler",
        "module_2_desc": "Enables digital queue reservation for routine medical examinations and dental checkups.",
        "module_3_name": "Epidemiological Symptom Hotspot Tracker",
        "module_3_desc": "Aggregates seasonal influenza and dengue trends across campus residential dormitories.",
        "abstract": "A mobile health application empowering students to maintain personal medical histories and book clinic consultations.",
    })
    projects.append({
        "id": "1Y-2S-E2-T2", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year Midterm Progress Defense", "date": "3/27/2026", "room": "Room 303", "time": "9:30AM-10:00AM",
        "team_name": "Team NetAudit", "title": "Campus Network Intrusion Detection Scanner", "adviser": "Teresita Buenaventura",
        "chair": "Arsenio Macasaet", "panelist": "Eduardo Padilla", "documenter": "Cecilia Magbanua",
        "members": ["Lucas Alcantara", "Elena Santos", "Mateo Garcia", "Olivia Diaz"],
        "stack": "Django / Python", "domain": "Cybersecurity & Network Systems",
        "prereq_course": "IT313 Information Assurance & Security", "career_track": "Network Security Engineer",
        "keywords": ["security", "network", "intrusion", "vulnerability", "firewall", "audit", "penetration"],
        "frontend_tech": "React Enterprise SOC Dashboard", "backend_tech": "Python Scapy Packet Inspection Engine",
        "database_tech": "Elasticsearch Log Cluster & Kibana",
        "module_1_name": "Deep Packet Inspection Analyzer",
        "module_1_desc": "Captures raw promiscuous ethernet frames to detect malicious port scans and ARP spoofing.",
        "module_2_name": "CVE Vulnerability Database Cross-Referencer",
        "module_2_desc": "Audits server software versions against current NIST National Vulnerability Database signatures.",
        "module_3_name": "Automated Defensive Blackholing",
        "module_3_desc": "Interacts with border routers via SSH to drop malicious external attacking subnets dynamically.",
        "abstract": "A network security monitor analyzing packet headers in real-time to detect zero-day intrusions and rogue hardware devices.",
    })
    projects.append({
        "id": "1Y-2S-E2-T3", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year Midterm Progress Defense", "date": "3/27/2026", "room": "Room 303", "time": "10:00AM-10:30AM",
        "team_name": "Team CloudLedger", "title": "Decentralized Student Credential Verification", "adviser": "Teresita Buenaventura",
        "chair": "Arsenio Macasaet", "panelist": "Eduardo Padilla", "documenter": "Cecilia Magbanua",
        "members": ["Gabriel Cruz", "Isabella Reyes", "Daniel Lee", "Ava Martinez"],
        "stack": "Cloud / AWS", "domain": "Cybersecurity & Network Systems",
        "prereq_course": "IT311 Cloud Architecture & Enterprise Systems", "career_track": "Cloud Security Specialist",
        "keywords": ["blockchain", "security", "cryptography", "cloud", "audit", "auth", "aws"],
        "frontend_tech": "React Web3 Verification Portal", "backend_tech": "Node.js Hyperledger Fabric Client",
        "database_tech": "Immutable Distributed Ledger & AWS S3",
        "module_1_name": "Diploma Merkle Root Hasher",
        "module_1_desc": "Generates cryptographically unforgeable proof-of-authenticity hashes for university diplomas.",
        "module_2_name": "Third-Party Employer Validation Portal",
        "module_2_desc": "Allows hiring enterprises to verify graduation credentials instantly without manual registrar inquiry.",
        "module_3_name": "Revocation Registry Smart Contract",
        "module_3_desc": "Enables registrar administrators to revoke fraudulently issued credentials in an immutable audit ledger.",
        "abstract": "A cloud-backed cryptographic verification platform guaranteeing the authenticity and unalterability of collegiate credentials.",
    })

    # Event 3: 1st Year Year-End Showcase
    projects.append({
        "id": "1Y-2S-E3-T1", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year Year-End Showcase", "date": "5/15/2026", "room": "Multimedia Lab", "time": "9:00AM-9:30AM",
        "team_name": "Team TerraMap", "title": "Campus Cadastral Land Navigation System", "adviser": "Arsenio Macasaet",
        "chair": "Florencia Dela Torre", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["James Rivera", "Sofia Lim", "Miguel Torres", "Chloe Nguyen"],
        "stack": "GIS / Mapping", "domain": "GIS & Smart Community",
        "prereq_course": "IT322 Geographic Information Systems", "career_track": "GIS Systems Specialist",
        "keywords": ["gis", "map", "mapping", "cadastral", "land", "spatial", "location", "geo"],
        "frontend_tech": "OpenLayers / React Spatial Viewer", "backend_tech": "GeoDjango / Python PostGIS API",
        "database_tech": "PostGIS Enterprise GeoDatabase",
        "module_1_name": "Cadastral Boundary Parcel Mapper",
        "module_1_desc": "Visualizes university perimeter lot surveys, easement limits, and architectural building footprints.",
        "module_2_name": "Subsurface Utility Layer Visualizer",
        "module_2_desc": "Maps buried electrical conduits and water pipelines to prevent utility strikes during campus construction.",
        "module_3_name": "Zoning & Space Utilization Analyzer",
        "module_3_desc": "Calculates floor-to-area ratios (FAR) to guide campus future infrastructure master planning.",
        "abstract": "An enterprise cadastral spatial platform cataloging land parcels, infrastructure footprints, and underground utility vectors.",
    })
    projects.append({
        "id": "1Y-2S-E3-T2", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year Year-End Showcase", "date": "5/15/2026", "room": "Multimedia Lab", "time": "9:30AM-10:00AM",
        "team_name": "Team InsightBI", "title": "Graduation Outcome Predictive Analytics", "adviser": "Arsenio Macasaet",
        "chair": "Florencia Dela Torre", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Lucas Alcantara", "Elena Santos", "Mateo Garcia", "Olivia Diaz"],
        "stack": "Django / Python", "domain": "Data Analytics & BI",
        "prereq_course": "IT221 Data Analysis & Visualization", "career_track": "Data Scientist",
        "keywords": ["analytics", "dashboard", "mining", "visualization", "forecasting", "reporting", "big data"],
        "frontend_tech": "D3.js Interactive Analytics Charts", "backend_tech": "Python Scikit-Learn Regression Models",
        "database_tech": "PostgreSQL Data Warehouse",
        "module_1_name": "On-Time Graduation Probability Classifier",
        "module_1_desc": "Applies logistic regression over historical semester transcripts to predict graduation timelines.",
        "module_2_name": "Prerequisite Bottleneck Heatmap",
        "module_2_desc": "Highlights specific curriculum subjects causing high student delay and repeat rates.",
        "module_3_name": "Executive Accreditation Report Exporter",
        "module_3_desc": "Compiles formal CHED and PACUCOA accreditation statistical cohorts automatically.",
        "abstract": "A predictive data science dashboard analyzing historical cohort performance to identify academic hurdles and forecast graduation outcomes.",
    })
    projects.append({
        "id": "1Y-2S-E3-T3", "year_level": "1st Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "1st Year Year-End Showcase", "date": "5/15/2026", "room": "Multimedia Lab", "time": "10:00AM-10:30AM",
        "team_name": "Team Immersion3D", "title": "Interactive Campus Virtual Tour", "adviser": "Arsenio Macasaet",
        "chair": "Florencia Dela Torre", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Gabriel Cruz", "Isabella Reyes", "Daniel Lee", "Ava Martinez"],
        "stack": "AR / Unity", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "3D Interactive Media Developer",
        "keywords": ["ar", "vr", "unity", "augmented", "virtual", "web"],
        "frontend_tech": "Unity WebGL / Three.js 3D Engine", "backend_tech": "Node.js Spatial Asset CDN",
        "database_tech": "MongoDB Asset Metadata Store",
        "module_1_name": "Photorealistic 3D Campus Mesh Renderer",
        "module_1_desc": "Renders real-time 3D geometry of university monuments, lecture halls, and laboratories in web browsers.",
        "module_2_name": "Interactive Point-of-Interest (POI) Markers",
        "module_2_desc": "Provides clickable audio-visual informational overlays explaining historic university landmarks.",
        "module_3_name": "Multi-User Virtual Open House Gateway",
        "module_3_desc": "Enables prospective students globally to explore campus facilities during admissions events.",
        "abstract": "A 3D virtual tour platform rendering interactive campus models in web browsers for remote student orientation.",
    })

    # 2ND YEAR - 1ST SEMESTER (PIT - 3 EVENTS, 3 UNIQUE TEAMS/PROJECTS PER EVENT)
    projects.append({
        "id": "2Y-1S-E1-T1", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Architecture Pitch", "date": "10/24/2025", "room": "Room 302", "time": "9:00AM-9:30AM",
        "team_name": "Team Quantum", "title": "Automated Grade Calculator & Prerequisite Engine", "adviser": "Renato Villanueva",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Darren Kim", "Isabel Cruz", "Noah Ramos", "Leah Fernandez"],
        "stack": "Django / Python", "domain": "Data Analytics & BI",
        "prereq_course": "IT221 Data Analysis & Visualization", "career_track": "Data Analyst",
        "keywords": ["django", "python", "grade", "tracker", "analytics", "dashboard", "grade tracker"],
        "frontend_tech": "React Bootstrap Data Dashboard", "backend_tech": "Django ORM / Python Calculation Kernel",
        "database_tech": "PostgreSQL 16 Enterprise Relational DB",
        "module_1_name": "Weighted Rubric Grade Calculator",
        "module_1_desc": "Calculates composite term marks honoring variable laboratory and lecture weighting percentages.",
        "module_2_name": "Prerequisite Eligibility Validator",
        "module_2_desc": "Audits curriculum advancement criteria before permitting student enrollment into advanced subjects.",
        "module_3_name": "Scholastic Honors & Deans List Filter",
        "module_3_desc": "Identifies honor candidates free of failing marks in strict accordance with university manual.",
        "abstract": "An automated grading and curriculum evaluation platform enforcing institutional grade calculations and prerequisite gates.",
    })
    projects.append({
        "id": "2Y-1S-E1-T2", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Architecture Pitch", "date": "10/24/2025", "room": "Room 302", "time": "9:30AM-10:00AM",
        "team_name": "Team CircuitCore", "title": "Smart Laboratory Power Automation", "adviser": "Renato Villanueva",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Nathan Lopez", "Mia Valenzuela", "Leo Mendoza", "Chloe Castillo"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "IoT Firmware Engineer",
        "keywords": ["iot", "arduino", "esp32", "sensor", "smart home", "automation", "embedded"],
        "frontend_tech": "Vue.js Lab Management Panel", "backend_tech": "Node.js MQTT Microservice Broker",
        "database_tech": "MongoDB TimeSeries Store",
        "module_1_name": "Current Sensor Bench Monitor",
        "module_1_desc": "Monitors current draw across 40 individual electronics laboratory workbenches.",
        "module_2_name": "Automatic Schedule-Based Circuit Breaker",
        "module_2_desc": "Disconnects mains power automatically at laboratory dismissal time to prevent electrical fire hazards.",
        "module_3_name": "Emergency Master Shut-off Trigger",
        "module_3_desc": "Enables instructors to de-energize workbenches instantly from mobile devices in hazard events.",
        "abstract": "An embedded IoT electrical governance system automating workbench power schedules and providing emergency shutoff controls.",
    })
    projects.append({
        "id": "2Y-1S-E1-T3", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Architecture Pitch", "date": "10/24/2025", "room": "Room 302", "time": "10:00AM-10:30AM",
        "team_name": "Team SwiftPortal", "title": "Departmental Inventory & Procurement SaaS", "adviser": "Renato Villanueva",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Oliver Aquino", "Emma Corpuz", "Ethan Rivera", "Sophia Sy"],
        "stack": "Cloud / AWS", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT311 Cloud Architecture & Enterprise Systems", "career_track": "Enterprise Cloud Engineer",
        "keywords": ["cloud", "saas", "erp", "inventory", "procurement", "aws", "docker", "portal"],
        "frontend_tech": "React Enterprise UI / Tailwind", "backend_tech": "Java Spring Boot / Dockerized Containers",
        "database_tech": "Amazon Aurora PostgreSQL",
        "module_1_name": "Asset Barcode & QR Serialization",
        "module_1_desc": "Tracks individual computer monitors, oscilloscopes, and developmental boards throughout lifespan.",
        "module_2_name": "Automated Low-Stock Procurement Requisition",
        "module_2_desc": "Generates purchase orders when laboratory consumables cross safety thresholds.",
        "module_3_name": "Annual Depreciation Ledger",
        "module_3_desc": "Calculates straight-line equipment depreciation accounting for university fiscal audits.",
        "abstract": "A cloud SaaS application managing collegiate physical assets, procurement life cycles, and equipment depreciation.",
    })

    # Event 2: 2nd Year Milestone Review
    projects.append({
        "id": "2Y-1S-E2-T1", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Milestone Review", "date": "11/14/2025", "room": "Room 301", "time": "9:00AM-9:30AM",
        "team_name": "Team MobileCare", "title": "Campus Health & Teleconsultation Mobile App", "adviser": "Jonathan Beltran",
        "chair": "Analiza Corpuz", "panelist": "Eduardo Padilla", "documenter": "Cecilia Magbanua",
        "members": ["Darren Kim", "Isabel Cruz", "Noah Ramos", "Leah Fernandez"],
        "stack": "Flutter / Mobile", "domain": "Mobile & Ubiquitous Computing",
        "prereq_course": "IT222 Mobile Application Development", "career_track": "Mobile App Developer",
        "keywords": ["flutter", "mobile", "android", "ios", "tracker app", "dart", "geolocation"],
        "frontend_tech": "Flutter 3.x Mobile Client", "backend_tech": "Django REST Web Framework",
        "database_tech": "PostgreSQL with AES Encryption",
        "module_1_name": "Telehealth Video Consultation Gateway",
        "module_1_desc": "Connects quarantined students to university physicians over encrypted WebRTC video sessions.",
        "module_2_name": "Digital Prescription Delivery",
        "module_2_desc": "Issues digitally signed medical prescriptions directly to university pharmacy kiosks.",
        "module_3_name": "Mental Wellness Self-Assessment Module",
        "module_3_desc": "Provides confidential standardized psychological assessments connecting students to campus guidance counselors.",
        "abstract": "A mobile teleconsultation platform facilitating confidential physician appointments and digital prescription dispatch.",
    })
    projects.append({
        "id": "2Y-1S-E2-T2", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Milestone Review", "date": "11/14/2025", "room": "Room 301", "time": "9:30AM-10:00AM",
        "team_name": "Team GeoAlert", "title": "Flood Hazard GIS Early Warning System", "adviser": "Jonathan Beltran",
        "chair": "Analiza Corpuz", "panelist": "Eduardo Padilla", "documenter": "Cecilia Magbanua",
        "members": ["Nathan Lopez", "Mia Valenzuela", "Leo Mendoza", "Chloe Castillo"],
        "stack": "GIS / Mapping", "domain": "GIS & Smart Community",
        "prereq_course": "IT322 Geographic Information Systems", "career_track": "Geospatial Data Engineer",
        "keywords": ["gis", "map", "mapping", "geo", "spatial", "disaster", "evacuation", "location"],
        "frontend_tech": "Mapbox GL JS / React Spatial UI", "backend_tech": "FastAPI Python / Hydrological Models",
        "database_tech": "PostGIS Enterprise GeoSpatial DB",
        "module_1_name": "River Basin Telemetry Interpolator",
        "module_1_desc": "Interpolates ultrasonic river water level sensors into real-time flood inundation vectors.",
        "module_2_name": "Automated SMS Geofenced Broadcast",
        "module_2_desc": "Dispatches localized emergency evacuation alerts to residents within threatened flood polygons.",
        "module_3_name": "Road Inundation Impedance Modeler",
        "module_3_desc": "Recalculates dynamic vehicular rescue routes avoiding flooded arterial roads.",
        "abstract": "A hydrological GIS early warning platform predicting urban flash floods and routing rescue personnel away from inundated corridors.",
    })
    projects.append({
        "id": "2Y-1S-E2-T3", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Milestone Review", "date": "11/14/2025", "room": "Room 301", "time": "10:00AM-10:30AM",
        "team_name": "Team CodeForge", "title": "Interactive Programming Assessment Sandbox", "adviser": "Jonathan Beltran",
        "chair": "Analiza Corpuz", "panelist": "Eduardo Padilla", "documenter": "Cecilia Magbanua",
        "members": ["Oliver Aquino", "Emma Corpuz", "Ethan Rivera", "Sophia Sy"],
        "stack": "React / Node.js", "domain": "Web Applications & Platforms",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "Full-Stack Software Engineer",
        "keywords": ["react", "node", "javascript", "quiz", "builder", "web", "peer"],
        "frontend_tech": "React / Monaco Code Editor (VS Code Web)", "backend_tech": "Node.js / Dockerized gVisor Sandboxes",
        "database_tech": "PostgreSQL & Redis Queue",
        "module_1_name": "Secure Micro-Container Code Evaluator",
        "module_1_desc": "Executes untrusted student C++, Java, and Python submissions in isolated non-root containers.",
        "module_2_name": "Automated Unit Test Grading Engine",
        "module_2_desc": "Evaluates submitted algorithms against hidden edge test cases, assessing memory and execution runtime.",
        "module_3_name": "Plagiarism AST Token Comparison",
        "module_3_desc": "Analyzes abstract syntax trees across cohort submissions to detect variable-renaming code copying.",
        "abstract": "A containerized programming assessment environment delivering real-time code execution, automated unit test scoring, and syntax plagiarism checks.",
    })

    # Event 3: 2nd Year Innovation Expo
    projects.append({
        "id": "2Y-1S-E3-T1", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Innovation Expo", "date": "12/12/2025", "room": "Room 303", "time": "9:00AM-9:30AM",
        "team_name": "Team NeuroSense", "title": "Facial Emotion Recognition for E-Learning", "adviser": "Florencia Dela Torre",
        "chair": "Ricardo Fontanilla", "panelist": "Teresita Buenaventura", "documenter": "Cecilia Magbanua",
        "members": ["Darren Kim", "Isabel Cruz", "Noah Ramos", "Leah Fernandez"],
        "stack": "Django / Python", "domain": "Artificial Intelligence & ML",
        "prereq_course": "IT324 Artificial Intelligence & Data Mining", "career_track": "Machine Learning Specialist",
        "keywords": ["ai", "machine learning", "deep learning", "neural", "computer vision", "classifier", "detection"],
        "frontend_tech": "React Classroom HUD Interface", "backend_tech": "PyTorch / FastAPI Deep Learning Worker",
        "database_tech": "PostgreSQL / Redis Streams",
        "module_1_name": "Facial Action Coding Emotion Classifier",
        "module_1_desc": "Classifies student cognitive engagement (Confusion, Boredom, Focus) via facial micro-expressions.",
        "module_2_name": "Aggregated Lecture Engagement Telemetry",
        "module_2_desc": "Provides professors with real-time graphs showing comprehension drops during complex lecture slides.",
        "module_3_name": "Adaptive Quiz Trigger Engine",
        "module_3_desc": "Automatically serves explanatory mini-quizzes when cohort confusion rates exceed 40%.",
        "abstract": "An educational AI tool classifying student affective engagement during synchronous lectures to optimize instructional delivery.",
    })
    projects.append({
        "id": "2Y-1S-E3-T2", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Innovation Expo", "date": "12/12/2025", "room": "Room 303", "time": "9:30AM-10:00AM",
        "team_name": "Team SecureLink", "title": "Zero-Trust Network Access Controller", "adviser": "Florencia Dela Torre",
        "chair": "Ricardo Fontanilla", "panelist": "Teresita Buenaventura", "documenter": "Cecilia Magbanua",
        "members": ["Nathan Lopez", "Mia Valenzuela", "Leo Mendoza", "Chloe Castillo"],
        "stack": "Django / Python", "domain": "Cybersecurity & Network Systems",
        "prereq_course": "IT313 Information Assurance & Security", "career_track": "Cybersecurity Architect",
        "keywords": ["security", "firewall", "encryption", "auth", "network", "vulnerability", "audit"],
        "frontend_tech": "Angular Network Topology Visualizer", "backend_tech": "Python / WireGuard VPN Kernel Interface",
        "database_tech": "PostgreSQL & Redis Session Cache",
        "module_1_name": "Device Posture Assessment Agent",
        "module_1_desc": "Verifies OS patch level and antivirus status before granting access to internal university servers.",
        "module_2_name": "Micro-Segmentation Tunnel Provisioner",
        "module_2_desc": "Establishes isolated, encrypted WireGuard point-to-point tunnels tailored strictly to authorized applications.",
        "module_3_name": "Continuous Anomaly Re-Authenticator",
        "module_3_desc": "Revokes active session tokens dynamically upon detecting anomalous geographical IP jumps.",
        "abstract": "A zero-trust identity and device posture controller restricting university intranet resources through micro-segmented encrypted tunnels.",
    })
    projects.append({
        "id": "2Y-1S-E3-T3", "year_level": "2nd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "2nd Year Innovation Expo", "date": "12/12/2025", "room": "Room 303", "time": "10:00AM-10:30AM",
        "team_name": "Team MicroLogistics", "title": "Automated Package Delivery Drone Routing", "adviser": "Florencia Dela Torre",
        "chair": "Ricardo Fontanilla", "panelist": "Teresita Buenaventura", "documenter": "Cecilia Magbanua",
        "members": ["Oliver Aquino", "Emma Corpuz", "Ethan Rivera", "Sophia Sy"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "Robotics & Embedded Dev",
        "keywords": ["iot", "robotics", "embedded", "sensor", "microcontroller", "hardware", "automation"],
        "frontend_tech": "QGroundControl Custom React Overlay", "backend_tech": "ROS 2 (Robot Operating System) on Raspberry Pi 4",
        "database_tech": "SQLite Telemetry Flight Logger",
        "module_1_name": "Autonomous Waypoint Mission Planner",
        "module_1_desc": "Calculates obstacle-free 3D airspace routes across campus buildings for urgent medical sample delivery.",
        "module_2_name": "LiDAR Anti-Collision Sensor Matrix",
        "module_2_desc": "Maintains a 5-meter safety bubble around UAV during low-altitude hover maneuvers.",
        "module_3_name": "Automated Winch Payload Drop Controller",
        "module_3_desc": "Lowers packages onto designated target optical fiducial markers smoothly without landing.",
        "abstract": "An autonomous robotics platform coordinating indoor-outdoor UAV delivery routes for inter-building specimen transfers.",
    })

    # 2ND YEAR - 2ND SEMESTER (PIT - 3 EVENTS, 3 UNIQUE TEAMS/PROJECTS PER EVENT)
    projects.append({
        "id": "2Y-2S-E1-T1", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year System Pitch", "date": "2/20/2026", "room": "Room 302", "time": "9:00AM-9:30AM",
        "team_name": "Team CoreERP", "title": "University Student Org Finance & Payroll ERP", "adviser": "Renato Villanueva",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Darren Kim", "Isabel Cruz", "Noah Ramos", "Leah Fernandez"],
        "stack": "Laravel / PHP", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT311 Cloud Architecture & Enterprise Systems", "career_track": "Enterprise Systems Developer",
        "keywords": ["erp", "payroll", "billing", "saas", "management system", "portal", "cloud", "laravel", "php"],
        "frontend_tech": "Vue.js Financial Ledger Component", "backend_tech": "Laravel 11 Multi-Tenant Core",
        "database_tech": "MySQL 8.0 with Double-Entry Bookkeeping",
        "module_1_name": "Double-Entry General Ledger",
        "module_1_desc": "Enforces balanced debits and credits for student organizational disbursements and collection dues.",
        "module_2_name": "Reimbursement Voucher Approval Hierarchy",
        "module_2_desc": "Routes receipt images through faculty advisers, treasurers, and student affairs auditors.",
        "module_3_name": "Automated Financial Statement Exporter",
        "module_3_desc": "Generates standardized trial balance sheets and cash flow statements for student council elections.",
        "abstract": "A multi-tenant cloud ERP platform delivering audited double-entry bookkeeping and reimbursement validation for campus societies.",
    })
    projects.append({
        "id": "2Y-2S-E1-T2", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year System Pitch", "date": "2/20/2026", "room": "Room 302", "time": "9:30AM-10:00AM",
        "team_name": "Team VisionBot", "title": "YOLO-Based Campus Parking Space Monitor", "adviser": "Renato Villanueva",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Nathan Lopez", "Mia Valenzuela", "Leo Mendoza", "Chloe Castillo"],
        "stack": "Django / Python", "domain": "Artificial Intelligence & ML",
        "prereq_course": "IT324 Artificial Intelligence & Data Mining", "career_track": "Computer Vision Engineer",
        "keywords": ["yolo", "detection", "computer vision", "recognition", "ai", "machine learning", "prediction"],
        "frontend_tech": "Flutter Mobile & Electronic Highway Signboard", "backend_tech": "Python / YOLOv8 / DeepSORT Tracking",
        "database_tech": "PostgreSQL with Spatial Slot Mapping",
        "module_1_name": "Real-time Vehicle Detection Bounding Core",
        "module_1_desc": "Identifies vacant and occupied parking slots from overhead CCTV video feeds with 98% accuracy.",
        "module_2_name": "License Plate OCR Indexer",
        "module_2_desc": "Extracts vehicle registration numbers during entry to prevent unauthorized parking lot overnight storage.",
        "module_3_name": "Digital Wayfinding Display Driver",
        "module_3_desc": "Updates outdoor LED signage directing motorists toward sectors with remaining vacant slots.",
        "abstract": "An AI vision analytics system executing real-time object detection across parking camera feeds to eliminate campus traffic bottlenecks.",
    })
    projects.append({
        "id": "2Y-2S-E1-T3", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year System Pitch", "date": "2/20/2026", "room": "Room 302", "time": "10:00AM-10:30AM",
        "team_name": "Team HydroMonitor", "title": "IoT Water Quality & Consumption Tracker", "adviser": "Renato Villanueva",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Oliver Aquino", "Emma Corpuz", "Ethan Rivera", "Sophia Sy"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "Smart Cities IoT Developer",
        "keywords": ["iot", "sensor", "arduino", "hardware", "embedded", "smart home", "automation"],
        "frontend_tech": "React Dashboard / WebSockets", "backend_tech": "Node.js IoT Gateway",
        "database_tech": "TimescaleDB Time-Series Engine",
        "module_1_name": "Water Potability Sensor Suite",
        "module_1_desc": "Measures Total Dissolved Solids (TDS), pH, and turbidity in campus drinking fountains.",
        "module_2_name": "Acoustic Pipe Leakage Detector",
        "module_2_desc": "Monitors nighttime acoustic pipe vibrations to flag subterranean water line bursts.",
        "module_3_name": "Consumption Forecasting & Anomaly Alerts",
        "module_3_desc": "Alerts campus facility engineers when water flow rates indicate stuck flush valves.",
        "abstract": "An IoT smart hardware network tracking water quality parameters and pinpointing distribution leaks across campus facilities.",
    })

    # Event 2: 2nd Year Midterm Defense
    projects.append({
        "id": "2Y-2S-E2-T1", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year Midterm Defense", "date": "3/27/2026", "room": "Room 301", "time": "9:00AM-9:30AM",
        "team_name": "Team MapPulse", "title": "Smart Public Transit Route Navigator", "adviser": "Eduardo Padilla",
        "chair": "Jonathan Beltran", "panelist": "Renato Villanueva", "documenter": "Cecilia Magbanua",
        "members": ["Darren Kim", "Isabel Cruz", "Noah Ramos", "Leah Fernandez"],
        "stack": "GIS / Mapping", "domain": "GIS & Smart Community",
        "prereq_course": "IT322 Geographic Information Systems", "career_track": "Transit GIS Specialist",
        "keywords": ["gis", "map", "mapping", "location", "geo", "spatial", "disaster"],
        "frontend_tech": "Flutter Mobile with OpenStreetMap Layer", "backend_tech": "Python / OpenTripPlanner Routing Engine",
        "database_tech": "PostGIS Enterprise GeoSpatial DB",
        "module_1_name": "Live Public Transit Fleet Tracker",
        "module_1_desc": "Streams real-time geographic positions of public utility vehicles servicing university gates.",
        "module_2_name": "Intermodal Transfer Time Estimator",
        "module_2_desc": "Calculates arrival times and transfer costs for multi-leg commuter journeys across the metropolis.",
        "module_3_name": "Crowdsourced Passenger Density Meter",
        "module_3_desc": "Allows passengers to report on-board seating availability and traffic bottlenecks.",
        "abstract": "A transit GIS platform calculating optimized intermodal urban commuter routes with live vehicle tracking.",
    })
    projects.append({
        "id": "2Y-2S-E2-T2", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year Midterm Defense", "date": "3/27/2026", "room": "Room 301", "time": "9:30AM-10:00AM",
        "team_name": "Team SentinelX", "title": "Web Vulnerability Scanner & Penetration Tester", "adviser": "Eduardo Padilla",
        "chair": "Jonathan Beltran", "panelist": "Renato Villanueva", "documenter": "Cecilia Magbanua",
        "members": ["Nathan Lopez", "Mia Valenzuela", "Leo Mendoza", "Chloe Castillo"],
        "stack": "Django / Python", "domain": "Cybersecurity & Network Systems",
        "prereq_course": "IT313 Information Assurance & Security", "career_track": "Application Security Engineer",
        "keywords": ["security", "vulnerability", "penetration", "audit", "cryptography", "auth", "firewall"],
        "frontend_tech": "React Security Audit Explorer", "backend_tech": "Python Asynchronous Security Crawler",
        "database_tech": "PostgreSQL & Redis Task Broker",
        "module_1_name": "OWASP Top 10 Attack Vector Prober",
        "module_1_desc": "Audits endpoints for SQL injection, Cross-Site Scripting (XSS), and Cross-Site Request Forgery (CSRF).",
        "module_2_name": "Automated SSL/TLS Cipher Suite Auditor",
        "module_2_desc": "Evaluates cryptographic protocol deprecation and weak Diffie-Hellman parameters on public domains.",
        "module_3_name": "Executive Vulnerability Remediation Exporter",
        "module_3_desc": "Generates scored vulnerability reports mapped directly to CVSS v3.1 severity metrics.",
        "abstract": "An automated penetration testing suite crawling institutional web servers to remediate OWASP Top 10 security vulnerabilities.",
    })
    projects.append({
        "id": "2Y-2S-E2-T3", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year Midterm Defense", "date": "3/27/2026", "room": "Room 301", "time": "10:00AM-10:30AM",
        "team_name": "Team LearnSphere", "title": "Gamified Low-Code Courseware Builder", "adviser": "Eduardo Padilla",
        "chair": "Jonathan Beltran", "panelist": "Renato Villanueva", "documenter": "Cecilia Magbanua",
        "members": ["Oliver Aquino", "Emma Corpuz", "Ethan Rivera", "Sophia Sy"],
        "stack": "React / Node.js", "domain": "Web Applications & Platforms",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "EdTech Solutions Architect",
        "keywords": ["react", "node", "javascript", "lowcode", "builder", "quiz", "web"],
        "frontend_tech": "React Drag-and-Drop Canvas (React Flow)", "backend_tech": "Node.js / Express Courseware Compiler",
        "database_tech": "MongoDB JSON Document Store",
        "module_1_name": "Visual Drag-and-Drop Curriculum Canvas",
        "module_1_desc": "Empowers non-technical faculty to build branching interactive scenario exercises visually.",
        "module_2_name": "SCORM & xAPI Interactive Exporter",
        "module_2_desc": "Compiles interactive learning modules compliant with Blackboard, Canvas, and Moodle LMS standards.",
        "module_3_name": "Gamification Badging & Leaderboard Engine",
        "module_3_desc": "Awards verifiable micro-credentials and digital badges upon passing mastery assessments.",
        "abstract": "A low-code visual courseware builder compiling gamified scenario lessons compatible with enterprise learning management systems.",
    })

    # Event 3: 2nd Year Project Showcase
    projects.append({
        "id": "2Y-2S-E3-T1", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year Project Showcase", "date": "5/15/2026", "room": "Room 301", "time": "9:00AM-9:30AM",
        "team_name": "Team ApexAnalytics", "title": "Institutional Faculty Research Metric Dashboard", "adviser": "Analiza Corpuz",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Darren Kim", "Isabel Cruz", "Noah Ramos", "Leah Fernandez"],
        "stack": "Django / Python", "domain": "Data Analytics & BI",
        "prereq_course": "IT221 Data Analysis & Visualization", "career_track": "Research Intelligence Analyst",
        "keywords": ["analytics", "dashboard", "visualization", "mining", "reporting", "big data"],
        "frontend_tech": "Vue.js & Highcharts Enterprise", "backend_tech": "Django / Python Web Scraping & Aggregator",
        "database_tech": "PostgreSQL Analytics Warehouse",
        "module_1_name": "Scopus & Google Scholar Publication Harvester",
        "module_1_desc": "Aggregates faculty citations, h-index, and journal impact factor metrics automatically.",
        "module_2_name": "Departmental Collaboration Graph Visualizer",
        "module_2_desc": "Visualizes cross-disciplinary research co-authorship networks across academic institutes.",
        "module_3_name": "Research Grant Expenditure Tracker",
        "module_3_desc": "Monitors government-funded project milestone progress and budget utilization velocity.",
        "abstract": "An academic intelligence analytics platform indexing collegiate research citations, h-index progressions, and interdisciplinary collaborations.",
    })
    projects.append({
        "id": "2Y-2S-E3-T2", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year Project Showcase", "date": "5/15/2026", "room": "Room 301", "time": "9:30AM-10:00AM",
        "team_name": "Team PocketCampus", "title": "Campus Event Geolocation Attendance App", "adviser": "Analiza Corpuz",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Nathan Lopez", "Mia Valenzuela", "Leo Mendoza", "Chloe Castillo"],
        "stack": "Flutter / Mobile", "domain": "Mobile & Ubiquitous Computing",
        "prereq_course": "IT222 Mobile Application Development", "career_track": "Mobile App Developer",
        "keywords": ["mobile", "flutter", "dart", "geolocation", "attendance app", "tracker app", "android"],
        "frontend_tech": "Flutter Mobile Client / Dart", "backend_tech": "FastAPI Python / PostGIS",
        "database_tech": "PostgreSQL with Spatial Indices",
        "module_1_name": "Geofenced Check-In Perimeter Enforcer",
        "module_1_desc": "Restricts event sign-in to attendees physically located within the auditorium boundary polygon.",
        "module_2_name": "Anti-Mock Location Validator",
        "module_2_desc": "Detects Android developer options and fake GPS spoofing applications to safeguard attendance validity.",
        "module_3_name": "Digital Participation Certificate Issuer",
        "module_3_desc": "Dispatches cryptographically signed PDF seminar certificates immediately upon checkout.",
        "abstract": "A mobile event check-in platform verifying attendee presence through strict polygon geofencing and anti-spoofing heuristics.",
    })
    projects.append({
        "id": "2Y-2S-E3-T3", "year_level": "2nd Year", "semester": "2nd Semester", "track": "PIT",
        "event_or_stage": "2nd Year Project Showcase", "date": "5/15/2026", "room": "Room 301", "time": "10:00AM-10:30AM",
        "team_name": "Team HoloLearn", "title": "Augmented Reality Anatomy Lab Simulator", "adviser": "Analiza Corpuz",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Oliver Aquino", "Emma Corpuz", "Ethan Rivera", "Sophia Sy"],
        "stack": "AR / Unity", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "Spatial Computing / AR Developer",
        "keywords": ["ar", "vr", "unity", "augmented", "virtual"],
        "frontend_tech": "Unity AR Foundation / ARKit / ARCore", "backend_tech": "Node.js Cloud Model Asset Bundler",
        "database_tech": "AWS CloudFront & S3",
        "module_1_name": "Anatomical Plane Raycast Dissector",
        "module_1_desc": "Superimposes high-polygon skeletal and circulatory models over flat laboratory desks.",
        "module_2_name": "Interactive Haptic Organ Probe",
        "module_2_desc": "Delivers mobile haptic vibration feedback as students isolate anatomical structures.",
        "module_3_name": "Spatial Knowledge Pinpoint Evaluation",
        "module_3_desc": "Administers timed quizzes where students must locate specific nerves and muscles in augmented space.",
        "abstract": "An augmented reality instructional application projecting interactive 3D anatomical models onto physical laboratory surfaces.",
    })

    # 3RD YEAR - 1ST SEMESTER (PIT - 3 EVENTS, 3 UNIQUE TEAMS/PROJECTS PER EVENT)
    projects.append({
        "id": "3Y-1S-E1-T1", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Capstone Readiness Pitch", "date": "10/24/2025", "room": "Room 301", "time": "9:00AM-9:30AM",
        "team_name": "Team CodeLearners", "title": "Smart Campus Navigator & Spatial Guide", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Carlos Reyes", "Maria Santos", "Juan Dela Cruz", "Ana Mendoza"],
        "stack": "Flutter / Mobile", "domain": "Mobile & Ubiquitous Computing",
        "prereq_course": "IT222 Mobile Application Development", "career_track": "Mobile App Developer",
        "keywords": ["flutter", "mobile", "geolocation", "map", "gis", "dart", "tracker app", "android"],
        "frontend_tech": "Flutter Cross-Platform Framework / Dart", "backend_tech": "Django REST Backend / Python 3.12",
        "database_tech": "PostgreSQL / PostGIS Spatial Database",
        "module_1_name": "Beacon-Assisted Indoor Location Engine",
        "module_1_desc": "Combines Bluetooth Low Energy (BLE) RSSI signals with smartphone IMU dead-reckoning.",
        "module_2_name": "Dynamic Event Spatial Calendar",
        "module_2_desc": "Pins college festivals, guest seminars, and student presentations onto a zoomable 2D campus vector map.",
        "module_3_name": "Multilingual Audio Guide Synthesizer",
        "module_3_desc": "Synthesizes contextual voice-guided navigation in English, Tagalog, and Bisaya.",
        "abstract": "A mobile spatial application combining BLE beacons and PostGIS routing to deliver indoor-outdoor guidance across university buildings.",
    })
    projects.append({
        "id": "3Y-1S-E1-T2", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Capstone Readiness Pitch", "date": "10/24/2025", "room": "Room 301", "time": "9:30AM-10:00AM",
        "team_name": "Team SensorGrid", "title": "IoT-Based Smart Classroom Environmental Monitor", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Jose Garcia", "Liza Torres", "Marco Villanueva", "Nina Flores"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "IoT Solutions Engineer",
        "keywords": ["iot", "arduino", "esp32", "sensor", "embedded", "automation", "hardware"],
        "frontend_tech": "Vue.js Real-time Dashboard with WebSockets", "backend_tech": "Node.js MQTT Stream Broker & InfluxDB",
        "database_tech": "InfluxDB TimeSeries & PostgreSQL Metadata",
        "module_1_name": "High-Precision Indoor Air Quality Node",
        "module_1_desc": "Samples particulate matter (PM2.5), volatile organic compounds (VOC), and temperature every 2 seconds.",
        "module_2_name": "Acoustic Noise Pollution Alerter",
        "module_2_desc": "Flags decibel levels exceeding 70 dB during official university examination sessions.",
        "module_3_name": "Smart Energy Recovery Ventilator Trigger",
        "module_3_desc": "Operates motorized intake dampers automatically when carbon dioxide crosses 1000 ppm.",
        "abstract": "An industrial IoT telemetry array measuring particulate matter, noise, and carbon dioxide to maintain optimal learning environments.",
    })
    projects.append({
        "id": "3Y-1S-E1-T3", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Capstone Readiness Pitch", "date": "10/24/2025", "room": "Room 301", "time": "10:00AM-10:30AM",
        "team_name": "Team ServiceDesk", "title": "Campus Helpdesk Ticket & Incident Dispatcher", "adviser": "Ricardo Fontanilla",
        "chair": "Maricel Suarez", "panelist": "Jonathan Beltran", "documenter": "Cecilia Magbanua",
        "members": ["Diego Ramos", "Patricia Cruz", "Ryan Bautista", "Sophia Aquino"],
        "stack": "React / Node.js", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT311 Cloud Architecture & Enterprise Systems", "career_track": "Enterprise Cloud Architect",
        "keywords": ["saas", "portal", "cloud", "management system", "react", "node", "javascript"],
        "frontend_tech": "React 18 / Tailwind Ticket Board", "backend_tech": "Express.js / Node.js API Service",
        "database_tech": "PostgreSQL Relational Storage",
        "module_1_name": "Automated IT Service Desk Dispatcher",
        "module_1_desc": "Routes technical repair tickets to available departmental technicians using round-robin queues.",
        "module_2_name": "SLA Escalation Timer Daemon",
        "module_2_desc": "Escalates unresolved campus network or hardware faults to department heads when breach limits approach.",
        "module_3_name": "Customer Satisfaction Telemetry Engine",
        "module_3_desc": "Gathers instant five-star faculty ratings upon incident ticket closure to benchmark support quality.",
        "abstract": "A cloud service desk automation portal managing IT incident tickets, technician dispatches, and SLA escalation policies.",
    })

    # Event 2: 3rd Year Systems Defense
    projects.append({
        "id": "3Y-1S-E2-T1", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Systems Defense", "date": "11/14/2025", "room": "Room 303", "time": "9:00AM-9:30AM",
        "team_name": "Team BioShield", "title": "Contactless Facial Recognition Terminal", "adviser": "Jonathan Beltran",
        "chair": "Renato Villanueva", "panelist": "Florencia Dela Torre", "documenter": "Cecilia Magbanua",
        "members": ["Carlos Reyes", "Maria Santos", "Juan Dela Cruz", "Ana Mendoza"],
        "stack": "Django / Python", "domain": "Artificial Intelligence & ML",
        "prereq_course": "IT324 Artificial Intelligence & Data Mining", "career_track": "AI Computer Vision Engineer",
        "keywords": ["ai", "computer vision", "opencv", "recognition", "detection", "neural", "deep learning"],
        "frontend_tech": "Flutter Kiosk Touchless Interface", "backend_tech": "Python / InsightFace Deep CNN",
        "database_tech": "Milvus Vector Database & PostgreSQL",
        "module_1_name": "Sub-Second Cosine Similarity Face Matcher",
        "module_1_desc": "Executes 512-dimension vector similarity queries across 10,000 enrolled faces in under 150 ms.",
        "module_2_name": "Infrared Thermal Temperature Cross-Check",
        "module_2_desc": "Integrates I2C thermal sensors checking for elevated body temperatures during building entry.",
        "module_3_name": "Secure API Attendance Broadcaster",
        "module_3_desc": "Emits cryptographically signed HMAC payloads updating university administrative records instantaneously.",
        "abstract": "A high-speed contactless biometric terminal executing vector face recognition and thermal health screening.",
    })
    projects.append({
        "id": "3Y-1S-E2-T2", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Systems Defense", "date": "11/14/2025", "room": "Room 303", "time": "9:30AM-10:00AM",
        "team_name": "Team CloudHaven", "title": "Containerized Microservices Log Aggregator", "adviser": "Jonathan Beltran",
        "chair": "Renato Villanueva", "panelist": "Florencia Dela Torre", "documenter": "Cecilia Magbanua",
        "members": ["Jose Garcia", "Liza Torres", "Marco Villanueva", "Nina Flores"],
        "stack": "Cloud / AWS", "domain": "Enterprise & Cloud SaaS",
        "prereq_course": "IT311 Cloud Architecture & Enterprise Systems", "career_track": "DevOps / SRE Engineer",
        "keywords": ["cloud", "docker", "microservices", "kubernetes", "aws", "storage", "sync"],
        "frontend_tech": "Grafana Dashboards & React Admin", "backend_tech": "Go (Golang) Vector Log Daemon & Fluentbit",
        "database_tech": "Elasticsearch Cluster & AWS S3 Cold Storage",
        "module_1_name": "Distributed Standard Output Scraper",
        "module_1_desc": "Collects structured JSON logs across 50+ Docker containers without performance degradation.",
        "module_2_name": "Log Pattern Anomaly Detector",
        "module_2_desc": "Flags sudden surges in HTTP 500 error spikes using moving average outlier heuristics.",
        "module_3_name": "Cold Tier Compression Archiver",
        "module_3_desc": "Compresses historical audit logs into GZIP archives stored in AWS S3 Glacier storage tiers.",
        "abstract": "A containerized log aggregation pipeline ingesting distributed container streams and alerting DevOps engineers to service anomalies.",
    })
    projects.append({
        "id": "3Y-1S-E2-T3", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Systems Defense", "date": "11/14/2025", "room": "Room 303", "time": "10:00AM-10:30AM",
        "team_name": "Team DataMetrics", "title": "Student Retention & Attrition Risk Predictor", "adviser": "Jonathan Beltran",
        "chair": "Renato Villanueva", "panelist": "Florencia Dela Torre", "documenter": "Cecilia Magbanua",
        "members": ["Diego Ramos", "Patricia Cruz", "Ryan Bautista", "Sophia Aquino"],
        "stack": "Django / Python", "domain": "Data Analytics & BI",
        "prereq_course": "IT221 Data Analysis & Visualization", "career_track": "Data Scientist",
        "keywords": ["analytics", "dashboard", "visualization", "mining", "prediction", "forecasting", "reporting"],
        "frontend_tech": "React Data Explorer UI", "backend_tech": "Django / Python XGBoost Classifier",
        "database_tech": "PostgreSQL Analytics Schema",
        "module_1_name": "Multi-Variable Student Attrition Predictor",
        "module_1_desc": "Analyzes attendance, quiz scores, and LMS activity to flag students with high dropout likelihood.",
        "module_2_name": "Targeted Academic Intervention Recommender",
        "module_2_desc": "Suggests specific peer tutors or laboratory review sessions tailored to student weak subject modules.",
        "module_3_name": "Retention Longitudinal Trend Modeler",
        "module_3_desc": "Generates 5-year retention projections assisting academic deans in program accreditation audits.",
        "abstract": "A machine learning analytics platform forecasting student dropout risks early and recommending personalized academic interventions.",
    })

    # Event 3: 3rd Year Tech Summit
    projects.append({
        "id": "3Y-1S-E3-T1", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Tech Summit", "date": "12/12/2025", "room": "Multimedia Lab", "time": "9:00AM-9:30AM",
        "team_name": "Team CyberBastion", "title": "Automated SSL/TLS Security Audit Pipeline", "adviser": "Eduardo Padilla",
        "chair": "Maricel Suarez", "panelist": "Arsenio Macasaet", "documenter": "Cecilia Magbanua",
        "members": ["Carlos Reyes", "Maria Santos", "Juan Dela Cruz", "Ana Mendoza"],
        "stack": "Django / Python", "domain": "Cybersecurity & Network Systems",
        "prereq_course": "IT313 Information Assurance & Security", "career_track": "Security Assurance Engineer",
        "keywords": ["security", "cryptography", "firewall", "encryption", "audit", "vulnerability", "auth"],
        "frontend_tech": "Vue.js 3 / Tailwind Admin", "backend_tech": "Python / OpenSSL Verification Worker",
        "database_tech": "PostgreSQL Audit Store",
        "module_1_name": "Certificate Chain Validity Verifier",
        "module_1_desc": "Inspects SSL root certificate expiration, OCSP stapling, and Certificate Transparency (CT) logs.",
        "module_2_name": "Deprecated Cipher Suite Alerting Daemon",
        "module_2_desc": "Identifies web servers negotiating outdated TLS 1.0/1.1 or RC4 ciphers violating institutional mandates.",
        "module_3_name": "Automated Let's Encrypt ACME Renewer",
        "module_3_desc": "Coordinates automated DNS-01 certificate renewals across internal development subdomains.",
        "abstract": "An automated security audit daemon continuously inspecting university public domain certificates and flagging deprecated ciphers.",
    })
    projects.append({
        "id": "3Y-1S-E3-T2", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Tech Summit", "date": "12/12/2025", "room": "Multimedia Lab", "time": "9:30AM-10:00AM",
        "team_name": "Team AgriDrone", "title": "Autonomous Crop Health Drone Analyzer", "adviser": "Eduardo Padilla",
        "chair": "Maricel Suarez", "panelist": "Arsenio Macasaet", "documenter": "Cecilia Magbanua",
        "members": ["Jose Garcia", "Liza Torres", "Marco Villanueva", "Nina Flores"],
        "stack": "IoT / Embedded", "domain": "IoT & Smart Hardware",
        "prereq_course": "IT315 Embedded Systems & IoT", "career_track": "IoT Drone Systems Specialist",
        "keywords": ["iot", "sensor", "robotics", "microcontroller", "embedded", "automation", "ai"],
        "frontend_tech": "Mission Planner / WebGL Orthomosaic View", "backend_tech": "Python / OpenCV Multispectral Indexer",
        "database_tech": "PostGIS GeoTIFF Tile Storage",
        "module_1_name": "NDVI Multispectral Imagery Indexer",
        "module_1_desc": "Calculates Normalized Difference Vegetation Index (NDVI) values to detect crop chlorosis and moisture stress.",
        "module_2_name": "Autonomous Drone Grid Mission Controller",
        "module_2_desc": "Navigates precision lawnmower flight grids while geotagging high-resolution aerial imagery.",
        "module_3_name": "Agricultural Fertilizer Prescription Mapper",
        "module_3_desc": "Generates variable-rate nitrogen application maps for local agricultural research fields.",
        "abstract": "An aerial IoT drone imaging platform computing NDVI vegetation stress indices to optimize agricultural crop yields.",
    })
    projects.append({
        "id": "3Y-1S-E3-T3", "year_level": "3rd Year", "semester": "1st Semester", "track": "PIT",
        "event_or_stage": "3rd Year Tech Summit", "date": "12/12/2025", "room": "Multimedia Lab", "time": "10:00AM-10:30AM",
        "team_name": "Team EduConnect", "title": "Collaborative Peer Code Review Platform", "adviser": "Eduardo Padilla",
        "chair": "Maricel Suarez", "panelist": "Arsenio Macasaet", "documenter": "Cecilia Magbanua",
        "members": ["Diego Ramos", "Patricia Cruz", "Ryan Bautista", "Sophia Aquino"],
        "stack": "React / Node.js", "domain": "Web Applications & Platforms",
        "prereq_course": "IT212 Web Systems & Technologies", "career_track": "Collaborative Tools Software Dev",
        "keywords": ["react", "node", "javascript", "web", "peer", "builder", "quiz"],
        "frontend_tech": "React Code Diff Viewer / Monaco", "backend_tech": "Node.js Git Protocol Parser",
        "database_tech": "PostgreSQL Codebase Index",
        "module_1_name": "In-line Syntax Commenting System",
        "module_1_desc": "Allows students to leave line-by-line constructive feedback on classmates' programming submissions.",
        "module_2_name": "Automated Linting & Formatting Checker",
        "module_2_desc": "Runs ESLint and PEP 8 linters to enforce clean software engineering style conventions.",
        "module_3_name": "Peer Review Constructiveness Scorer",
        "module_3_desc": "Evaluates peer review comments using NLP sentiment to reward thorough and helpful code critiques.",
        "abstract": "A collaborative peer code review platform teaching industrial pull request workflows and automated style linting.",
    })

    # 3RD YEAR - 2ND SEMESTER (CAPSTONE TRACK - 3 STAGES, IDENTICAL TEAMS/PROJECTS)
    capstone_3rd_teams = [
        {
            "team_name": "Team Site Avengers",
            "title": "DefenSYS: Capstone & PIT Defense Management System",
            "adviser": "Ricardo Fontanilla",
            "members": ["Carlos Reyes", "Maria Santos", "Juan Dela Cruz", "Ana Mendoza"],
            "stack": "Django / Python",
            "domain": "Enterprise & Cloud SaaS",
            "prereq_course": "IT311 Cloud Architecture & Enterprise Systems",
            "career_track": "Enterprise Software Engineer",
            "keywords": ["django", "python", "portal", "management system", "cloud", "saas", "dashboard"],
            "frontend_tech": "Flutter Web & Responsive Mobile Client",
            "backend_tech": "Django 5.x / Django REST Framework / Celery",
            "database_tech": "PostgreSQL 16 Enterprise Relational DB",
            "module_1_name": "Role-Governed Multi-Tier Defense Scheduler",
            "module_1_desc": "Automates defense matrix allocation preventing panelist time overlaps and venue collisions.",
            "module_2_name": "Consensus Rubric Scoring & CPI Calculation",
            "module_2_desc": "Captures panel, adviser, and peer rubric evaluations calculating live Competency Proficiency Indices.",
            "module_3_name": "Automated Digital Deliverable Vault",
            "module_3_desc": "Enforces pre/post-defense manuscript and repository file upload gates with checksum validation.",
            "abstract": "An institutional defense operations and decision support platform managing academic schedules, rubric grading consensus, and curriculum analytics.",
        },
        {
            "team_name": "Team VisionPulse",
            "title": "AI-Powered Attendance System & Exam Proctoring",
            "adviser": "Analiza Corpuz",
            "members": ["Jose Garcia", "Liza Torres", "Marco Villanueva", "Nina Flores"],
            "stack": "Django / Python",
            "domain": "Artificial Intelligence & ML",
            "prereq_course": "IT324 Artificial Intelligence & Data Mining",
            "career_track": "AI Computer Vision Engineer",
            "keywords": ["ai", "machine learning", "computer vision", "opencv", "yolo", "recognition", "detection"],
            "frontend_tech": "React WebRTC Exam Proctoring HUD",
            "backend_tech": "Python / PyTorch / YOLOv8 Multi-Stream Worker",
            "database_tech": "PostgreSQL with Vector Embeddings",
            "module_1_name": "Multi-Camera Gaze & Head Pose Tracker",
            "module_1_desc": "Detects student gaze deviation away from examination monitors using landmark regression.",
            "module_2_name": "Prohibited Electronic Device Detector",
            "module_2_desc": "Applies YOLOv8 object detection to flag mobile phones, smartwatches, and auxiliary notes.",
            "module_3_name": "Automated Incident Timestamp Flagging",
            "module_3_desc": "Generates forensic video clips of suspicious examination events for proctor review.",
            "abstract": "An automated AI video proctoring system detecting unauthorized electronic devices and anomalous student gaze behaviors.",
        },
        {
            "team_name": "Team GeoRescue",
            "title": "Disaster Hazard GIS Evacuation Portal",
            "adviser": "Eduardo Padilla",
            "members": ["Diego Ramos", "Patricia Cruz", "Ryan Bautista", "Sophia Aquino"],
            "stack": "GIS / Mapping",
            "domain": "GIS & Smart Community",
            "prereq_course": "IT322 Geographic Information Systems",
            "career_track": "GIS Solutions Architect",
            "keywords": ["gis", "map", "mapping", "geo", "spatial", "disaster", "evacuation", "barangay"],
            "frontend_tech": "React / Mapbox Vector Tiles",
            "backend_tech": "Python GeoDjango / PostGIS",
            "database_tech": "PostGIS Enterprise GeoSpatial DB",
            "module_1_name": "Multi-Hazard Overlay Composite Engine",
            "module_1_desc": "Overlays seismic fault lines, storm surge hazard zones, and active flood areas onto unified maps.",
            "module_2_name": "Evacuation Shelter Resource Allocator",
            "module_2_desc": "Matches displaced families to available emergency evacuation shelters with sufficient rations.",
            "module_3_name": "Offline Resilient SMS Emergency Dispatch",
            "module_3_desc": "Transmits emergency geographic waypoints over cellular SMS mesh networks during power outages.",
            "abstract": "A municipal geographic disaster response portal managing multi-hazard mapping overlays, shelter capacities, and emergency route dispatch.",
        },
    ]

    for stage_name, s_date, s_room, s_panelist in [
        ("Concept Proposal", "2/20/2026", "Room 301", "Jonathan Beltran"),
        ("Project Proposal", "3/27/2026", "Room 302", "Renato Villanueva"),
        ("Colloquium", "5/15/2026", "Smart Room", "Florencia Dela Torre"),
    ]:
        for idx, t in enumerate(capstone_3rd_teams):
            projects.append({
                "id": f"3Y-2S-CAP-{stage_name[:4]}-T{idx+1}",
                "year_level": "3rd Year",
                "semester": "2nd Semester",
                "track": "Capstone",
                "event_or_stage": stage_name,
                "date": s_date,
                "room": s_room,
                "time": f"{9 + idx * 0.5:.2f}".replace(".00", ":00AM").replace(".50", ":30AM") + "-" + f"{9.5 + idx * 0.5:.2f}".replace(".00", ":00AM").replace(".50", ":30AM"),
                "team_name": t["team_name"],
                "title": t["title"],
                "adviser": t["adviser"],
                "chair": "Maricel Suarez",
                "panelist": s_panelist,
                "documenter": "Cecilia Magbanua",
                "members": t["members"],
                "stack": t["stack"],
                "domain": t["domain"],
                "prereq_course": t["prereq_course"],
                "career_track": t["career_track"],
                "keywords": t["keywords"],
                "frontend_tech": t["frontend_tech"],
                "backend_tech": t["backend_tech"],
                "database_tech": t["database_tech"],
                "module_1_name": t["module_1_name"],
                "module_1_desc": t["module_1_desc"],
                "module_2_name": t["module_2_name"],
                "module_2_desc": t["module_2_desc"],
                "module_3_name": t["module_3_name"],
                "module_3_desc": t["module_3_desc"],
                "abstract": t["abstract"],
            })

    # 4TH YEAR - CAPSTONE TRACK (1ST & 2ND SEMESTER - 3 STAGES, IDENTICAL TEAMS/PROJECTS)
    capstone_4th_teams = [
        {
            "team_name": "Team SkyLedger",
            "title": "Alumni Career Tracker",
            "adviser": "Ricardo Fontanilla",
            "members": ["Marcus Villar", "Patricia Ong", "Ethan Salazar", "Zoe Castillo"],
            "stack": "React / Node.js",
            "domain": "Enterprise & Cloud SaaS",
            "prereq_course": "IT311 Cloud Architecture & Enterprise Systems",
            "career_track": "Full-Stack Cloud Developer",
            "keywords": ["saas", "portal", "cloud", "aws", "docker", "react", "node", "analytics", "dashboard"],
            "frontend_tech": "React 18 / TypeScript / Tailwind CSS",
            "backend_tech": "Node.js / Express / REST APIs / Docker",
            "database_tech": "PostgreSQL 16 Relational DB / AWS RDS",
            "module_1_name": "Alumni Profile & Employment History Management",
            "module_1_desc": "Maintains post-graduation employer history, job titles, industries, and salary progression.",
            "module_2_name": "Career Path Explorer & Mentorship Gateway",
            "module_2_desc": "Connects undergraduate seniors with verified alumni working in target technical specializations.",
            "module_3_name": "Institutional Accreditation Analytics Generator",
            "module_3_desc": "Generates CHED and PACUCOA-compliant employment alignment reports automatically.",
            "abstract": "A cloud-native web platform tracing collegiate graduate career progressions to optimize curriculum alignment and institutional accreditation.",
        },
        {
            "team_name": "Team BioPulse",
            "title": "AI-Powered Patient Vital Triage & Disease Predictor",
            "adviser": "Jonathan Beltran",
            "members": ["Ryan Torres", "Nina Villanueva", "Diego Garcia", "Patricia Ramos"],
            "stack": "Django / Python",
            "domain": "Artificial Intelligence & ML",
            "prereq_course": "IT324 Artificial Intelligence & Data Mining",
            "career_track": "Healthcare AI Systems Engineer",
            "keywords": ["ai", "machine learning", "deep learning", "neural", "prediction", "classifier", "django", "python"],
            "frontend_tech": "Flutter Mobile & Web Clinical Tablet UI",
            "backend_tech": "Django REST Framework / PyTorch Inference Server",
            "database_tech": "PostgreSQL with HIPAA Patient Vault Encryption",
            "module_1_name": "Emergency Room Triage Acuity Classifier",
            "module_1_desc": "Calculates Emergency Severity Index (ESI) scores from real-time vital signs in seconds.",
            "module_2_name": "Cardiovascular Risk Prediction Neural Network",
            "module_2_desc": "Evaluates blood pressure, ECG waveforms, and oxygen saturation to alert nurses to impending shock.",
            "module_3_name": "Hospital Bed Allocation Telemetry",
            "module_3_desc": "Coordinates ICU and general ward admissions to prevent emergency room boarding bottlenecks.",
            "abstract": "A healthcare clinical intelligence application classifying patient vital signs and predicting medical acuity levels in emergency wards.",
        },
        {
            "team_name": "Team SafeCity",
            "title": "Smart City IoT Infrastructure & Asset Sentinel",
            "adviser": "Renato Villanueva",
            "members": ["Carlos Bautista", "Sophia Santos", "Miguel Cruz", "Isabella Alcantara"],
            "stack": "IoT / Embedded",
            "domain": "IoT & Smart Hardware",
            "prereq_course": "IT315 Embedded Systems & IoT",
            "career_track": "IoT Infrastructure Engineer",
            "keywords": ["iot", "arduino", "esp32", "sensor", "embedded", "smart home", "automation", "hardware"],
            "frontend_tech": "React GIS Municipal Operations Center HUD",
            "backend_tech": "Go (Golang) High-Throughput MQTT Ingestion Engine",
            "database_tech": "TimescaleDB Time-Series Engine / PostGIS",
            "module_1_name": "Smart Streetlight Mesh Controller",
            "module_1_desc": "Controls adaptive LED brightness based on pedestrian traffic density, slashing municipal electricity bills by 35%.",
            "module_2_name": "Structural Health Vibration Telemetry Node",
            "module_2_desc": "Monitors seismic and bridge resonant frequencies using MEMS accelerometers to detect structural fatigue.",
            "module_3_name": "Urban Asset Preventative Maintenance Scheduler",
            "module_3_desc": "Dispatches municipal repair crews automatically upon detecting streetlight outages or water main failures.",
            "abstract": "An enterprise municipal IoT platform automating urban streetlight illumination schedules and monitoring critical infrastructure structural health.",
        },
    ]

    for sem_label, s_prefix, s_dates in [
        ("1st Semester", "1S", [("Concept Proposal", "9/18/2025", "Room 301", "Jonathan Beltran"), ("Project Proposal", "10/24/2025", "Room 301", "Analiza Corpuz"), ("Colloquium", "11/21/2025", "Smart Room", "Renato Villanueva")]),
        ("2nd Semester", "2S", [("Concept Proposal", "2/20/2026", "Room 301", "Maricel Suarez"), ("Project Proposal", "3/27/2026", "Room 301", "Florencia Dela Torre"), ("Colloquium", "5/15/2026", "Smart Room", "Arsenio Macasaet")]),
    ]:
        for stage_name, s_date, s_room, s_panelist in s_dates:
            for idx, t in enumerate(capstone_4th_teams):
                projects.append({
                    "id": f"4Y-{s_prefix}-CAP-{stage_name[:4]}-T{idx+1}",
                    "year_level": "4th Year",
                    "semester": sem_label,
                    "track": "Capstone",
                    "event_or_stage": stage_name,
                    "date": s_date,
                    "room": s_room,
                    "time": f"{9 + idx * 0.5:.2f}".replace(".00", ":00AM").replace(".50", ":30AM") + "-" + f"{9.5 + idx * 0.5:.2f}".replace(".00", ":00AM").replace(".50", ":30AM"),
                    "team_name": t["team_name"],
                    "title": t["title"],
                    "adviser": t["adviser"],
                    "chair": "Maricel Suarez" if s_panelist != "Maricel Suarez" else "Jonathan Beltran",
                    "panelist": s_panelist,
                    "documenter": "Cecilia Magbanua",
                    "members": t["members"],
                    "stack": t["stack"],
                    "domain": t["domain"],
                    "prereq_course": t["prereq_course"],
                    "career_track": t["career_track"],
                    "keywords": t["keywords"],
                    "frontend_tech": t["frontend_tech"],
                    "backend_tech": t["backend_tech"],
                    "database_tech": t["database_tech"],
                    "module_1_name": t["module_1_name"],
                    "module_1_desc": t["module_1_desc"],
                    "module_2_name": t["module_2_name"],
                    "module_2_desc": t["module_2_desc"],
                    "module_3_name": t["module_3_name"],
                    "module_3_desc": t["module_3_desc"],
                    "abstract": t["abstract"],
                })

    return projects


# ==============================================================================
# 5. CSV EMITTERS
# ==============================================================================

def write_students_csv(filepath: str, year_level: str, semester_label: str, subject_code: str, subject_title: str, section: str, instructor: str, students: List[Dict[str, Any]]):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, mode='w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["OFFICIAL LIST OF ENROLLED STUDENTS", "", "", "", "", "", "", "", "", ""])
        writer.writerow([f"2025-2026 {semester_label}", "", "", "", "", "", "", "", "", ""])
        writer.writerow(["", "", "", "", "", "", "", "", "", ""])
        writer.writerow(["Subject Code", subject_code, "", "", "", "", "", "", "", ""])
        writer.writerow(["Subject Title", subject_title, "", "", "", "", "", "", "", ""])
        writer.writerow(["Academic Units", "3", "Lab Units", "1", "", "", "", "", "", ""])
        writer.writerow(["Credit Units", "3", "Lab Hours", "3", "", "", "", "", "", ""])
        writer.writerow(["Mode", "Lecture and Laboratory", "", "", "", "", "", "", "", ""])
        writer.writerow(["Instructor", instructor, "", "", "", "", "", "", "", ""])
        writer.writerow(["Class Section", section, "", "", "", "", "", "", "", ""])
        writer.writerow(["Year Level", year_level, "", "", "", "", "", "", "", ""])
        writer.writerow(["Schedule(s)", "M 1:00 PM - 3:00 PM", "", "", "", "", "", "", "", ""])
        writer.writerow(["", "", "", "", "", "", "", "", "", ""])
        writer.writerow(["#", "Student Number", "Full Name", "Program", "Gender", "Level", "OR No.", "Validation Date", "Email", "Contact"])
        val_date = "7/28/2025 11:47" if "1st" in semester_label else "1/15/2026 10:30"
        yr_short = "1st Yr." if "1st" in year_level else ("2nd Yr." if "2nd" in year_level else ("3rd Yr." if "3rd" in year_level else "4th Yr."))
        for s in students:
            writer.writerow([
                s['num'],
                s['id'],
                f"{s['last']}, {s['first']}",
                "BSIT",
                s['gender'],
                yr_short,
                f"OR-{s['id']}",
                val_date,
                s['email'],
                s['contact']
            ])


def write_teams_csv(filepath: str, teams_list: List[Dict[str, Any]], is_capstone: bool = False):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, mode='w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        if is_capstone:
            writer.writerow(["Team Name", "Capstone Project", "Adviser", "Team Members"])
            for t in teams_list:
                writer.writerow([t['team_name'], t['title'], t['adviser'], t['members'][0]])
                for m in t['members'][1:]:
                    writer.writerow(["", "", "", m])
        else:
            writer.writerow(["Team Name", "PIT Project", "Team Members"])
            for t in teams_list:
                writer.writerow([t['team_name'], t['title'], t['members'][0]])
                for m in t['members'][1:]:
                    writer.writerow(["", "", m])


def write_schedule_csv(filepath: str, schedules_by_event: Dict[str, List[Dict[str, Any]]], is_capstone: bool = False):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, mode='w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        proj_col = "Capstone Project" if is_capstone else "Project"
        
        first_block = True
        for event_name, rows in schedules_by_event.items():
            if not rows:
                continue
            if not first_block:
                writer.writerow(["", "", "", "", "", "", "", ""])
                writer.writerow(["", "", "", "", "", "", "", ""])
            first_block = False
            
            sample_row = rows[0]
            writer.writerow([event_name, "", "", "", "", "", "", ""])
            writer.writerow([sample_row['date'], "", "", "", "", "", "", ""])
            writer.writerow([sample_row['room'], "", "", "", "", "", "", ""])
            writer.writerow(["Time", "Team Name", proj_col, "Adviser", "Team Members", "Chair", "Panel Member 1", "Documenter"])
            
            for r in rows:
                writer.writerow([
                    r['time'],
                    r['team_name'],
                    r['title'],
                    r['adviser'],
                    r['members'][0],
                    r['chair'],
                    r['panelist'],
                    r['documenter']
                ])
                for m in r['members'][1:]:
                    writer.writerow(["", "", "", "", m, "", "", ""])


# ==============================================================================
# 6. MAIN ORCHESTRATION PIPELINE
# ==============================================================================

def main():
    workspace_root = r"c:\Users\Admin\Desktop\DefenSYS"
    all_year_dir = os.path.join(workspace_root, "sample_file", "All Year all sem test")
    manuscripts_dir = os.path.join(workspace_root, "sample_file", "Project_Manuscripts")
    
    print("================================================================================")
    print("Starting DefenSYS Realistic Test Data & DSS Manuscript Generation Pipeline")
    print(f"Target Directory: {all_year_dir}")
    print(f"Manuscripts Directory: {manuscripts_dir}")
    print("================================================================================\n")

    projects = get_all_projects()
    print(f"Loaded {len(projects)} total project/stage configurations.")

    # 1. EMIT MASTER UNIQUE PROJECTS CATALOG CSV & JSON
    unique_catalog_path_csv = os.path.join(all_year_dir, "unique_projects_curriculum_catalog.csv")
    unique_catalog_path_json = os.path.join(all_year_dir, "unique_projects_curriculum_catalog.json")
    os.makedirs(all_year_dir, exist_ok=True)

    unique_projects_dict = {}
    for p in projects:
        key = (p['team_name'], p['title'])
        if key not in unique_projects_dict:
            unique_projects_dict[key] = p

    unique_projects_list = list(unique_projects_dict.values())
    print(f"Found {len(unique_projects_list)} distinct projects across all cohorts.")

    with open(unique_catalog_path_csv, mode='w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            "Project ID", "Team Name", "Project Title", "Year Level", "Semester", "Track",
            "Event / Stage", "Tech Stack", "Domain", "Prerequisite Course", "Career Track",
            "Adviser", "Keywords", "Abstract"
        ])
        for p in unique_projects_list:
            writer.writerow([
                p['id'],
                p['team_name'],
                p['title'],
                p['year_level'],
                p['semester'],
                p['track'],
                p['event_or_stage'],
                p['stack'],
                p['domain'],
                p['prereq_course'],
                p['career_track'],
                p['adviser'],
                ", ".join(p['keywords']),
                p['abstract']
            ])
    print(f"Saved: {unique_catalog_path_csv}")

    with open(unique_catalog_path_json, mode='w', encoding='utf-8') as f:
        json.dump(unique_projects_list, f, indent=2)
    print(f"Saved: {unique_catalog_path_json}")

    # 2. EMIT CSV FILES FOR EACH YEAR LEVEL AND SEMESTER
    def filter_projects(year, sem, track=None, event=None):
        res = [p for p in projects if p['year_level'] == year and p['semester'] == sem]
        if track:
            res = [p for p in res if p['track'] == track]
        if event:
            res = [p for p in res if p['event_or_stage'] == event]
        return res

    # 1st Year - 1st Sem
    dir_1y_1s = os.path.join(all_year_dir, "1st_Year", "1st_Sem")
    write_students_csv(
        os.path.join(dir_1y_1s, "students_import.csv"),
        "1st Year", "1st Semester", "IT111", "Introduction to Computing", "BSIT-1A", "Maricel Suarez", STUDENTS_1ST_YEAR
    )
    t_1y_1s = filter_projects("1st Year", "1st Semester", event="1st Year Concept Pitch")
    write_teams_csv(os.path.join(dir_1y_1s, "teams_import.csv"), t_1y_1s, is_capstone=False)
    sched_1y_1s = {
        "1st Year Concept Pitch": filter_projects("1st Year", "1st Semester", event="1st Year Concept Pitch"),
        "1st Year Prototype Defense": filter_projects("1st Year", "1st Semester", event="1st Year Prototype Defense"),
        "1st Year Tech Expo": filter_projects("1st Year", "1st Semester", event="1st Year Tech Expo"),
    }
    write_schedule_csv(os.path.join(dir_1y_1s, "defense_schedule_import.csv"), sched_1y_1s, is_capstone=False)
    write_schedule_csv(os.path.join(dir_1y_1s, "schedule_event1_pitch.csv"), {"1st Year Concept Pitch": sched_1y_1s["1st Year Concept Pitch"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_1y_1s, "schedule_event2_prototype.csv"), {"1st Year Prototype Defense": sched_1y_1s["1st Year Prototype Defense"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_1y_1s, "schedule_event3_expo.csv"), {"1st Year Tech Expo": sched_1y_1s["1st Year Tech Expo"]}, is_capstone=False)

    # 1st Year - 2nd Sem
    dir_1y_2s = os.path.join(all_year_dir, "1st_Year", "2nd_Sem")
    write_students_csv(
        os.path.join(dir_1y_2s, "students_import.csv"),
        "1st Year", "2nd Semester", "IT121", "Computer Programming 1", "BSIT-1A", "Ricardo Fontanilla", STUDENTS_1ST_YEAR
    )
    t_1y_2s = filter_projects("1st Year", "2nd Semester", event="1st Year System Design Pitch")
    write_teams_csv(os.path.join(dir_1y_2s, "teams_import.csv"), t_1y_2s, is_capstone=False)
    sched_1y_2s = {
        "1st Year System Design Pitch": filter_projects("1st Year", "2nd Semester", event="1st Year System Design Pitch"),
        "1st Year Midterm Progress Defense": filter_projects("1st Year", "2nd Semester", event="1st Year Midterm Progress Defense"),
        "1st Year Year-End Showcase": filter_projects("1st Year", "2nd Semester", event="1st Year Year-End Showcase"),
    }
    write_schedule_csv(os.path.join(dir_1y_2s, "defense_schedule_import.csv"), sched_1y_2s, is_capstone=False)
    write_schedule_csv(os.path.join(dir_1y_2s, "schedule_event1_pitch.csv"), {"1st Year System Design Pitch": sched_1y_2s["1st Year System Design Pitch"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_1y_2s, "schedule_event2_defense.csv"), {"1st Year Midterm Progress Defense": sched_1y_2s["1st Year Midterm Progress Defense"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_1y_2s, "schedule_event3_showcase.csv"), {"1st Year Year-End Showcase": sched_1y_2s["1st Year Year-End Showcase"]}, is_capstone=False)

    # 2nd Year - 1st Sem
    dir_2y_1s = os.path.join(all_year_dir, "2nd_Year", "1st_Sem")
    write_students_csv(
        os.path.join(dir_2y_1s, "students_import.csv"),
        "2nd Year", "1st Semester", "IT211", "Data Structures & Algorithms", "BSIT-2A", "Jonathan Beltran", STUDENTS_2ND_YEAR
    )
    t_2y_1s = filter_projects("2nd Year", "1st Semester", event="2nd Year Architecture Pitch")
    write_teams_csv(os.path.join(dir_2y_1s, "teams_import.csv"), t_2y_1s, is_capstone=False)
    sched_2y_1s = {
        "2nd Year Architecture Pitch": filter_projects("2nd Year", "1st Semester", event="2nd Year Architecture Pitch"),
        "2nd Year Milestone Review": filter_projects("2nd Year", "1st Semester", event="2nd Year Milestone Review"),
        "2nd Year Innovation Expo": filter_projects("2nd Year", "1st Semester", event="2nd Year Innovation Expo"),
    }
    write_schedule_csv(os.path.join(dir_2y_1s, "defense_schedule_import.csv"), sched_2y_1s, is_capstone=False)
    write_schedule_csv(os.path.join(dir_2y_1s, "schedule_event1_architecture.csv"), {"2nd Year Architecture Pitch": sched_2y_1s["2nd Year Architecture Pitch"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_2y_1s, "schedule_event2_milestone.csv"), {"2nd Year Milestone Review": sched_2y_1s["2nd Year Milestone Review"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_2y_1s, "schedule_event3_expo.csv"), {"2nd Year Innovation Expo": sched_2y_1s["2nd Year Innovation Expo"]}, is_capstone=False)

    # 2nd Year - 2nd Sem
    dir_2y_2s = os.path.join(all_year_dir, "2nd_Year", "2nd_Sem")
    write_students_csv(
        os.path.join(dir_2y_2s, "students_import.csv"),
        "2nd Year", "2nd Semester", "IT221", "Data Analysis & Visualization", "BSIT-2A", "Renato Villanueva", STUDENTS_2ND_YEAR
    )
    t_2y_2s = filter_projects("2nd Year", "2nd Semester", event="2nd Year System Pitch")
    write_teams_csv(os.path.join(dir_2y_2s, "teams_import.csv"), t_2y_2s, is_capstone=False)
    sched_2y_2s = {
        "2nd Year System Pitch": filter_projects("2nd Year", "2nd Semester", event="2nd Year System Pitch"),
        "2nd Year Midterm Defense": filter_projects("2nd Year", "2nd Semester", event="2nd Year Midterm Defense"),
        "2nd Year Project Showcase": filter_projects("2nd Year", "2nd Semester", event="2nd Year Project Showcase"),
    }
    write_schedule_csv(os.path.join(dir_2y_2s, "defense_schedule_import.csv"), sched_2y_2s, is_capstone=False)
    write_schedule_csv(os.path.join(dir_2y_2s, "schedule_event1_pitch.csv"), {"2nd Year System Pitch": sched_2y_2s["2nd Year System Pitch"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_2y_2s, "schedule_event2_defense.csv"), {"2nd Year Midterm Defense": sched_2y_2s["2nd Year Midterm Defense"]}, is_capstone=False)
    write_schedule_csv(os.path.join(dir_2y_2s, "schedule_event3_showcase.csv"), {"2nd Year Project Showcase": sched_2y_2s["2nd Year Project Showcase"]}, is_capstone=False)

    # 3rd Year - 1st Sem PIT
    dir_3y_pit = os.path.join(all_year_dir, "3rd_Year", "1st_Sem_PIT")
    dir_3y_pit_legacy = os.path.join(all_year_dir, "3rd_Year", "PIT")
    for target_d in [dir_3y_pit, dir_3y_pit_legacy]:
        write_students_csv(
            os.path.join(target_d, "students_import.csv"),
            "3rd Year", "1st Semester", "IT311", "Cloud Architecture & Enterprise Systems", "BSIT-3A", "Ricardo Fontanilla", STUDENTS_3RD_YEAR
        )
        t_3y_pit = filter_projects("3rd Year", "1st Semester", event="3rd Year Capstone Readiness Pitch")
        write_teams_csv(os.path.join(target_d, "teams_import.csv"), t_3y_pit, is_capstone=False)
        sched_3y_pit = {
            "3rd Year Capstone Readiness Pitch": filter_projects("3rd Year", "1st Semester", event="3rd Year Capstone Readiness Pitch"),
            "3rd Year Systems Defense": filter_projects("3rd Year", "1st Semester", event="3rd Year Systems Defense"),
            "3rd Year Tech Summit": filter_projects("3rd Year", "1st Semester", event="3rd Year Tech Summit"),
        }
        write_schedule_csv(os.path.join(target_d, "defense_schedule_import.csv"), sched_3y_pit, is_capstone=False)
        write_schedule_csv(os.path.join(target_d, "schedule_event1_readiness_pitch.csv"), {"3rd Year Capstone Readiness Pitch": sched_3y_pit["3rd Year Capstone Readiness Pitch"]}, is_capstone=False)
        write_schedule_csv(os.path.join(target_d, "schedule_event2_systems_defense.csv"), {"3rd Year Systems Defense": sched_3y_pit["3rd Year Systems Defense"]}, is_capstone=False)
        write_schedule_csv(os.path.join(target_d, "schedule_event3_tech_summit.csv"), {"3rd Year Tech Summit": sched_3y_pit["3rd Year Tech Summit"]}, is_capstone=False)

    # 3rd Year - 2nd Sem Capstone
    dir_3y_cap = os.path.join(all_year_dir, "3rd_Year", "2nd_Sem_Capstone")
    dir_3y_cap_legacy = os.path.join(all_year_dir, "3rd_Year", "Capstone")
    for target_d in [dir_3y_cap, dir_3y_cap_legacy]:
        write_students_csv(
            os.path.join(target_d, "students_import.csv"),
            "3rd Year", "2nd Semester", "CAP301", "Capstone Project 1", "BSIT-3A", "Maricel Suarez", STUDENTS_3RD_YEAR
        )
        cap_teams_3y = filter_projects("3rd Year", "2nd Semester", event="Concept Proposal")
        with open(os.path.join(target_d, "capstone_teams_import.csv"), mode='w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(["team_name", "project_title", "year_level", "member_ids", "leader_id", "adviser_name"])
            writer.writerow(["", "", "", "", "", ""])
            for t in cap_teams_3y:
                writer.writerow([
                    t['team_name'],
                    t['title'],
                    "3rd Year",
                    "|".join(t['members']),
                    t['members'][0],
                    t['adviser']
                ])
        # Also write standard teams_import.csv for alternative importers
        write_teams_csv(os.path.join(target_d, "teams_import.csv"), cap_teams_3y, is_capstone=True)
        sched_3y_cap = {
            "Concept Proposal": filter_projects("3rd Year", "2nd Semester", event="Concept Proposal"),
            "Project Proposal": filter_projects("3rd Year", "2nd Semester", event="Project Proposal"),
            "Colloquium": filter_projects("3rd Year", "2nd Semester", event="Colloquium"),
        }
        write_schedule_csv(os.path.join(target_d, "defense_schedule_import.csv"), sched_3y_cap, is_capstone=True)
        write_schedule_csv(os.path.join(target_d, "schedule_stage1_concept_proposal.csv"), {"Concept Proposal": sched_3y_cap["Concept Proposal"]}, is_capstone=True)
        write_schedule_csv(os.path.join(target_d, "schedule_stage2_project_proposal.csv"), {"Project Proposal": sched_3y_cap["Project Proposal"]}, is_capstone=True)
        write_schedule_csv(os.path.join(target_d, "schedule_stage3_colloquium.csv"), {"Colloquium": sched_3y_cap["Colloquium"]}, is_capstone=True)

    # 4th Year - Capstone
    dir_4y = os.path.join(all_year_dir, "4th_Year_Capstone")
    dir_4y_1s = os.path.join(dir_4y, "1st_Sem")
    dir_4y_2s = os.path.join(dir_4y, "2nd_Sem")
    for s_label, target_d in [("1st Semester", dir_4y_1s), ("2nd Semester", dir_4y_2s), ("1st Semester", dir_4y)]:
        write_students_csv(
            os.path.join(target_d, "students_import.csv"),
            "4th Year", s_label, "CAP401", "Capstone Project 2", "BSIT-4A", "Maricel Suarez", STUDENTS_4TH_YEAR
        )
        t_4y = filter_projects("4th Year", s_label, event="Concept Proposal")
        write_teams_csv(os.path.join(target_d, "teams_import.csv"), t_4y, is_capstone=True)
        sched_4y = {
            "Concept Proposal": filter_projects("4th Year", s_label, event="Concept Proposal"),
            "Project Proposal": filter_projects("4th Year", s_label, event="Project Proposal"),
            "Colloquium": filter_projects("4th Year", s_label, event="Colloquium"),
        }
        write_schedule_csv(os.path.join(target_d, "defense_schedule_import.csv"), sched_4y, is_capstone=True)
        if target_d == dir_4y:
            write_schedule_csv(os.path.join(target_d, "schedule_import.csv"), sched_4y, is_capstone=True)
        write_schedule_csv(os.path.join(target_d, "schedule_stage1_concept_proposal.csv"), {"Concept Proposal": sched_4y["Concept Proposal"]}, is_capstone=True)
        write_schedule_csv(os.path.join(target_d, "schedule_stage2_project_proposal.csv"), {"Project Proposal": sched_4y["Project Proposal"]}, is_capstone=True)
        write_schedule_csv(os.path.join(target_d, "schedule_stage3_colloquium.csv"), {"Colloquium": sched_4y["Colloquium"]}, is_capstone=True)

    print("All CSV templates, rosters, and schedules successfully emitted.")

    # 3. GENERATE ALL 5-PAGE REPORTLAB PDF MANUSCRIPTS
    print("\nGenerating 5-Page ReportLab PDF Manuscripts for each project...")

    def get_event_subfolder(event_or_stage: str, track: str) -> str:
        if track == "Capstone":
            stage_map = {
                "Concept Proposal": "Stage_1_Concept_Proposal",
                "Project Proposal": "Stage_2_Project_Proposal",
                "Colloquium": "Stage_3_Colloquium",
            }
            clean = re.sub(r'[^a-zA-Z0-9_-]', '', event_or_stage.replace(' ', '_'))[:40]
            return stage_map.get(event_or_stage, clean)
        else:
            pit_map = {
                "1st Year Concept Pitch": "Event_1_Concept_Pitch",
                "1st Year Prototype Defense": "Event_2_Prototype_Defense",
                "1st Year Tech Expo": "Event_3_Tech_Expo",
                "1st Year System Design Pitch": "Event_1_System_Design_Pitch",
                "1st Year Midterm Progress Defense": "Event_2_Midterm_Progress_Defense",
                "1st Year Year-End Showcase": "Event_3_Year_End_Showcase",
                "2nd Year Architecture Pitch": "Event_1_Architecture_Pitch",
                "2nd Year Milestone Review": "Event_2_Milestone_Review",
                "2nd Year Innovation Expo": "Event_3_Innovation_Expo",
                "2nd Year System Pitch": "Event_1_System_Pitch",
                "2nd Year Midterm Defense": "Event_2_Midterm_Defense",
                "2nd Year Project Showcase": "Event_3_Project_Showcase",
                "3rd Year Capstone Readiness Pitch": "Event_1_Capstone_Readiness_Pitch",
                "3rd Year Systems Defense": "Event_2_Systems_Defense",
                "3rd Year Tech Summit": "Event_3_Tech_Summit",
            }
            clean = re.sub(r'[^a-zA-Z0-9_-]', '', event_or_stage.replace(' ', '_'))[:40]
            return pit_map.get(event_or_stage, clean)

    for proj in unique_projects_list:
        yr = proj['year_level'].replace(" ", "_")
        sem = proj['semester'].replace(" ", "_")
        track = proj.get('track', 'PIT')
        evt = proj.get('event_or_stage', '')
        evt_sub = get_event_subfolder(evt, track)

        team_folder = re.sub(r'[^a-zA-Z0-9_-]', '', proj['team_name'].replace(' ', '_'))[:40]

        if track == 'Capstone' and '3rd' in yr:
            sub_folder = os.path.join(manuscripts_dir, "3rd_Year", "2nd_Sem_Capstone", "Stage_1_Concept_Proposal", team_folder, "Pre_Deliverables")
            sem_tag = "2nd_Sem"
        elif track == 'PIT' and '3rd' in yr:
            sub_folder = os.path.join(manuscripts_dir, "3rd_Year", "1st_Sem_PIT", evt_sub, team_folder, "Pre_Deliverables")
            sem_tag = "1st_Sem"
        elif '4th' in yr:
            sem_tag = "1st_Sem" if "1st" in sem else "2nd_Sem"
            sub_folder = os.path.join(manuscripts_dir, "4th_Year_Capstone", sem_tag, "Stage_1_Concept_Proposal", team_folder, "Pre_Deliverables")
        else:
            sem_tag = "1st_Sem" if "1st" in sem else "2nd_Sem"
            sub_folder = os.path.join(manuscripts_dir, yr, sem_tag, evt_sub, team_folder, "Pre_Deliverables")

        os.makedirs(sub_folder, exist_ok=True)
        clean_team = re.sub(r'[^a-zA-Z0-9]', '', proj['team_name'])
        clean_title = re.sub(r'[^a-zA-Z0-9]', '', proj['title'].replace(" ", "_"))[:35]
        filename = f"{yr}_{sem_tag}_{clean_team}_{clean_title}_Manuscript.pdf"
        target_pdf_path = os.path.join(sub_folder, filename)

        generate_manuscript_pdf(proj, target_pdf_path)
        print(f"  [PDF] Generated: {target_pdf_path}")

    print("\n================================================================================")
    print("ALL TEST DATA & PDF MANUSCRIPTS SUCCESSFULLY GENERATED!")
    print("================================================================================")


if __name__ == '__main__':
    main()
