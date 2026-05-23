"""
PDF Generator for Weekly Progress Reports Compilation
"""
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from io import BytesIO
from datetime import datetime


def generate_weekly_reports_pdf(team, reports):
    """
    Generate PDF compilation of weekly progress reports
    
    Args:
        team: StudentTeam object
        reports: QuerySet of WeeklyProgressReport objects
        
    Returns:
        bytes: PDF content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.5*inch,
        bottomMargin=0.5*inch,
        leftMargin=0.75*inch,
        rightMargin=0.75*inch
    )
    story = []
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=20,
        textColor=colors.HexColor('#7F1D1D'),
        spaceAfter=30,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold',
    )
    
    subtitle_style = ParagraphStyle(
        'Subtitle',
        parent=styles['Normal'],
        fontSize=12,
        alignment=TA_CENTER,
        spaceAfter=6,
    )
    
    # Cover Page
    story.append(Spacer(1, 1.5*inch))
    story.append(Paragraph('WEEKLY PROGRESS REPORTS', title_style))
    story.append(Paragraph('COMPILATION', title_style))
    story.append(Spacer(1, 0.5*inch))
    
    # Team Information
    cover_data = [
        ['Team Name:', team.name or 'N/A'],
        ['Project Title:', team.project_title or 'N/A'],
        ['Year Level:', team.year_level or 'N/A'],
        ['Adviser:', team.adviser.get_full_name() if team.adviser else 'N/A'],
        ['Total Weeks:', str(len(reports))],
        ['Compilation Date:', datetime.now().strftime('%B %d, %Y')],
    ]
    
    cover_table = Table(cover_data, colWidths=[2*inch, 4.5*inch])
    cover_table.setStyle(TableStyle([
        ('FONT', (0, 0), (-1, -1), 'Helvetica', 11),
        ('FONT', (0, 0), (0, -1), 'Helvetica-Bold', 11),
        ('ALIGN', (0, 0), (0, -1), 'RIGHT'),
        ('ALIGN', (1, 0), (1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
        ('TOPPADDING', (0, 0), (-1, -1), 10),
    ]))
    
    story.append(cover_table)
    story.append(PageBreak())
    
    # Process each week
    for idx, report in enumerate(reports):
        # Week Header
        week_title = Paragraph(
            f'<b>WEEK {report.week_number}</b> - {report.report_date}',
            styles['Heading1']
        )
        story.append(week_title)
        story.append(Spacer(1, 0.15*inch))
        
        # Submission Info
        student_name = report.student.get_full_name() if report.student else "Unknown"
        info_text = f'<i>Submitted by: {student_name} on {report.submitted_at.strftime("%B %d, %Y %I:%M %p") if report.submitted_at else "N/A"}</i>'
        story.append(Paragraph(info_text, styles['Normal']))
        story.append(Spacer(1, 0.2*inch))
        
        # Check if this is a file-based report or legacy JSON report
        if report.report_file:
            # File-based report (new method)
            story.append(Paragraph('<b>REPORT FILE</b>', styles['Heading2']))
            story.append(Spacer(1, 0.1*inch))
            
            file_info = [
                ['File Name:', report.report_file],
                ['File Size:', report.file_size or 'N/A'],
            ]
            
            file_table = Table(file_info, colWidths=[1.5*inch, 4.5*inch])
            file_table.setStyle(TableStyle([
                ('FONT', (0, 0), (-1, -1), 'Helvetica', 10),
                ('FONT', (0, 0), (0, -1), 'Helvetica-Bold', 10),
                ('ALIGN', (0, 0), (0, -1), 'RIGHT'),
                ('ALIGN', (1, 0), (1, -1), 'LEFT'),
                ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                ('TOPPADDING', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
            ]))
            story.append(file_table)
            story.append(Spacer(1, 0.2*inch))
            
            note_text = '<i>Note: This is a file-based submission. The actual report file should be downloaded separately from the system.</i>'
            story.append(Paragraph(note_text, styles['Normal']))
            
        else:
            # Legacy JSON report (old method)
            # Accomplishments
            story.append(Paragraph('<b>ACCOMPLISHMENTS FOR THE WEEK</b>', styles['Heading2']))
            story.append(Spacer(1, 0.1*inch))
            
            if report.accomplishments and len(report.accomplishments) > 0:
                acc_data = [['Task/Activity', 'Description', 'Output/Evidence']]
                for acc in report.accomplishments:
                    acc_data.append([
                        Paragraph(acc.get('task', 'N/A'), styles['Normal']),
                        Paragraph(acc.get('description', 'N/A'), styles['Normal']),
                        Paragraph('Attached', styles['Normal'])
                    ])
                
                acc_table = Table(acc_data, colWidths=[1.8*inch, 2.7*inch, 1.5*inch])
                acc_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#7F1D1D')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                    ('TOPPADDING', (0, 0), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ]))
                story.append(acc_table)
            else:
                story.append(Paragraph('<i>No accomplishments recorded.</i>', styles['Normal']))
            
            story.append(Spacer(1, 0.2*inch))
            
            # Individual Contributions
            story.append(Paragraph('<b>INDIVIDUAL CONTRIBUTIONS</b>', styles['Heading2']))
            story.append(Spacer(1, 0.1*inch))
            
            if report.contributions and len(report.contributions) > 0:
                cont_data = [['Team Member', 'Contribution']]
                for cont in report.contributions:
                    cont_data.append([
                        Paragraph(cont.get('member', 'N/A'), styles['Normal']),
                        Paragraph(cont.get('contribution', 'N/A'), styles['Normal'])
                    ])
                
                cont_table = Table(cont_data, colWidths=[2*inch, 4*inch])
                cont_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#7F1D1D')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                    ('TOPPADDING', (0, 0), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ]))
                story.append(cont_table)
            else:
                story.append(Paragraph('<i>No contributions recorded.</i>', styles['Normal']))
            
            story.append(Spacer(1, 0.2*inch))
            
            # Issues Encountered
            story.append(Paragraph('<b>ISSUES ENCOUNTERED AND ACTIONS TAKEN</b>', styles['Heading2']))
            story.append(Spacer(1, 0.1*inch))
            
            if report.issues and len(report.issues) > 0:
                issue_data = [['Issue/Concern', 'Action Taken/Resolution']]
                for issue in report.issues:
                    issue_data.append([
                        Paragraph(issue.get('issue', 'N/A'), styles['Normal']),
                        Paragraph(issue.get('action', 'N/A'), styles['Normal'])
                    ])
                
                issue_table = Table(issue_data, colWidths=[3*inch, 3*inch])
                issue_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#7F1D1D')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                    ('TOPPADDING', (0, 0), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ]))
                story.append(issue_table)
            else:
                story.append(Paragraph('<i>No issues recorded.</i>', styles['Normal']))
            
            story.append(Spacer(1, 0.2*inch))
            
            # Plans for Next Week
            story.append(Paragraph('<b>PLAN FOR NEXT WEEK</b>', styles['Heading2']))
            story.append(Spacer(1, 0.1*inch))
            
            if report.plans and len(report.plans) > 0:
                plan_data = [['Planned Task', 'Expected Output']]
                for plan in report.plans:
                    plan_data.append([
                        Paragraph(plan.get('task', 'N/A'), styles['Normal']),
                        Paragraph(plan.get('output', 'N/A'), styles['Normal'])
                    ])
                
                plan_table = Table(plan_data, colWidths=[3*inch, 3*inch])
                plan_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#7F1D1D')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
                    ('TOPPADDING', (0, 0), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ]))
                story.append(plan_table)
            else:
                story.append(Paragraph('<i>No plans recorded.</i>', styles['Normal']))
        
        # Add page break after each week except the last one
        if idx < len(reports) - 1:
            story.append(PageBreak())
    
    # Build PDF
    doc.build(story)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
