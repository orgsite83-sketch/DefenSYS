"""
DefenSYS Deliverables Generator
Generates realistic Pre-Defense and Post-Defense PDF deliverable artifacts for all 72 team-events/stages
and places them into sample_file/Project_Manuscripts/ organized by year level and semester.

Rules:
1. Each event and stage has exactly 2 Pre-Defense and 2 Post-Defense deliverables.
2. PIT events have unique deliverables tailored to their specific milestone themes.
3. Capstone stages have verdict-driven deliverables:
   - Concept Proposal: Pre has Concept Paper & Pitch Deck; Post has Approved Concept Paper & Signed Minutes.
   - Project Proposal: Pre has Proposal Manuscript Ch 1-3 & PoC Prototype Spec; Post has Approved Proposal Manuscript & Signed Matrix of Revisions.
   - Colloquium: Pre has Final Draft Ch 1-5 & Inspection Signoff; Post has Approved Final Manuscript & IEEE Journal/Source Bundle.
4. All PDFs are generated with ReportLab with official USTP & DefenSYS branding, metadata tables, verdict badges, and signature blocks.
"""

import os
import sys
import re
from pathlib import Path

# Add backend directory to sys.path
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    HRFlowable,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY

from generate_sample_curriculum_data import get_all_projects


def sanitize_filename(name: str) -> str:
    s = re.sub(r'[^a-zA-Z0-9_-]', '', name.replace(' ', '_'))
    return s[:40]


def get_event_subfolder(event_or_stage: str, track: str) -> str:
    if track == "Capstone":
        stage_map = {
            "Concept Proposal": "Stage_1_Concept_Proposal",
            "Project Proposal": "Stage_2_Project_Proposal",
            "Colloquium": "Stage_3_Colloquium",
        }
        return stage_map.get(event_or_stage, sanitize_filename(event_or_stage))
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
        return pit_map.get(event_or_stage, sanitize_filename(event_or_stage))


def get_target_dir(workspace_root: str, proj: dict) -> str:
    yl = proj['year_level']
    sem = proj['semester']
    track = proj['track']
    evt = proj.get('event_or_stage', '')
    sub_stage = get_event_subfolder(evt, track)
    team_name = sanitize_filename(proj['team_name'])

    if yl == "1st Year":
        sub = "1st_Sem" if "1st" in sem else "2nd_Sem"
        return os.path.join(workspace_root, "sample_file", "Project_Manuscripts", "1st_Year", sub, sub_stage, team_name)
    elif yl == "2nd Year":
        sub = "1st_Sem" if "1st" in sem else "2nd_Sem"
        return os.path.join(workspace_root, "sample_file", "Project_Manuscripts", "2nd_Year", sub, sub_stage, team_name)
    elif yl == "3rd Year":
        if track == "PIT":
            return os.path.join(workspace_root, "sample_file", "Project_Manuscripts", "3rd_Year", "1st_Sem_PIT", sub_stage, team_name)
        else:
            return os.path.join(workspace_root, "sample_file", "Project_Manuscripts", "3rd_Year", "2nd_Sem_Capstone", sub_stage, team_name)
    else:  # 4th Year
        sub = "1st_Sem" if "1st" in sem else "2nd_Sem"
        return os.path.join(workspace_root, "sample_file", "Project_Manuscripts", "4th_Year_Capstone", sub, sub_stage, team_name)


