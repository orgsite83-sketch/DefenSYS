from io import BytesIO
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib import colors

from reports.pdf_styles import (
    defensys_styles,
    defensys_cover_page,
    defensys_table_style,
    NumberedCanvas,
    MAROON,
    GOLD,
    BORDER_GREY,
    BG_LIGHT,
    TEXT_DARK
)


def generate_user_directory_pdf(users, generated_by_user):
    """
    Generate a PDF user account directory.
    
    Args:
        users: QuerySet of User objects
        generated_by_user: Username of requestor
        
    Returns:
        bytes: PDF binary content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.85*inch,
        bottomMargin=0.85*inch,
        leftMargin=0.5*inch,
        rightMargin=0.5*inch
    )
    
    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')
    
    story = []
    styles = defensys_styles()
    
    # 1. Cover Page
    total_users = len(users)
    metadata_rows = [
        ("Total Registered Users:", str(total_users)),
    ]
    
    defensys_cover_page(
        story=story,
        title="User Account Directory",
        subtitle="Active DefenSYS Portal Accounts List",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows
    )
    
    # 2. Main Title
    story.append(Paragraph("DefenSYS Portal User Accounts", styles['SectionHeader']))
    story.append(Spacer(1, 0.05*inch))
    
    # 3. Directory Table
    headers = [
        Paragraph("<b>Username</b>", styles['TableHeader']),
        Paragraph("<b>Full Name</b>", styles['TableHeader']),
        Paragraph("<b>Email Address</b>", styles['TableHeader']),
        Paragraph("<b>Role / Type</b>", styles['TableHeader']),
        Paragraph("<b>Status</b>", styles['TableHeader']),
    ]
    
    table_rows = [headers]
    for user in users:
        fullname = user.get_full_name() or f"{user.first_name} {user.last_name}".strip()
        if not fullname:
            fullname = "N/A"
            
        role_label = str(user.role).capitalize() if getattr(user, 'role', None) else "User"
        
        # Display other sub-roles
        sub_roles = []
        if getattr(user, 'is_pit_lead', False):
            sub_roles.append("PIT Lead")
        if getattr(user, 'is_uploader', False):
            sub_roles.append("Doc Uploader")
        if getattr(user, 'is_panelist', False):
            sub_roles.append("Panelist")
            
        if sub_roles:
            role_label = f"{role_label} ({', '.join(sub_roles)})"
            
        status_label = "ACTIVE" if user.is_active else "INACTIVE"
        
        table_rows.append([
            Paragraph(user.username, styles['TableCellBold']),
            Paragraph(fullname, styles['TableCell']),
            Paragraph(user.email or "No Email", styles['TableCell']),
            Paragraph(role_label, styles['TableCell']),
            Paragraph(status_label, styles['TableCellBold'])
        ])
        
    dir_table = Table(table_rows, colWidths=[1.3*inch, 1.8*inch, 2.2*inch, 1.4*inch, 0.8*inch])
    dir_table.setStyle(defensys_table_style())
    story.append(dir_table)
    
    # 4. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
