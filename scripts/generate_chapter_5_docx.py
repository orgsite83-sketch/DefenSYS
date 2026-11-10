import os
import docx
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_chapter_5_document(output_path):
    doc = docx.Document()
    
    # Configure Page Setup (USTP Standard Thesis Margins)
    section = doc.sections[0]
    section.top_margin = Inches(1.0)
    section.bottom_margin = Inches(1.0)
    section.left_margin = Inches(1.5)
    section.right_margin = Inches(1.0)
    section.page_width = Inches(8.5)
    section.page_height = Inches(11.0)
    
    # Chapter Header
    p_chap = doc.add_paragraph()
    p_chap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_chap.paragraph_format.space_before = Pt(0)
    p_chap.paragraph_format.space_after = Pt(6)
    p_chap.paragraph_format.line_spacing = 1.0
    r_chap = p_chap.add_run("CHAPTER V")
    r_chap.font.name = "Times New Roman"
    r_chap.font.size = Pt(14)
    r_chap.font.bold = True
    
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.space_before = Pt(0)
    p_title.paragraph_format.space_after = Pt(18)
    p_title.paragraph_format.line_spacing = 1.0
    r_title = p_title.add_run("CONCLUSIONS AND RECOMMENDATIONS")
    r_title.font.name = "Times New Roman"
    r_title.font.size = Pt(14)
    r_title.font.bold = True
    
    def add_h1(text):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.space_before = Pt(14)
        p.paragraph_format.space_after = Pt(6)
        p.paragraph_format.line_spacing = 1.15
        p.paragraph_format.first_line_indent = Inches(0)
        r = p.add_run(text)
        r.font.name = "Times New Roman"
        r.font.size = Pt(12.5)
        r.font.bold = True
        return p

    def add_h2(text):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.space_before = Pt(10)
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.line_spacing = 1.15
        p.paragraph_format.first_line_indent = Inches(0)
        r = p.add_run(text)
        r.font.name = "Times New Roman"
        r.font.size = Pt(12)
        r.font.bold = True
        return p

    def add_body(text, indent=True):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(6)
        p.paragraph_format.line_spacing = 1.5
        if indent:
            p.paragraph_format.first_line_indent = Inches(0.5)
        else:
            p.paragraph_format.first_line_indent = Inches(0)
        r = p.add_run(text)
        r.font.name = "Times New Roman"
        r.font.size = Pt(12)
        return p

    def add_numbered_item(number_str, lead_bold, text):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.space_before = Pt(4)
        p.paragraph_format.space_after = Pt(6)
        p.paragraph_format.line_spacing = 1.5
        p.paragraph_format.left_indent = Inches(0.5)
        p.paragraph_format.first_line_indent = Inches(-0.5)
        
        r_num = p.add_run(number_str + " ")
        r_num.font.name = "Times New Roman"
        r_num.font.size = Pt(12)
        r_num.font.bold = True
        
        r_b = p.add_run(lead_bold + " ")
        r_b.font.name = "Times New Roman"
        r_b.font.size = Pt(12)
        r_b.font.bold = True
        
        r_t = p.add_run(text)
        r_t.font.name = "Times New Roman"
        r_t.font.size = Pt(12)
        return p

    # --- 5.1 CONCLUSION ---
    add_h1("5.1 Conclusion")
    add_body(
        "Based on the empirical findings, quantitative statistical treatments, and user acceptance testing of "
        "DefenSYS: A Cross-Platform Capstone and PIT Management System with Secure Archiving and Curriculum Analytics, "
        "the study successfully accomplished its general objective of designing, developing, and evaluating a unified, secure "
        "platform for the Department of Information Technology at the University of Science and Technology of Southern Philippines "
        "(USTP) – Oroquieta Campus. The platform achieved an overall Software Quality Grand Mean of 4.65 (SD = 0.42), interpreted as "
        "Highly Acceptable (Strongly Agree) based on the ISO/IEC 25010:2011 product quality standard, with an overwhelming 96.97% overall "
        "system acceptance rate across all 15 key departmental stakeholders. Specifically, the following conclusions are established "
        "relative to the four research problems and specific objectives:"
    )

    add_body(
        "1. Elimination of Grading Inefficiencies and Guaranteed Score Immutability: The hybrid Web and Mobile Evaluation Engine "
        "conclusively proves that dual grading workflows can be executed synchronously without computational latency or transcription "
        "errors. By automating multi-tier Capstone weighted formulas (Panelist, Adviser, and Peer) and event-configured PIT weighted "
        "scores (Panelist and Peer), the platform eliminates the disjointed reliance on physical paper rubrics and standalone spreadsheets. "
        "Furthermore, the database-level Grade Lock mechanism guarantees absolute score immutability upon submission, ensuring data integrity "
        "and preventing post-defense tampering."
    )

    add_body(
        "2. Resolution of Archival and Retrieval Bottlenecks for ISO Accreditation: The automated two-stage deliverable ingestion pipeline "
        "conclusively resolves historical document disorganization. The server-side Regular Expression (Regex) validation gatekeeper, coupled "
        "with dynamic template resolution, standardizes student deliverable filenames into institutional conventions without causing submission "
        "rejections. Concurrently, the automated Readiness Gatekeeper ensures that only teams with complete, verified stage deliverables are "
        "cleared for defense scheduling. This establishes a structured, standardized, and ISO-audit-ready repository that eliminates manual "
        "end-of-semester sorting."
    )

    add_body(
        "3. Robust Intellectual Property Protection and Enforcement of Physical Library Usage: The platform's security architecture "
        "effectively protects student intellectual property from unauthorized extraction and AI-assisted plagiarism while maintaining academic "
        "accessibility. By enforcing Role-Based Visibility Filtering, student browsing is strictly restricted to stage-specific deliverables "
        "(e.g., approved PIT papers, concept proposals, and presentation media summaries), whereas full-length manuscripts are reserved exclusively "
        "for authorized faculty and administrators. Additionally, client-side dynamic watermarking—which overlays the viewer's authenticated user ID, "
        "name, and timestamp across rendered documents—acts as an unalterable deterrent against unauthorized reproduction, successfully upholding the "
        "department's mandate requiring students to visit the physical library for complete manuscript reference."
    )

    add_body(
        "4. Transition to Empirical, Data-Driven Curriculum Development: The integration of the Natural Language Processing (NLP) classification "
        "pipeline (TF-IDF feature extraction and Multinomial Naive Bayes) conclusively proves that institutional archives can autonomously power "
        "academic decision-making. Achieving an empirical classification accuracy of 92.00% and a Macro F1-Score of 92.96% across departmental manuscripts, "
        "the classifier accurately routes documents into seven core technology domains without human intervention. By feeding these thematic distributions "
        "directly into the Curriculum Analytics Decision Support System (DSS), the system equips the Department Chairman with empirical, longitudinal "
        "data on student technology trends, shifting curriculum planning from observational guesswork to verifiable evidence."
    )

    # --- 5.2 RECOMMENDATIONS ---
    add_h1("5.2 Recommendations")
    add_body(
        "In strict alignment with the evaluation outcomes and operational requirements of the Department of Information Technology, the researchers "
        "formulate the following three (3) consolidated, high-impact recommendations to guide institutional policy, operational workflows, and future "
        "technical development:"
    )

    add_numbered_item(
        "1.",
        "Formal Institutional Rollout and Policy Mandate for Academic Administration and ISO Accreditation:",
        "It is strongly recommended that the Department of Information Technology at USTP – Oroquieta Campus officially institutionalize DefenSYS "
        "as the mandatory platform for all Capstone and Project Integration Technology (PIT) courses across all year levels, completely replacing "
        "paper-based rubrics and disconnected spreadsheets. Department leadership should formally incorporate the Curriculum Analytics Decision Support "
        "System (DSS) into the biannual curriculum review process, utilizing empirical student technology trends to guide faculty specializations, "
        "introduce relevant elective offerings (such as edge IoT and modern cross-platform development), and allocate laboratory funding. Furthermore, "
        "the standardized repository, immutable audit logs, and locked grade registries should be designated as the authoritative documentary evidence base "
        "for institutional ISO accreditation and CHED quality assurance audits."
    )

    add_numbered_item(
        "2.",
        "Operational Workflow Adherence and Stakeholder Compliance across Faculty, Students, and Documenters:",
        "Academic stakeholders must strictly adhere to the integrated platform workflows to maintain system data integrity. PIT Leads and Instructors "
        "should configure academic terms, rosters, and event rubrics within the first two weeks of classes and utilize centralized queues to verify deliverable "
        "milestones prior to defense endorsement. Defense Panelists and Panel Chairs should conduct live scoring exclusively through the mobile interface "
        "to enable instantaneous grade consolidation and immediate verdict formalization under the Grade Lock mechanism. Defense Documenters should utilize "
        "the live transcription workspace to record panel remarks under specific panelist accounts and secure required digital signatures during the hearing. "
        "Finally, students must observe submission deadlines and respect intellectual property protocols by utilizing the watermarked repository strictly "
        "for ideation while consulting the physical library for complete manuscripts."
    )

    add_numbered_item(
        "3.",
        "Technical Infrastructure Enhancement, Offline Synchronization, and Institutional System Integration:",
        "For future researchers and software engineers enhancing the platform, it is recommended to implement an offline-first synchronization "
        "architecture utilizing local client-side caching (e.g., SQLite or Hive) on mobile evaluation devices. This will allow uninterrupted rubric scoring "
        "during transient campus Wi-Fi drops, automatically synchronizing with the PostgreSQL database upon reconnect. Additionally, the NLP classification "
        "pipeline should be upgraded by fine-tuning contextual transformer models (such as SciBERT or distilled Large Language Models) on expanded multi-campus "
        "manuscript datasets to eliminate boundary misclassifications between overlapping domains (e.g., Data Analytics and Machine Learning). Lastly, the system "
        "should be integrated with the university's central Learning Management System (via LTI standards) and campus-wide Single Sign-On (SSO) infrastructure, "
        "complemented by internal static code quality and similarity analysis modules."
    )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    doc.save(output_path)
    print(f"Successfully generated updated Chapter 5 Word document at: {output_path}")

if __name__ == "__main__":
    out_file = r"outputs\Chapter_5_Conclusions_and_Recommendations.docx"
    create_chapter_5_document(out_file)