def get_event_deliverable_specs(event_or_stage: str, track: str):
    """
    Returns (pre1, pre2, post1, post2) deliverable specifications.
    Each is a tuple: (code, short_name, full_title, phase_label, description, verdict_text, badge_color)
    """
    # Capstone stages
    if track == "Capstone":
        if event_or_stage == "Concept Proposal":
            pre1 = (
                "D4", "Concept_Paper_Manuscript",
                "D4 - Concept Proposal Paper & Research Abstract",
                "PRE-DEFENSE DELIVERABLE 1",
                "Formal 5-page initial concept proposal detailing problem formulation, literature background, and technical feasibility.",
                "SUBMITTED FOR ORAL HEARING EVALUATION - Panel Primary Defense Material",
                "#0369A1"
            )
            pre2 = (
                "D1", "Adviser_Endorsement_and_Pitch_Deck",
                "D1 - Adviser Acceptance & Concept Pitch Presentation",
                "PRE-DEFENSE DELIVERABLE 2",
                "Written endorsement from Project Adviser certifying topic viability accompanied by structured 10-slide oral pitch deck.",
                "SUBMITTED FOR ORAL HEARING EVALUATION - Adviser Readiness Endorsed",
                "#0369A1"
            )
            post1 = (
                "D4.1", "Approved_Concept_Paper",
                "D4.1 - Approved & Revised Concept Paper",
                "POST-DEFENSE DELIVERABLE 1 (APPROVED)",
                "Consolidated concept document revised in accordance with panel recommendations, bearing approval seals.",
                "OFFICIAL HEARING VERDICT: PASSED WITH REVISIONS - Stage Defense Endorsed for Project Vault",
                "#059669"
            )
            post2 = (
                "D5", "Signed_Concept_Minutes_and_Verdict",
                "D5 - Signed Minutes of Concept Defense & Verdict Sheet",
                "POST-DEFENSE DELIVERABLE 2 (APPROVED)",
                "Official hearing transcript recorded by Secretariat/Documenter detailing panel action items and passing scores.",
                "OFFICIAL HEARING VERDICT: PASSED WITH REVISIONS - Committee Signatures Verified",
                "#059669"
            )
            return pre1, pre2, post1, post2

        elif event_or_stage == "Project Proposal":
            pre1 = (
                "D7_9", "Proposal_Manuscript_Chapters_1_to_3",
                "D7-D9 - Technical Proposal Manuscript (Chapters 1-3)",
                "PRE-DEFENSE DELIVERABLE 1",
                "Comprehensive academic manuscript containing Chapter 1 (Introduction), Chapter 2 (Literature Review), and Chapter 3 (Methodology).",
                "SUBMITTED FOR PROPOSAL DEFENSE - Panel Primary Defense Material",
                "#0369A1"
            )
            pre2 = (
                "D9.1", "Proof_of_Concept_Prototype_Specification",
                "D9.1 - Proof-of-Concept Prototype Specification & Sandbox",
                "PRE-DEFENSE DELIVERABLE 2",
                "Technical specification of minimum viable prototype, live sandbox deployment link, and API endpoint test runs.",
                "SUBMITTED FOR PROPOSAL DEFENSE - Functional Prototype Verified by Adviser",
                "#0369A1"
            )
            post1 = (
                "D10", "Approved_Proposal_Manuscript_Chapters_1_to_3",
                "D10 - Approved Proposal Technical Manuscript (Chapters 1-3)",
                "POST-DEFENSE DELIVERABLE 1 (APPROVED)",
                "Final proposal manuscript revised per panel directives, formatted in strict compliance with university capstone guidelines.",
                "OFFICIAL PROPOSAL VERDICT: PASSED WITH REVISIONS - Archived to Institutional Project Vault",
                "#059669"
            )
            post2 = (
                "D13", "Signed_Matrix_of_Revisions_and_Minutes",
                "D13 - Signed Matrix of Revisions & Proposal Minutes",
                "POST-DEFENSE DELIVERABLE 2 (APPROVED)",
                "Itemized verification table certifying line-by-line compliance with panel recommendations, signed by all panel members.",
                "OFFICIAL PROPOSAL VERDICT: COMPLIANCE CERTIFIED - Signed by Defense Chair & Panelists",
                "#059669"
            )
            return pre1, pre2, post1, post2

        else:  # Colloquium / Final Defense
            pre1 = (
                "D14", "Draft_Technical_Manuscript_Chapters_1_to_5",
                "D14 - Full Draft Technical Manuscript (Chapters 1-5)",
                "PRE-DEFENSE DELIVERABLE 1",
                "Complete technical manuscript draft including Chapter 4 (Empirical Results & Discussion) and Chapter 5 (Conclusions).",
                "SUBMITTED FOR FINAL COLLOQUIUM - Panel Primary Defense Material",
                "#0369A1"
            )
            pre2 = (
                "D14.1", "Pre_Deployment_Inspection_and_Plagiarism_Scan",
                "D14.1 - System Pre-Deployment Verification & Plagiarism Scan",
                "PRE-DEFENSE DELIVERABLE 2",
                "Adviser inspection certificate confirming 100% operational system alongside Turnitin similarity report (<15%).",
                "SUBMITTED FOR FINAL COLLOQUIUM - Pre-Defense Quality Clearance Endorsed",
                "#0369A1"
            )
            post1 = (
                "D16", "Approved_Final_Technical_Manuscript_Chapters_1_to_5",
                "D16 - Approved Full-Length Final Manuscript (Chapters 1-5)",
                "POST-DEFENSE DELIVERABLE 1 (APPROVED)",
                "Hardbound-grade final manuscript signed by College Dean, Department Chair, Panelists, and Project Adviser.",
                "OFFICIAL FINAL VERDICT: PASSED UNANIMOUSLY - Permanent Vault Archive & Library Deposit",
                "#059669"
            )
            post2 = (
                "D17_15", "IEEE_Executive_Journal_and_Source_Release_Bundle",
                "D17/D15 - IEEE Executive Journal & Complete Source Bundle",
                "POST-DEFENSE DELIVERABLE 2 (APPROVED)",
                "7-page IEEE-format camera-ready conference paper accompanied by complete Dockerized software repository snapshot.",
                "OFFICIAL FINAL VERDICT: CLEARED FOR GRADUATION - Final Institutional Release Approved",
                "#059669"
            )
            return pre1, pre2, post1, post2

    # PIT Events (Progressive milestone exhibitions - NOT verdict-based)
    # Architecture:
    # PRE1: Draft Case Study / Concept Paper / Technical Report (Draft evaluated during event)
    # PRE2: Pitch Deck / Prototype Test Run Specs / Exhibition Poster (Event presentation materials)
    # POST1: Revised Final Case Study / Concept Paper / Manuscript (Public Archival Artifact!)
    # POST2: Sprint Backlog / Defect Remediation Log / API Contract / Deployment Guide / Build Package
    pit_map = {
        # 1st Year 1st Sem
        "1st Year Concept Pitch": (
            ("PIT-CP-PRE1", "Draft_Concept_Paper_and_Case_Study", "Draft Concept Paper & System Case Study", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Draft academic case study detailing target campus problem, user personas, and proposed software solution.", "SUBMITTED FOR PITCH EVALUATION", "#0369A1"),
            ("PIT-CP-PRE2", "Concept_Pitch_Deck", "Concept Pitch Deck & Slide Presentation", "PRE-EVENT DELIVERABLE 2", "Structured 10-slide oral pitch deck covering problem scope, system architecture, and sprint timeline.", "SUBMITTED FOR PITCH EVALUATION", "#0369A1"),
            ("PIT-CP-POST1", "Revised_Final_Concept_Paper_and_Case_Study", "Revised Final Concept Paper & System Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Final revised concept paper and case study incorporating evaluator feedback; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-CP-POST2", "Sprint_Backlog_and_Implementation_Roadmap", "Sprint Backlog & Prototype Implementation Roadmap", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Actionable sprint backlog mapping feature tasks, user stories, and milestone timeline for prototype build.", "MILESTONE ACTION PLAN SUBMITTED", "#4F46E5"),
        ),
        "1st Year Prototype Defense": (
            ("PIT-PD-PRE1", "Draft_Prototype_Architecture_Report", "Draft Prototype Architecture & Logic Report", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Technical case study documenting functional logic, input/output flow, and modular execution.", "SUBMITTED FOR PROTOTYPE REVIEW", "#0369A1"),
            ("PIT-PD-PRE2", "UI_Wireframes_and_Test_Run_Specs", "UI Screen Wireframes & Prototype Test Run Specs", "PRE-EVENT DELIVERABLE 2", "Screen wireframes, state transition diagrams, and responsive layout test run specifications.", "SUBMITTED FOR PROTOTYPE REVIEW", "#0369A1"),
            ("PIT-PD-POST1", "Revised_Prototype_Architecture_Case_Study", "Revised Prototype Architecture & Technical Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Revised prototype technical report and system case study incorporating code review feedback; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-PD-POST2", "Defect_Remediation_Log_and_Code_Audit", "Defect Remediation Log & Code Quality Audit", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Itemized defect resolution log and Git commit audit certifying code hygiene and refactoring.", "MILESTONE DEFECT REMEDIATION VERIFIED", "#4F46E5"),
        ),
        "1st Year Tech Expo": (
            ("PIT-TE-PRE1", "Draft_Tech_Expo_Research_Manuscript", "Draft 5-Page Tech Expo Research Manuscript", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Draft 5-page publication-grade research manuscript ingested into DefenSYS DSS analytics engine.", "SUBMITTED FOR TECH EXPO EXHIBITION", "#0369A1"),
            ("PIT-TE-PRE2", "Showcase_Exhibition_Poster", "Project Showcase Exhibition Poster & Demo Spec", "PRE-EVENT DELIVERABLE 2", "High-resolution graphic exhibition poster summarizing problem background, system architecture, and UI.", "SUBMITTED FOR TECH EXPO EXHIBITION", "#0369A1"),
            ("PIT-TE-POST1", "Final_Tech_Expo_Research_Manuscript", "Final Camera-Ready Research Manuscript & Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Final publication-grade research manuscript and case study incorporating exhibition review feedback; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-TE-POST2", "End_User_Deployment_and_Quick_Start_Guide", "End-User Deployment & Quick Start Guide", "POST-EVENT DELIVERABLE 2 (ARTIFACT)", "Step-by-step user installation manual, prerequisites, and software demonstration script.", "POST-EVENT ARTIFACT: USER GUIDE SUBMITTED", "#4F46E5"),
        ),

        # 1st Year 2nd Sem
        "1st Year System Design Pitch": (
            ("PIT-SD-PRE1", "Draft_System_Design_Case_Study", "Draft System Design Case Study & User Stories", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Technical design case study detailing functional personas, user journeys, and component architecture.", "SUBMITTED FOR SYSTEM DESIGN PITCH", "#0369A1"),
            ("PIT-SD-PRE2", "System_Design_Pitch_Deck", "System Design Pitch Deck & Architecture Blueprint", "PRE-EVENT DELIVERABLE 2", "Pitch presentation covering component diagram, client-server topology, and framework rationale.", "SUBMITTED FOR SYSTEM DESIGN PITCH", "#0369A1"),
            ("PIT-SD-POST1", "Revised_System_Design_Case_Study", "Revised System Design Specification & Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Updated system design case study incorporating faculty feedback on interface modularity; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-SD-POST2", "Sprint_Work_Breakdown_and_Module_Plan", "Sprint Work Breakdown & Module Allocation Plan", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Gantt timeline mapping sprint backlog cards and team role ownership for subsystem implementation.", "MILESTONE WORK BREAKDOWN SUBMITTED", "#4F46E5"),
        ),
        "1st Year Midterm Progress Defense": (
            ("PIT-MP-PRE1", "Draft_Midterm_Technical_Manuscript", "Draft Midterm Progress Technical Manuscript (Ch 1-3)", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Interim technical manuscript documenting problem context, preliminary schema, and system logic.", "SUBMITTED FOR MIDTERM REVIEW", "#0369A1"),
            ("PIT-MP-PRE2", "CRUD_Data_Flow_and_Test_Results", "CRUD Transaction Logs & Validation Test Suite", "PRE-EVENT DELIVERABLE 2", "Automated test runs confirming database write/read integrity and input sanitization.", "SUBMITTED FOR MIDTERM REVIEW", "#0369A1"),
            ("PIT-MP-POST1", "Revised_Midterm_Technical_Case_Study", "Revised Midterm Technical Case Study & Architecture Report", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Revised technical case study addressing oral code defense recommendations; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-MP-POST2", "Bug_Remediation_Tracker_and_Revision_Log", "Bug Remediation Tracker & Code Revision Log", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Itemized issue tracker and resolution log resolving software defects identified during midterm evaluation.", "MILESTONE BUG REMEDIATION COMPLETED", "#4F46E5"),
        ),
        "1st Year Year-End Showcase": (
            ("PIT-YS-PRE1", "Draft_Year_End_Showcase_Manuscript", "Draft 5-Page Year-End Showcase Manuscript", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Comprehensive technical manuscript draft ingested into DefenSYS DSS analytics engine.", "SUBMITTED FOR YEAR-END SHOWCASE", "#0369A1"),
            ("PIT-YS-PRE2", "User_Manual_and_Setup_Guide", "Comprehensive End-User Manual & API Reference", "PRE-EVENT DELIVERABLE 2", "Full documentation suite explaining installation, environment variables, and user workflow.", "SUBMITTED FOR YEAR-END SHOWCASE", "#0369A1"),
            ("PIT-YS-POST1", "Final_Year_End_Showcase_Manuscript", "Final Year-End Showcase Research Manuscript & Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Final publication-grade research manuscript and system case study; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-YS-POST2", "Release_Distribution_Manifest_and_Checksums", "Release Distribution Manifest & Build Checksums", "POST-EVENT DELIVERABLE 2 (ARTIFACT)", "Software build artifact manifest, repository snapshot, and checksum hashes archived for showcase.", "POST-EVENT ARTIFACT: BUILD MANIFEST SUBMITTED", "#4F46E5"),
        ),

        # 2nd Year 1st Sem
        "2nd Year Architecture Pitch": (
            ("PIT-AP-PRE1", "Draft_Architecture_Pitch_Case_Study", "Draft Multi-Tier Architecture Case Study", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Technical case study outlining presentation, business controller, and database access layers.", "SUBMITTED FOR ARCHITECTURE PITCH", "#0369A1"),
            ("PIT-AP-PRE2", "Architecture_Pitch_Deck_and_ERD", "Architecture Pitch Deck & Normalized 3NF ERD", "PRE-EVENT DELIVERABLE 2", "Third Normal Form ERD diagram, relational tables, and multi-tier presentation slides.", "SUBMITTED FOR ARCHITECTURE PITCH", "#0369A1"),
            ("PIT-AP-POST1", "Revised_Multi_Tier_Architecture_Case_Study", "Revised Multi-Tier Architecture Case Study & Specification", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Refined architecture document certifying schema normalization and security parameters; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-AP-POST2", "Revised_REST_API_Route_Contract", "Revised RESTful API Route Specification Contract", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Updated Swagger/OpenAPI endpoint contract incorporating schema and authentication feedback.", "MILESTONE REVISED API CONTRACT SUBMITTED", "#4F46E5"),
        ),
        "2nd Year Milestone Review": (
            ("PIT-MR-PRE1", "Draft_Backend_Integration_Case_Study", "Draft Backend REST API & Integration Case Study", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Technical report detailing controller execution, transaction safety, and endpoint tests.", "SUBMITTED FOR MILESTONE REVIEW", "#0369A1"),
            ("PIT-MR-PRE2", "Automated_Unit_and_Integration_Logs", "Automated Unit Test Suites & Integration Logs", "PRE-EVENT DELIVERABLE 2", "Test runner logs demonstrating 80%+ code coverage on controllers, services, and models.", "SUBMITTED FOR MILESTONE REVIEW", "#0369A1"),
            ("PIT-MR-POST1", "Revised_Backend_Integration_Case_Study", "Revised Backend Integration Case Study & System Report", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Revised integration case study addressing faculty code evaluation; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-MR-POST2", "Git_Merge_Audit_and_Code_Review_Summary", "Git Merge Audit Log & Peer Code Review Summary", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Peer code review audit log verifying resolved pull request comments, clean branching, and test passes.", "MILESTONE CODE REVIEW AUDIT VERIFIED", "#4F46E5"),
        ),
        "2nd Year Innovation Expo": (
            ("PIT-IE-PRE1", "Draft_Innovation_Expo_Manuscript", "Draft 5-Page Innovation Expo Research Manuscript", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "5-page research manuscript draft for DefenSYS DSS analytics classification and indexing.", "SUBMITTED FOR INNOVATION EXPO", "#0369A1"),
            ("PIT-IE-PRE2", "Docker_Deployment_and_Latency_Report", "Docker Container Deployment & Performance Benchmark", "PRE-EVENT DELIVERABLE 2", "Benchmarking report detailing sub-second latency, throughput, and container health.", "SUBMITTED FOR INNOVATION EXPO", "#0369A1"),
            ("PIT-IE-POST1", "Final_Innovation_Expo_Research_Manuscript", "Final Innovation Expo Research Manuscript & Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Final publication-grade research manuscript and case study; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-IE-POST2", "Deployment_Validation_and_System_Health_Report", "Deployment Validation & System Health Report", "POST-EVENT DELIVERABLE 2 (ARTIFACT)", "Verified cloud deployment status report, SSL/TLS checks, and operational health metrics.", "POST-EVENT ARTIFACT: DEPLOYMENT HEALTH REPORT SUBMITTED", "#4F46E5"),
        ),

        # 2nd Year 2nd Sem
        "2nd Year System Pitch": (
            ("PIT-SP-PRE1", "Draft_Enterprise_System_Case_Study", "Draft Enterprise Domain & System Case Study", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Domain problem statement and requirements specification for IoT, GIS, AI, or SaaS ERP.", "SUBMITTED FOR SYSTEM PITCH", "#0369A1"),
            ("PIT-SP-PRE2", "System_Pitch_Deck_and_RBAC_Blueprint", "Enterprise System Pitch Deck & RBAC Security Blueprint", "PRE-EVENT DELIVERABLE 2", "Role-based access matrix, session token lifecycle, and slide presentation.", "SUBMITTED FOR SYSTEM PITCH", "#0369A1"),
            ("PIT-SP-POST1", "Revised_Enterprise_System_Case_Study", "Revised Enterprise System Case Study & Domain Specification", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Refined enterprise case study incorporating evaluator domain critique; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-SP-POST2", "Engineering_Sprint_Allocation_and_Action_Plan", "Engineering Sprint Allocation & Team Action Plan", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Revised team charter detailing sprint backlog velocity, role ownership, and action items.", "MILESTONE TEAM ACTION PLAN SUBMITTED", "#4F46E5"),
        ),
        "2nd Year Midterm Defense": (
            ("PIT-MD-PRE1", "Draft_Subsystem_Design_Case_Study", "Draft Subsystem Design & Data Modeling Case Study", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Technical document detailing asynchronous microservices, sensor loops, or spatial queries.", "SUBMITTED FOR MIDTERM REVIEW", "#0369A1"),
            ("PIT-MD-PRE2", "Async_Concurrency_Performance_Log", "Asynchronous Worker & Concurrency Performance Log", "PRE-EVENT DELIVERABLE 2", "Performance load test logs validating thread safety and non-blocking event loops.", "SUBMITTED FOR MIDTERM REVIEW", "#0369A1"),
            ("PIT-MD-POST1", "Revised_Subsystem_Design_Case_Study", "Revised Subsystem Design Case Study & Performance Report", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Revised technical design report resolving oral defense critique; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-MD-POST2", "Security_Hardening_and_Exception_Matrix", "Security Hardening & Exception Remediation Matrix", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Remediation tracker documenting resolution of identified security flaws, CSRF, and injection vectors.", "MILESTONE SECURITY REMEDIATION SUBMITTED", "#4F46E5"),
        ),
        "2nd Year Project Showcase": (
            ("PIT-PS-PRE1", "Draft_Project_Showcase_Manuscript", "Draft 5-Page Project Showcase Manuscript", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Standard 5-page manuscript draft ingested into DefenSYS DSS analytics classification.", "SUBMITTED FOR PROJECT SHOWCASE", "#0369A1"),
            ("PIT-PS-PRE2", "System_Throughput_Optimization_Report", "System Throughput, Query & Asset Optimization Report", "PRE-EVENT DELIVERABLE 2", "Empirical evaluation documenting caching hits, asset minimization, and render speed.", "SUBMITTED FOR PROJECT SHOWCASE", "#0369A1"),
            ("PIT-PS-POST1", "Final_Project_Showcase_Manuscript", "Final Project Showcase Research Manuscript & Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Final publication-grade research manuscript and case study; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-PS-POST2", "Production_Release_Bundle_and_Manifest", "Production Build Bundle & Staging Verification Manifest", "POST-EVENT DELIVERABLE 2 (ARTIFACT)", "Final release bundle including container compose, seed SQL, and user documentation.", "POST-EVENT ARTIFACT: BUILD MANIFEST ARCHIVED", "#4F46E5"),
        ),

        # 3rd Year 1st Sem
        "3rd Year Capstone Readiness Pitch": (
            ("PIT-CR-PRE1", "Draft_Capstone_Readiness_Case_Study", "Draft Capstone Readiness Case Study & Research Gap Synthesis", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Research gap analysis evaluating industry challenges, stack feasibility, and project objectives.", "SUBMITTED FOR READINESS PITCH", "#0369A1"),
            ("PIT-CR-PRE2", "Capstone_Readiness_Pitch_Deck", "Capstone Readiness Pitch Deck & Risk Mitigation Brief", "PRE-EVENT DELIVERABLE 2", "Feasibility analysis evaluating AI/ML models, cloud infrastructure, and risk bottlenecks.", "SUBMITTED FOR READINESS PITCH", "#0369A1"),
            ("PIT-CR-POST1", "Revised_Capstone_Readiness_Case_Study", "Revised Capstone Readiness Case Study & Research Roadmap", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Refined readiness paper incorporating faculty transition advice; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-CR-POST2", "Team_Role_Commitment_Matrix", "Consolidated Team Role Commitment Matrix", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Student role commitment agreements outlining technical specialization roles for upcoming Capstone.", "MILESTONE TEAM COMMITMENT SUBMITTED", "#4F46E5"),
        ),
        "3rd Year Systems Defense": (
            ("PIT-SD-PRE1", "Draft_Advanced_Systems_Case_Study", "Draft Advanced Systems Engineering & Architecture Case Study", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "In-depth engineering manuscript draft detailing ML models, GIS spatial algorithms, or IoT networks.", "SUBMITTED FOR SYSTEMS DEFENSE", "#0369A1"),
            ("PIT-SD-PRE2", "Algorithm_Inference_and_Audit_Log", "Algorithm Verification & Enterprise Audit Trail Log", "PRE-EVENT DELIVERABLE 2", "Logs validating model inference latency, PostGIS queries, and immutable audit trails.", "SUBMITTED FOR SYSTEMS DEFENSE", "#0369A1"),
            ("PIT-SD-POST1", "Revised_Advanced_Systems_Case_Study", "Revised Advanced Systems Engineering Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Updated systems engineering paper resolving defense critique; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-SD-POST2", "Fault_Tolerance_and_Resilience_Matrix", "Fault Tolerance & Systems Resilience Remediation Matrix", "POST-EVENT DELIVERABLE 2 (ACTION PLAN)", "Compliance matrix detailing system resilience under simulated network/database faults.", "MILESTONE FAULT TOLERANCE REMEDIATED", "#4F46E5"),
        ),
        "3rd Year Tech Summit": (
            ("PIT-TS-PRE1", "Draft_Tech_Summit_Research_Manuscript", "Draft 5-Page Tech Summit Research Manuscript", "PRE-EVENT DELIVERABLE 1 (DRAFT)", "Comprehensive publication-grade research manuscript draft for DefenSYS DSS ingestion.", "SUBMITTED FOR TECH SUMMIT", "#0369A1"),
            ("PIT-TS-PRE2", "Empirical_Benchmarking_and_Portfolio", "Empirical Evaluation Data & Competency Portfolio", "PRE-EVENT DELIVERABLE 2", "Quantified precision/recall metrics, throughput graphs, and prerequisite competency portfolio.", "SUBMITTED FOR TECH SUMMIT", "#0369A1"),
            ("PIT-TS-POST1", "Final_Tech_Summit_Research_Manuscript", "Final Tech Summit Research Manuscript & Case Study", "POST-EVENT DELIVERABLE 1 (ARCHIVE)", "Final publication-grade research manuscript and case study; archived to Public Repository.", "MILESTONE ACCEPTED: VAULT ARCHIVED", "#059669"),
            ("PIT-TS-POST2", "Technical_Release_Bundle_and_Abstract_Brief", "Technical Project Release Bundle & Abstract Brief", "POST-EVENT DELIVERABLE 2 (ARTIFACT)", "Final packaged release repository, database dump, and 4-page technical project brief.", "POST-EVENT ARTIFACT: TECHNICAL BRIEF SUBMITTED", "#4F46E5"),
        ),
    }

    if event_or_stage in pit_map:
        return pit_map[event_or_stage]

    # Fallback default
    pre1 = ("DEL-PRE1", "Project_Manuscript", "Project Research Manuscript", "PRE-DEFENSE DELIVERABLE 1", "Technical paper submitted for panel defense.", "SUBMITTED FOR DEFENSE", "#0369A1")
    pre2 = ("DEL-PRE2", "Supporting_Artifact", "Supporting Architecture Document", "PRE-DEFENSE DELIVERABLE 2", "Supporting schematics and technical models.", "SUBMITTED FOR DEFENSE", "#0369A1")
    post1 = ("DEL-POST1", "Signed_Evaluation_Minutes", "Signed Defense Evaluation Minutes", "POST-DEFENSE DELIVERABLE 1", "Official panel hearing minutes and scores.", "MILESTONE VERDICT: APPROVED", "#059669")
    post2 = ("DEL-POST2", "Milestone_Compliance_Clearance", "Milestone Compliance Clearance Certificate", "POST-DEFENSE DELIVERABLE 2", "Compliance verification and archival sign-off.", "MILESTONE VERDICT: VAULT ARCHIVED", "#059669")
    return pre1, pre2, post1, post2


def generate_deliverable_pdf(file_path: str, proj: dict, spec: tuple):
    """
    Generates an authentic, beautifully styled 1-2 page PDF deliverable using ReportLab.
    """
    code, short_name, full_title, phase_label, description, verdict_text, badge_color = spec

    doc = SimpleDocTemplate(
        file_path,
        pagesize=letter,
        leftMargin=36,
        rightMargin=36,
        topMargin=36,
        bottomMargin=36,
    )
    styles = getSampleStyleSheet()

    header_dept_style = ParagraphStyle(
        'HeaderDept',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10,
        leading=13,
        textColor=colors.HexColor('#7F1D1D'),
        alignment=TA_CENTER,
    )
    header_sub_style = ParagraphStyle(
        'HeaderSub',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=10,
        textColor=colors.HexColor('#475569'),
        alignment=TA_CENTER,
    )
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=14,
        leading=18,
        textColor=colors.HexColor('#1E293B'),
        alignment=TA_LEFT,
        spaceAfter=4,
    )
    badge_style = ParagraphStyle(
        'Badge',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11,
        textColor=colors.white,
        alignment=TA_CENTER,
    )
    section_h1 = ParagraphStyle(
        'SectionH1',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=10.5,
        leading=13,
        textColor=colors.HexColor('#7F1D1D'),
        spaceBefore=8,
        spaceAfter=4,
    )
    body_style = ParagraphStyle(
        'Body',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=11.5,
        textColor=colors.HexColor('#1E293B'),
        alignment=TA_JUSTIFY,
        spaceAfter=4,
    )
    cell_bold = ParagraphStyle(
        'CellBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=7.5,
        leading=9.5,
        textColor=colors.HexColor('#0F172A'),
    )
    cell_text = ParagraphStyle(
        'CellText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.5,
        leading=9.5,
        textColor=colors.HexColor('#334155'),
    )
    verdict_style = ParagraphStyle(
        'Verdict',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11.5,
        textColor=colors.HexColor('#065F46') if "APPROVED" in verdict_text or "PASSED" in verdict_text or "CLEARED" in verdict_text else colors.HexColor('#075985'),
        alignment=TA_CENTER,
    )

    story = []

    # 1. INSTITUTIONAL HEADER
    story.append(Paragraph("UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES", header_dept_style))
    story.append(Paragraph("DEPARTMENT OF INFORMATION TECHNOLOGY &nbsp;|&nbsp; DEFENSYS PLATFORM", header_sub_style))
    story.append(Paragraph("Academic Operations & Digital Defense Repository", header_sub_style))
    story.append(Spacer(1, 4))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor('#7F1D1D'), spaceAfter=8))

    # 2. DELIVERABLE BADGE & TITLE
    badge_table = Table([[Paragraph(phase_label, badge_style)]], colWidths=[200])
    badge_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor(badge_color)),
        ('PADDING', (0,0), (-1,-1), 4),
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
    ]))
    
    meta_row = Table([
        [badge_table, Paragraph(f"<b>Academic Year:</b> 2025–2026 &nbsp;|&nbsp; <b>Term:</b> {proj['semester']}", ParagraphStyle('RightMeta', parent=styles['Normal'], fontName='Helvetica', fontSize=8, alignment=2, textColor=colors.HexColor('#475569')))]
    ], colWidths=[220, 320])
    meta_row.setStyle(TableStyle([
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('PADDING', (0,0), (-1,-1), 0),
    ]))
    story.append(meta_row)
    story.append(Spacer(1, 8))

    story.append(Paragraph(full_title, title_style))
    story.append(Paragraph(f"<b>Project Title:</b> <i>{proj['title']}</i>", ParagraphStyle('ProjTitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, leading=13, textColor=colors.HexColor('#0F172A'))))
    story.append(Spacer(1, 6))

    is_capstone = (proj['track'] == 'Capstone')

    # 3. PROJECT & DEFENSE METADATA TABLE
    if is_capstone:
        metadata_data = [
            [Paragraph("Project ID", cell_bold), Paragraph(proj['id'], cell_text), Paragraph("Track & Level", cell_bold), Paragraph(f"{proj['track']} — {proj['year_level']}", cell_text)],
            [Paragraph("Team Name", cell_bold), Paragraph(f"<b>{proj['team_name']}</b>", cell_text), Paragraph("Stage", cell_bold), Paragraph(proj['event_or_stage'], cell_text)],
            [Paragraph("Scheduled Date", cell_bold), Paragraph(f"{proj['date']} ({proj['time']})", cell_text), Paragraph("Venue / Room", cell_bold), Paragraph(proj['room'], cell_text)],
            [Paragraph("Project Adviser", cell_bold), Paragraph(proj['adviser'], cell_text), Paragraph("Defense Chair", cell_bold), Paragraph(proj['chair'], cell_text)],
            [Paragraph("Panel Member", cell_bold), Paragraph(proj['panelist'], cell_text), Paragraph("Documenter", cell_bold), Paragraph(proj['documenter'], cell_text)],
            [Paragraph("Team Members", cell_bold), Paragraph(", ".join(proj['members']), cell_text), Paragraph("Technology Stack", cell_bold), Paragraph(proj['stack'], cell_text)],
        ]
    else:
        # PIT: Progressive milestone exhibitions (no documenter, course instructor & evaluators)
        metadata_data = [
            [Paragraph("Project ID", cell_bold), Paragraph(proj['id'], cell_text), Paragraph("Track & Level", cell_bold), Paragraph(f"{proj['track']} — {proj['year_level']}", cell_text)],
            [Paragraph("Team Name", cell_bold), Paragraph(f"<b>{proj['team_name']}</b>", cell_text), Paragraph("Event Milestone", cell_bold), Paragraph(proj['event_or_stage'], cell_text)],
            [Paragraph("Event Date", cell_bold), Paragraph(f"{proj['date']} ({proj['time']})", cell_text), Paragraph("Venue / Room", cell_bold), Paragraph(proj['room'], cell_text)],
            [Paragraph("Course Instructor", cell_bold), Paragraph(proj['adviser'], cell_text), Paragraph("Lead Evaluator", cell_bold), Paragraph(proj['chair'], cell_text)],
            [Paragraph("Panel Evaluator", cell_bold), Paragraph(proj['panelist'], cell_text), Paragraph("Evaluation Track", cell_bold), Paragraph("Rubric-Based Milestone Review", cell_text)],
            [Paragraph("Team Members", cell_bold), Paragraph(", ".join(proj['members']), cell_text), Paragraph("Technology Stack", cell_bold), Paragraph(proj['stack'], cell_text)],
        ]
    meta_table = Table(metadata_data, colWidths=[90, 180, 100, 170])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC')),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor('#CBD5E1')),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
        ('PADDING', (0,0), (-1,-1), 3.5),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 8))

    # 4. DELIVERABLE ARTIFACT DETAILS
    story.append(Paragraph("1. Deliverable Description & Objectives", section_h1))
    story.append(Paragraph(description, body_style))
    if is_capstone:
        desc_footer = (
            f"This academic deliverable represents an authentic verified artifact for <b>{proj['team_name']}</b> "
            f"defending the project <i>{proj['title']}</i> under the Capstone defense pipeline of the USTP Department of Information Technology. "
            f"It verifies tribunal compliance and formal defense verdict requirements."
        )
    else:
        desc_footer = (
            f"This academic deliverable represents an authentic verified artifact for <b>{proj['team_name']}</b> "
            f"presenting the project <i>{proj['title']}</i> under the Project in IT (PIT) milestone curriculum of the USTP Department of Information Technology. "
            f"It records formative rubric feedback and iterative project revisions without terminal defense verdicts."
        )
    story.append(Paragraph(desc_footer, body_style))

    story.append(Paragraph("2. Technical Scope & System Functional Modules", section_h1))
    modules_text = (
        f"• <b>{proj['module_1_name']}:</b> {proj['module_1_desc']}<br/>"
        f"• <b>{proj['module_2_name']}:</b> {proj['module_2_desc']}<br/>"
        f"• <b>{proj['module_3_name']}:</b> {proj['module_3_desc']}"
    )
    story.append(Paragraph(modules_text, body_style))

    story.append(Paragraph("3. Tech Stack & Environmental Specifications", section_h1))
    spec_text = (
        f"• <b>Frontend Interface:</b> {proj['frontend_tech']}<br/>"
        f"• <b>Backend Application Kernel:</b> {proj['backend_tech']}<br/>"
        f"• <b>Database & Persistence Engine:</b> {proj['database_tech']}<br/>"
        f"• <b>Domain Specialization Area:</b> {proj['domain']} &nbsp;|&nbsp; <b>Prerequisite Course:</b> {proj['prereq_course']}"
    )
    story.append(Paragraph(spec_text, body_style))
    story.append(Spacer(1, 4))

    # 5. STATUS BANNER
    if is_capstone:
        is_approved = ("APPROVED" in verdict_text or "PASSED" in verdict_text or "CLEARED" in verdict_text)
        bg_color = colors.HexColor('#ECFDF5') if is_approved else colors.HexColor('#F0F9FF')
        border_color = colors.HexColor('#A7F3D0') if is_approved else colors.HexColor('#BAE6FD')
        banner_title = "OFFICIAL DEFENSE VERDICT"
    else:
        is_revision = ("REVISION" in verdict_text or "REMEDIAT" in verdict_text or "PLAN" in verdict_text or "ARTIFACT" in verdict_text)
        bg_color = colors.HexColor('#F0FDF4') if is_revision else colors.HexColor('#EEF2FF')
        border_color = colors.HexColor('#BBF7D0') if is_revision else colors.HexColor('#C7D2FE')
        banner_title = "MILESTONE STATUS"
    
    verdict_table = Table([[Paragraph(f"<b>{banner_title}:</b> {verdict_text}", verdict_style)]], colWidths=[540])
    verdict_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), bg_color),
        ('BOX', (0,0), (-1,-1), 1.2, border_color),
        ('PADDING', (0,0), (-1,-1), 6),
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
    ]))
    story.append(verdict_table)
    story.append(Spacer(1, 10))

    # 6. OFFICIAL SIGNATURES & ENDORSEMENT BLOCK
    story.append(Paragraph("Official Endorsements & Committee Signatures", section_h1))
    if is_capstone:
        sig_data = [
            [
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
            ],
            [
                Paragraph(f"<b>{proj['members'][0]}</b><br/>Student Team Lead", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
                Paragraph(f"<b>{proj['adviser']}</b><br/>Project Adviser", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
                Paragraph(f"<b>{proj['chair']}</b><br/>Defense Panel Chair", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
                Paragraph(f"<b>{proj['documenter']}</b><br/>Secretariat / Documenter", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
            ]
        ]
    else:
        sig_data = [
            [
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
                Paragraph(f"_____________________________", ParagraphStyle('SigLine', parent=styles['Normal'], alignment=1, fontSize=8)),
            ],
            [
                Paragraph(f"<b>{proj['members'][0]}</b><br/>Student Team Lead", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
                Paragraph(f"<b>{proj['adviser']}</b><br/>Course Instructor / Lead", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
                Paragraph(f"<b>{proj['chair']}</b><br/>Lead Faculty Evaluator", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
                Paragraph(f"<b>{proj['panelist']}</b><br/>Panel Evaluator", ParagraphStyle('SigRole', parent=styles['Normal'], alignment=1, fontSize=7.5, textColor=colors.HexColor('#334155'))),
            ]
        ]
    sig_table = Table(sig_data, colWidths=[135, 135, 135, 135])
    sig_table.setStyle(TableStyle([
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
        ('PADDING', (0,0), (-1,-1), 2),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
    ]))
    story.append(sig_table)

    doc.build(story)


def main():
    workspace_root = r"c:\Users\Admin\Desktop\DefenSYS"
    all_projects = get_all_projects()

    print("================================================================================")
    print(f"GENERATING DELIVERABLE ARTIFACTS FOR {len(all_projects)} PROJECT SESSIONS")
    print("================================================================================\n")

    created_count = 0

    for idx, proj in enumerate(all_projects, start=1):
        target_dir = get_target_dir(workspace_root, proj)
        pre_dir = os.path.join(target_dir, "Pre_Deliverables")
        post_dir = os.path.join(target_dir, "Post_Deliverables")
        os.makedirs(pre_dir, exist_ok=True)
        os.makedirs(post_dir, exist_ok=True)

        specs = get_event_deliverable_specs(proj['event_or_stage'], proj['track'])
        pre1, pre2, post1, post2 = specs

        yl_clean = sanitize_filename(proj['year_level'])
        sem_clean = sanitize_filename(proj['semester'])
        team_clean = sanitize_filename(proj['team_name'])
        stage_clean = sanitize_filename(proj['event_or_stage'])

        # Filename templates (optimized to stay well within Windows 260-char MAX_PATH limit for browser uploads)
        deliverables_to_generate = [
            (os.path.join(pre_dir, f"{team_clean}_PRE1_{pre1[1]}.pdf"), pre1),
            (os.path.join(pre_dir, f"{team_clean}_PRE2_{pre2[1]}.pdf"), pre2),
            (os.path.join(post_dir, f"{team_clean}_POST1_{post1[1]}.pdf"), post1),
            (os.path.join(post_dir, f"{team_clean}_POST2_{post2[1]}.pdf"), post2),
        ]

        for full_path, spec in deliverables_to_generate:
            generate_deliverable_pdf(full_path, proj, spec)
            created_count += 1

        print(f"[{idx:2d}/{len(all_projects)}] Generated 4 deliverables for {proj['team_name']} ({proj['event_or_stage']}) in {os.path.basename(target_dir)}")

    print(f"\n[SUCCESS] Successfully generated {created_count} authentic deliverable PDF artifacts in sample_file/Project_Manuscripts/!")


if __name__ == "__main__":
    main()
