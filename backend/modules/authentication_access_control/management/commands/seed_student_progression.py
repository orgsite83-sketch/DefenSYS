import os
from datetime import date, datetime
from io import BytesIO
from django.core.management.base import BaseCommand
from django.db import transaction
from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.utils import timezone

from academic_period_management.models import SchoolYear, Semester
from user_management.academic_records.models import StudentAcademicRecord
from student_teams.models import StudentTeam, TeamMembership, TeamStageProgress
from defense.stages.models import DefenseStage
from repository.deliverables.models import DeliverableSubmission
from repository.vault.models import VaultEntry
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.audit import audit_scope_metadata

User = get_user_model()


def generate_seeding_pdf(title, subtitle, abstract, keywords_list, tech_focus=None):
    """
    Programmatic PDF generator utilizing ReportLab.
    Creates structured PDFs loaded with keyword features for the system's Naive Bayes classifier.
    """
    try:
        from reportlab.lib.pagesizes import letter
        from reportlab.lib import colors
        from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    except ImportError:
        # Fallback if ReportLab is not installed
        return ContentFile(b"%PDF-1.4 mock content loaded with keywords: " + ", ".join(keywords_list).encode('utf-8'), name="document.pdf")

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=54,
        bottomMargin=54,
        leftMargin=54,
        rightMargin=54
    )
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontSize=16,
        textColor=colors.HexColor('#7F1D1D'),
        spaceAfter=15,
        alignment=1, # Center
        fontName='Helvetica-Bold',
    )
    
    body_style = ParagraphStyle(
        'DocBody',
        parent=styles['Normal'],
        fontSize=10,
        spaceAfter=10,
        fontName='Helvetica',
    )
    
    keyword_style = ParagraphStyle(
        'DocKeywords',
        parent=styles['Normal'],
        fontSize=9,
        spaceAfter=15,
        fontName='Helvetica-Oblique',
    )
    
    story = []
    
    story.append(Paragraph(title.upper(), title_style))
    story.append(Paragraph(f"<b>Submission Label:</b> {subtitle}", styles['Normal']))
    story.append(Spacer(1, 15))
    
    # Abstract Section
    story.append(Paragraph("<b>ABSTRACT</b>", styles['Heading2']))
    story.append(Spacer(1, 6))
    story.append(Paragraph(abstract, body_style))
    story.append(Spacer(1, 10))
    
    # Keywords
    keywords_str = ", ".join(keywords_list)
    story.append(Paragraph(f"<b>Keywords:</b> {keywords_str}", keyword_style))
    story.append(Spacer(1, 15))
    
    # Methodology Table
    story.append(Paragraph("<b>SYSTEM ARCHITECTURE SUMMARY</b>", styles['Heading3']))
    story.append(Spacer(1, 6))
    
    rows_map = {
        'ml': ['Machine Learning Classifier', 'Neural Network, CNN, TensorFlow, Keras', 'Uses deep learning model for classification and feature engineering.'],
        'web_front': ['Web Frontend Application', 'React, JavaScript, CSS, Tailwind', 'Constructs the UI for client interaction and responsive design.'],
        'web_back': ['Web Backend Server', 'Django, Python, REST APIs, ORM', 'Handles business logic, database transactions, and data structures.'],
        'db': ['Database Management', 'MySQL, PostgreSQL, query optimization', 'Persists student academic records and team progression histories.'],
        'iot': ['IoT Smart Controller', 'Arduino, Raspberry Pi, MQTT, Sensors', 'Connects embedded hardware to monitor ambient variables and automation.'],
        'desktop': ['Desktop GUI Interface', 'Tkinter, PyQt, Desktop Widgets, Windows Forms', 'Constructs local desktop application layout for user interactions.'],
        'network': ['Network Sockets Sync', 'TCP/IP Sockets, Networking, Socket Connections', 'Synchronizes data across local area network connections in real-time.'],
        'prog': ['Basic Logic Control', 'Variables, Loops, Conditions, Flowcharts', 'Specifies basic sequential execution and software control flow.']
    }
    
    selected_keys = []
    if tech_focus == 'web':
        selected_keys = ['web_front', 'web_back', 'db']
    elif tech_focus == 'iot':
        selected_keys = ['iot', 'db']
    elif tech_focus == 'ml':
        selected_keys = ['ml', 'web_back', 'db']
    elif tech_focus == 'desktop':
        selected_keys = ['desktop', 'db']
    elif tech_focus == 'network':
        selected_keys = ['network', 'db']
    elif tech_focus == 'prog':
        selected_keys = ['prog']
    else:
        selected_keys = ['ml', 'web_front', 'web_back', 'db', 'iot']
        
    table_data = [['Layer', 'Technology/Method', 'Key Terms Description']]
    for key in selected_keys:
        table_data.append(rows_map[key])
    
    method_table = Table(table_data, colWidths=[120, 150, 200])
    method_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#7F1D1D')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 9),
        ('FONTSIZE', (0, 1), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ]))
    story.append(method_table)
    
    doc.build(story)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return ContentFile(pdf_content, name=f"{title.lower().replace(' ', '_')}.pdf")


def log_historical_action(
    *,
    semester,
    category,
    action,
    target_type,
    target_id,
    actor,
    old_values=None,
    new_values=None,
    reason="",
    review_status=None,
):
    sy_label = semester.school_year.label if semester.school_year else "2026-2027"
    sem_label = semester.label
    
    log_date = timezone.now()
    try:
        start_year = int(sy_label.split("-")[0])
        if sem_label == Semester.FIRST:
            log_date = timezone.make_aware(datetime(start_year, 10, 15, 10, 0))
        elif sem_label == Semester.SECOND:
            log_date = timezone.make_aware(datetime(start_year + 1, 3, 15, 10, 0))
        else:
            log_date = timezone.make_aware(datetime(start_year + 1, 7, 15, 10, 0))
    except Exception:
        pass

    log = SystemAuditLog.objects.create(
        actor=actor,
        category=category,
        action=action,
        target_type=target_type,
        target_id=str(target_id),
        old_values=old_values or {},
        new_values=new_values or {},
        reason=reason,
        review_status=review_status or (SystemAuditLog.REVIEW_CAPTURED if reason else SystemAuditLog.REVIEW_REQUIRES_REASON),
        ip_address="127.0.0.1",
        user_agent="DjangoSeeder/1.0",
    )
    
    SystemAuditLog.objects.filter(pk=log.pk).update(created_at=log_date)
    return log


class Command(BaseCommand):
    help = 'Populates the database with consecutive academic progression of 4 students, PIT Vault entries, and Capstone deliverables'

    @transaction.atomic
    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING("Starting expanded student progression seeding..."))

        # 1. Setup Consecutive Academic Periods (7 Semesters across 4 School Years)
        self.stdout.write("Configuring consecutive semesters...")
        sy_23_24, _ = SchoolYear.objects.get_or_create(label="2023-2024")
        sy_24_25, _ = SchoolYear.objects.get_or_create(label="2024-2025")
        sy_25_26, _ = SchoolYear.objects.get_or_create(label="2025-2026")
        sy_26_27, _ = SchoolYear.objects.get_or_create(label="2026-2027")

        # 2023-2024
        sem1, _ = Semester.objects.get_or_create(
            school_year=sy_23_24,
            label=Semester.FIRST,
            defaults={'is_active': False}
        )
        sem2, _ = Semester.objects.get_or_create(
            school_year=sy_23_24,
            label=Semester.SECOND,
            defaults={'is_active': False}
        )
        # 2024-2025
        sem3, _ = Semester.objects.get_or_create(
            school_year=sy_24_25,
            label=Semester.FIRST,
            defaults={'is_active': False}
        )
        sem4, _ = Semester.objects.get_or_create(
            school_year=sy_24_25,
            label=Semester.SECOND,
            defaults={'is_active': False}
        )
        # 2025-2026
        sem5, _ = Semester.objects.get_or_create(
            school_year=sy_25_26,
            label=Semester.FIRST,
            defaults={'is_active': False}
        )
        sem6, _ = Semester.objects.get_or_create(
            school_year=sy_25_26,
            label=Semester.SECOND,
            defaults={'is_active': False, 'capstone_team_creation_enabled': True, 'capstone_program_phase': Semester.PHASE_CAPSTONE_1}
        )
        # 2026-2027 (Active)
        sem7, _ = Semester.objects.get_or_create(
            school_year=sy_26_27,
            label=Semester.FIRST,
            defaults={'is_active': True, 'capstone_team_creation_enabled': False, 'capstone_program_phase': Semester.PHASE_CAPSTONE_2}
        )

        # Deactivate all others, activate sem7
        Semester.objects.exclude(pk=sem7.pk).update(is_active=False)
        sem7.is_active = True
        sem7.save()

        # Log creating school years and semesters
        for sem in [sem1, sem2, sem3, sem4, sem5, sem6]:
            log_historical_action(
                semester=sem,
                category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
                action="academic_period.create",
                target_type="Semester",
                target_id=sem.id,
                actor=None,
                new_values={
                    "school_year": sem.school_year.label if sem.school_year else "",
                    "term": sem.label,
                    "is_active": sem.is_active,
                },
                reason="Configure historical academic period calendar."
            )
        
        # Log activating sem7
        log_historical_action(
            semester=sem7,
            category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
            action="academic_period.activate",
            target_type="Semester",
            target_id=sem7.id,
            actor=None,
            old_values={"active_semester_id": sem6.id, "active_semester": sem6.label},
            new_values={"active_semester_id": sem7.id, "active_semester": sem7.label, "is_active": True},
            reason="Activate current semester."
        )

        # 2. Setup Faculty Users
        self.stdout.write("Configuring faculty roles...")
        faculty_pwd = os.environ.get('DEFENSYS_DEV_STUDENT_PASSWORD', 'student123')
        
        adviser, _ = User.objects.get_or_create(
            username='faculty.adviser',
            defaults={
                'email': 'adviser@ustp.edu.ph',
                'first_name': 'Ada',
                'last_name': 'Lovelace',
                'role': 'faculty',
                'is_adviser': True,
                'is_active': True,
            }
        )
        adviser.set_password(faculty_pwd)
        adviser.is_adviser = True
        adviser.save()

        pit_lead, _ = User.objects.get_or_create(
            username='faculty.pit',
            defaults={
                'email': 'pit@ustp.edu.ph',
                'first_name': 'Grace',
                'last_name': 'Hopper',
                'role': 'faculty',
                'is_pit_lead': True,
                'pit_lead_year': '3rd Year',
                'is_active': True,
            }
        )
        pit_lead.set_password(faculty_pwd)
        pit_lead.is_pit_lead = True
        pit_lead.save()

        # 3. Setup Cohort Student Users
        self.stdout.write("Configuring student cohort accounts...")
        students = []
        student_data = [
            ('cohort.student1', 'Juan', 'Dela Cruz'),
            ('cohort.student2', 'Maria', 'Santos'),
            ('cohort.student3', 'Mark', 'Ramos'),
            ('cohort.student4', 'Sarah', 'Lim'),
        ]

        for username, first, last in student_data:
            student, _ = User.objects.get_or_create(
                username=username,
                defaults={
                    'email': f'{username}@ustp.edu.ph',
                    'first_name': first,
                    'last_name': last,
                    'role': 'student',
                    'is_active': True,
                }
            )
            student.set_password(faculty_pwd)
            student.save()
            students.append(student)

        # Clear old seeder team & vault records to prevent conflicts and ensure clean rerun
        self.stdout.write("Clearing previous records...")
        StudentTeam.objects.filter(name__in=[
            "ByteSized PIT 1", "ByteSized PIT 2",
            "LogicCraft PIT 1", "LogicCraft PIT 2",
            "DataQuest PIT", "Team Apex Capstone"
        ]).delete()
        StudentAcademicRecord.objects.filter(student__in=students).delete()
        VaultEntry.objects.filter(team_name__in=[
            "ByteSized PIT 1", "ByteSized PIT 2",
            "LogicCraft PIT 1", "LogicCraft PIT 2",
            "DataQuest PIT"
        ]).delete()
        
        # Clear old seeder-related logs
        self.stdout.write("Clearing previous audit log records...")
        SystemAuditLog.objects.filter(actor__username__in=[
            'faculty.adviser', 'faculty.pit', 'cohort.student1',
            'cohort.student2', 'cohort.student3', 'cohort.student4'
        ]).delete()
        SystemAuditLog.objects.filter(user_agent='DjangoSeeder/1.0').delete()

        # 4. Configure Chronological Academic Records (Cohort stays in same Year Level for 1st & 2nd semesters of the AY)
        self.stdout.write("Creating student academic records chain...")
        records = {}
        for s in students:
            # 2023-2024 (1st Year)
            records[(s, sem1)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem1, year_level="1st Year"
            )
            records[(s, sem2)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem2, year_level="1st Year", rolled_from=records[(s, sem1)]
            )
            # 2024-2025 (2nd Year)
            records[(s, sem3)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem3, year_level="2nd Year", rolled_from=records[(s, sem2)]
            )
            records[(s, sem4)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem4, year_level="2nd Year", rolled_from=records[(s, sem3)]
            )
            # 2025-2026 (3rd Year)
            records[(s, sem5)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem5, year_level="3rd Year", rolled_from=records[(s, sem4)]
            )
            records[(s, sem6)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem6, year_level="3rd Year", rolled_from=records[(s, sem5)]
            )
            # 2026-2027 (4th Year)
            records[(s, sem7)] = StudentAcademicRecord.objects.create(
                student=s, semester=sem7, year_level="4th Year", rolled_from=records[(s, sem6)]
            )

        # 5. Populate Chronological PIT Teams & Vault Entries (ML Classified)
        self.stdout.write("Creating historical PIT teams and Vault archives...")
        
        def log_team_milestone(team, leader_user):
            log_historical_action(
                semester=team.semester,
                category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
                action="student_teams.create",
                target_type="StudentTeam",
                target_id=team.id,
                actor=pit_lead if "PIT" in team.level else adviser,
                new_values={
                    "name": team.name,
                    "project_title": team.project_title,
                    "level": team.level,
                    "year_level": team.year_level,
                    "leader": leader_user.username,
                },
                reason=f"Form team {team.name}."
            )
            for m in TeamMembership.objects.filter(team=team):
                log_historical_action(
                    semester=team.semester,
                    category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
                    action="student_teams.add_member",
                    target_type="TeamMembership",
                    target_id=m.id,
                    actor=pit_lead if "PIT" in team.level else adviser,
                    new_values={
                        "team_id": team.id,
                        "team_name": team.name,
                        "student": m.student.username,
                        "is_leader": m.is_leader,
                    },
                    reason=f"Add member {m.student.username} to {team.name}."
                )

        def sync_team(team_obj, leader_user, member_list):
            for idx, member in enumerate(member_list):
                TeamMembership.objects.create(
                    team=team_obj,
                    student=member,
                    is_leader=(member == leader_user),
                    order=idx
                )
            log_team_milestone(team_obj, leader_user)

        # Helper to seed a PIT vault entry programmatically (triggers ML text extraction & classification on save)
        def seed_pit_vault_entry(team, academic_year, semester_label, file_name, file_obj, course_code):
            entry = VaultEntry.objects.create(
                entry_type=VaultEntry.TYPE_PIT,
                file_name=file_name,
                academic_year=academic_year,
                team=team,
                team_name=team.name,
                year_level=team.year_level,
                course_code=course_code,
                semester_label=semester_label,
                stage_label=course_code,
                status=VaultEntry.STATUS_APPROVED,
                uploaded_by=pit_lead,
                uploaded_by_name=f"{pit_lead.first_name} {pit_lead.last_name}",
                metadata={
                    'project_slug': file_name.split('.')[2] if len(file_name.split('.')) > 2 else 'ProjectTitle',
                    'matched': True,
                    'project_title': team.project_title,
                }
            )
            entry.file.save(file_name, file_obj, save=True)
            
            # Fetch updated entry to get correct file size/url
            entry.refresh_from_db()
            scope_meta = audit_scope_metadata(scope='pit', team=team)
            log_historical_action(
                semester=team.semester,
                category=SystemAuditLog.CATEGORY_REPOSITORY,
                action="repository.vault_upload",
                target_type="VaultEntry",
                target_id=entry.pk,
                actor=pit_lead,
                new_values={
                    "file_name": entry.file_name,
                    "file_url": entry.file.url if entry.file else "",
                    "file_size": entry.file_size or "Unknown Size",
                    "status": entry.status,
                    **scope_meta
                },
                reason=f"Submit approved PIT deliverable: {entry.file_name}"
            )
            return entry

        # Year 1 Sem 1: 1st Year PIT 1
        t_pit1 = StudentTeam.objects.create(
            name="ByteSized PIT 1",
            project_title="Introduction to Programming Logic and Flowcharts",
            level="1st Year PIT",
            year_level="1st Year",
            semester=sem1,
            leader=students[0],
            status=StudentTeam.STATUS_APPROVED
        )
        sync_team(t_pit1, students[0], students)
        pdf_pit1 = generate_seeding_pdf(
            "ByteSized PIT 1 Project Report",
            "1st Year PIT - Basic programming flowcharts and control logic",
            "We implement basic sequential flowcharts and logic structures to introduce programming foundations.",
            ["variables", "loops", "logic", "flowcharts"],
            tech_focus="prog"
        )
        seed_pit_vault_entry(t_pit1, "2023-2024", "1st Semester", "1stYear.PIT101.ByteSizedPIT1.1stSemester.pdf", pdf_pit1, "PIT101")

        # Year 1 Sem 2: 1st Year PIT 2
        t_pit2 = StudentTeam.objects.create(
            name="ByteSized PIT 2",
            project_title="Command Line Tools and Scripting in Python",
            level="1st Year PIT",
            year_level="1st Year",
            semester=sem2,
            leader=students[0],
            status=StudentTeam.STATUS_APPROVED
        )
        sync_team(t_pit2, students[0], students)
        pdf_pit2 = generate_seeding_pdf(
            "ByteSized PIT 2 Project Report",
            "1st Year PIT - Basic CLI tools and file processing in python",
            "We build a command-line script interface using Python for scanning directory files and parsing plain text content.",
            ["python", "command line", "scripts"],
            tech_focus="desktop"
        )
        seed_pit_vault_entry(t_pit2, "2023-2024", "2nd Semester", "1stYear.PIT102.ByteSizedPIT2.2ndSemester.pdf", pdf_pit2, "PIT102")

        # Year 2 Sem 1: 2nd Year PIT 1
        t_pit3 = StudentTeam.objects.create(
            name="LogicCraft PIT 1",
            project_title="Desktop GUI Interfaces and SQLite Integration",
            level="2nd Year PIT",
            year_level="2nd Year",
            semester=sem3,
            leader=students[0],
            status=StudentTeam.STATUS_APPROVED
        )
        sync_team(t_pit3, students[0], students)
        pdf_pit3 = generate_seeding_pdf(
            "LogicCraft PIT 1 Project Report",
            "2nd Year PIT - Desktop GUI applications with SQLite databases",
            "We construct a desktop graphical user interface using desktop widgets and SQLite database models for storing student records locally.",
            ["GUI", "sqlite", "local database", "widgets"],
            tech_focus="desktop"
        )
        seed_pit_vault_entry(t_pit3, "2024-2025", "1st Semester", "2ndYear.PIT201.LogicCraftPIT1.1stSemester.pdf", pdf_pit3, "PIT201")

        # Year 2 Sem 2: 2nd Year PIT 2
        t_pit4 = StudentTeam.objects.create(
            name="LogicCraft PIT 2",
            project_title="Local LAN Socket Communication and Network Sync",
            level="2nd Year PIT",
            year_level="2nd Year",
            semester=sem4,
            leader=students[0],
            status=StudentTeam.STATUS_APPROVED
        )
        sync_team(t_pit4, students[0], students)
        pdf_pit4 = generate_seeding_pdf(
            "LogicCraft PIT 2 Project Report",
            "2nd Year PIT - Local sockets communications and TCP IP networking",
            "We deploy local area network communication scripts using TCP IP socket connections to sync logs between two computers.",
            ["tcp ip", "sockets", "networking"],
            tech_focus="network"
        )
        seed_pit_vault_entry(t_pit4, "2024-2025", "2nd Semester", "2ndYear.PIT202.LogicCraftPIT2.2ndSemester.pdf", pdf_pit4, "PIT202")

        # Year 3 Sem 1: 3rd Year PIT
        t_pit5 = StudentTeam.objects.create(
            name="DataQuest PIT",
            project_title="Web Interfaces and Sensor Data Gathering",
            level="3rd Year PIT",
            year_level="3rd Year",
            semester=sem5,
            leader=students[0],
            status=StudentTeam.STATUS_APPROVED
        )
        sync_team(t_pit5, students[0], students)
        pdf_pit5 = generate_seeding_pdf(
            "DataQuest PIT Project Report",
            "3rd Year PIT - Web dashboard with sensor data logs",
            "We build a responsive web interface dashboard using React and Django for data visualization.",
            ["web framework", "dashboard", "react", "django", "html", "css"],
            tech_focus="web"
        )
        seed_pit_vault_entry(t_pit5, "2025-2026", "1st Semester", "3rdYear.PIT301.DataQuestPIT.1stSemester.pdf", pdf_pit5, "PIT301")


        # 6. Populate Capstone Timeline (Capstone 1 -> Capstone 2 Continuation)
        self.stdout.write("Configuring sequential Capstone milestones...")
        
        # Capstone 1 (Sem 6)
        team_cap1 = StudentTeam.objects.create(
            name="Team Apex Capstone",
            project_title="AI-Powered Crop Disease Classifier and Smart Irrigation Web Application",
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level="3rd Year",
            semester=sem6,
            leader=students[0],
            adviser=adviser,
            status=StudentTeam.STATUS_APPROVED,
            capstone_phase=StudentTeam.PHASE_ACTIVE,
            ready_for_stage="Oral Defense"
        )
        sync_team(team_cap1, students[0], students)

        # Capstone 2 (Sem 7 - Active)
        team_cap2 = StudentTeam.objects.create(
            name="Team Apex Capstone",
            project_title="AI-Powered Crop Disease Classifier and Smart Irrigation Web Application",
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level="4th Year",
            semester=sem7,
            leader=students[0],
            adviser=adviser,
            status=StudentTeam.STATUS_APPROVED,
            capstone_phase=StudentTeam.PHASE_ACTIVE,
            ready_for_stage="Oral Defense"
        )
        sync_team(team_cap2, students[0], students)

        # Update student active team IDs
        for s in students:
            s.team_id = str(team_cap2.id)
            s.save()

        # Stages
        concept_stage, _ = DefenseStage.objects.get_or_create(
            label="Concept Proposal", defaults={'display_order': 1}
        )
        proposal_stage, _ = DefenseStage.objects.get_or_create(
            label="Project Proposal", defaults={'display_order': 2}
        )
        oral_stage, _ = DefenseStage.objects.get_or_create(
            label="Oral Defense", defaults={'display_order': 3}
        )

        p1 = TeamStageProgress.objects.create(
            team=team_cap1, semester=sem6, defense_stage=concept_stage, status=TeamStageProgress.STATUS_PASSED
        )
        p2 = TeamStageProgress.objects.create(
            team=team_cap1, semester=sem6, defense_stage=proposal_stage, status=TeamStageProgress.STATUS_PASSED
        )
        p3 = TeamStageProgress.objects.create(
            team=team_cap2, semester=sem7, defense_stage=oral_stage, status=TeamStageProgress.STATUS_READY
        )

        # Log grading (passed/ready) stages
        log_historical_action(
            semester=sem6,
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action="grade_center.stage_pass",
            target_type="TeamStageProgress",
            target_id=p1.pk,
            actor=adviser,
            new_values={
                "stage": concept_stage.label,
                "status": TeamStageProgress.STATUS_PASSED,
                "team_id": team_cap1.id,
                "team_name": team_cap1.name,
            },
            reason=f"Mark defense stage '{concept_stage.label}' as PASSED for team '{team_cap1.name}'."
        )
        log_historical_action(
            semester=sem6,
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action="grade_center.stage_pass",
            target_type="TeamStageProgress",
            target_id=p2.pk,
            actor=adviser,
            new_values={
                "stage": proposal_stage.label,
                "status": TeamStageProgress.STATUS_PASSED,
                "team_id": team_cap1.id,
                "team_name": team_cap1.name,
            },
            reason=f"Mark defense stage '{proposal_stage.label}' as PASSED for team '{team_cap1.name}'."
        )
        log_historical_action(
            semester=sem7,
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action="grade_center.stage_ready",
            target_type="TeamStageProgress",
            target_id=p3.pk,
            actor=adviser,
            new_values={
                "stage": oral_stage.label,
                "status": TeamStageProgress.STATUS_READY,
                "team_id": team_cap2.id,
                "team_name": team_cap2.name,
            },
            reason=f"Mark defense stage '{oral_stage.label}' as READY for team '{team_cap2.name}'."
        )

        # 7. Generate Capstone Deliverables
        self.stdout.write("Uploading Capstone deliverables (indexing ML)...")
        abstract_text = (
            "We implement an AI-powered crop disease classifier using deep learning, neural networks, and convolutional neural network models "
            "trained with TensorFlow and Keras. The system classifies plant leaf anomalies using image classification. "
            "The backend services are built on Django, exposing clean REST APIs. Database systems rely on MySQL and PostgreSQL for transaction integrity."
        )
        ml_keywords = [
            "machine learning", "neural network", "tensorflow", "pytorch", "classification",
            "model training", "django", "rest api", "mysql"
        ]

        # Concept Proposal
        cp_file = generate_seeding_pdf("Concept Proposal Document", "Capstone 1 - Initial Pitch", abstract_text, ml_keywords, tech_focus="ml")
        cp_sub = DeliverableSubmission(
            team=team_cap1,
            stage_label="Concept Proposal",
            deliverable_id="CP",
            label="Concept Proposal Document",
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            required=True,
            file_name="concept_proposal.pdf",
            file_size=f"{len(cp_file) // 1024} KB",
            uploaded_by=students[0]
        )
        cp_sub.file.save("concept_proposal.pdf", cp_file, save=True)

        cp_sub.refresh_from_db()
        log_historical_action(
            semester=sem6,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action="repository.deliverable_submit",
            target_type="DeliverableSubmission",
            target_id=cp_sub.pk,
            actor=students[0],
            new_values={
                "file_name": cp_sub.file_name,
                "file_url": cp_sub.file.url if cp_sub.file else "",
                "file_size": cp_sub.file_size,
                "stage": cp_sub.stage_label,
                "team_id": team_cap1.id,
                "team_name": team_cap1.name,
            },
            reason=f"Upload capstone deliverable: {cp_sub.file_name}"
        )

        # Project Proposal
        pp_file = generate_seeding_pdf("Project Proposal Document", "Capstone 1 - Detailed Methodology", abstract_text, ml_keywords, tech_focus="ml")
        pp_sub = DeliverableSubmission(
            team=team_cap1,
            stage_label="Project Proposal",
            deliverable_id="PP",
            label="Project Proposal Document",
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            required=True,
            file_name="project_proposal.pdf",
            file_size=f"{len(pp_file) // 1024} KB",
            uploaded_by=students[0]
        )
        pp_sub.file.save("project_proposal.pdf", pp_file, save=True)

        pp_sub.refresh_from_db()
        log_historical_action(
            semester=sem6,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action="repository.deliverable_submit",
            target_type="DeliverableSubmission",
            target_id=pp_sub.pk,
            actor=students[0],
            new_values={
                "file_name": pp_sub.file_name,
                "file_url": pp_sub.file.url if pp_sub.file else "",
                "file_size": pp_sub.file_size,
                "stage": pp_sub.stage_label,
                "team_id": team_cap1.id,
                "team_name": team_cap1.name,
            },
            reason=f"Upload capstone deliverable: {pp_sub.file_name}"
        )

        # Oral Defense
        od_file = generate_seeding_pdf("Oral Defense Document", "Capstone 2 - Final Implementation", abstract_text, ml_keywords, tech_focus="ml")
        od_sub = DeliverableSubmission(
            team=team_cap2,
            stage_label="Oral Defense",
            deliverable_id="OD",
            label="Oral Defense Document",
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            required=True,
            file_name="oral_defense.pdf",
            file_size=f"{len(od_file) // 1024} KB",
            uploaded_by=students[0]
        )
        od_sub.file.save("oral_defense.pdf", od_file, save=True)

        od_sub.refresh_from_db()
        log_historical_action(
            semester=sem7,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action="repository.deliverable_submit",
            target_type="DeliverableSubmission",
            target_id=od_sub.pk,
            actor=students[0],
            new_values={
                "file_name": od_sub.file_name,
                "file_url": od_sub.file.url if od_sub.file else "",
                "file_size": od_sub.file_size,
                "stage": od_sub.stage_label,
                "team_id": team_cap2.id,
                "team_name": team_cap2.name,
            },
            reason=f"Upload capstone deliverable: {od_sub.file_name}"
        )

        self.stdout.write(self.style.SUCCESS("Success! Populated database with full 7-semester student progression, PIT Vault entries, and Capstone deliverables."))
