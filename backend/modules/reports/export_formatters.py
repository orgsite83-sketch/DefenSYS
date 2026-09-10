import csv
import io
import os
import base64
from datetime import datetime
from django.http import HttpResponse
from rest_framework.response import Response

try:
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.utils import get_column_letter
    HAS_OPENPYXL = True
except ImportError:
    HAS_OPENPYXL = False


def _find_header_image_base64():
    """
    Returns base64 data URI of the official template header image (image003.png) if available.
    """
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    candidates = [
        os.path.join(base_dir, 'modules', 'reports', 'assets', 'image003.png'),
        os.path.join(base_dir, 'static', 'template', 'image003.png'),
        os.path.join(base_dir, '..', 'frontend', 'assets', 'template', 'Minutes-Defense-TEMPLATE_files', 'image003.png'),
    ]
    for p in candidates:
        abs_p = os.path.abspath(p)
        if os.path.exists(abs_p):
            try:
                with open(abs_p, 'rb') as f:
                    encoded = base64.b64encode(f.read()).decode('utf-8')
                    return f"data:image/png;base64,{encoded}"
            except Exception:
                pass
    return None


def build_preview_response(title, subtitle, summary_kpis, metadata, columns, rows, sections=None, generated_by='admin', pdf_base64=None):
    """
    Builds a JSON payload for the in-app Live Data Viewer and Document Sheet preview.
    """
    payload = {
        'title': title,
        'subtitle': subtitle,
        'generated_by': generated_by or 'admin',
        'generated_at': datetime.now().strftime('%Y-%m-%d %I:%M %p'),
        'summary_kpis': summary_kpis,
        'metadata': metadata,
        'columns': columns,
        'rows': rows,
        'total_rows': len(rows),
    }
    if sections is not None:
        payload['sections'] = sections
    if pdf_base64 is not None:
        payload['pdf_base64'] = pdf_base64
    return Response(payload)


def generate_csv_response(columns, rows, filename):
    """
    Generates an RFC-4180 compliant CSV download with UTF-8 BOM encoding for Excel compatibility.
    """
    output = io.StringIO()
    output.write('\ufeff')
    
    fieldnames = [col['key'] for col in columns]
    header_labels = {col['key']: col['label'] for col in columns}
    
    writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction='ignore')
    writer.writerow(header_labels)
    
    for row in rows:
        cleaned_row = {}
        for key in fieldnames:
            val = row.get(key, '')
            if val is None:
                cleaned_row[key] = ''
            elif isinstance(val, (dict, list)):
                cleaned_row[key] = str(val)
            else:
                cleaned_row[key] = str(val)
        writer.writerow(cleaned_row)
        
    csv_bytes = output.getvalue().encode('utf-8-sig')
    
    if not filename.endswith('.csv'):
        filename = f"{filename}.csv"
        
    response = HttpResponse(csv_bytes, content_type='text/csv; charset=utf-8')
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    return response


def generate_xlsx_response(title, metadata, columns, rows, filename):
    """
    Generates a professionally styled Excel workbook (.xlsx) matching the institutional USTP template.
    """
    if not HAS_OPENPYXL:
        return generate_csv_response(columns, rows, filename.replace('.xlsx', '.csv'))
        
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Report Data"
    ws.views.sheetView[0].showGridLines = True
    
    # Fonts & Colors
    maroon_fill = PatternFill(start_color="7A110A", end_color="7A110A", fill_type="solid")
    gold_fill = PatternFill(start_color="D4A843", end_color="D4A843", fill_type="solid")
    meta_bg = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")
    
    inst_header_font = Font(name="Calibri", size=13, bold=True, color="7A110A")
    inst_dept_font = Font(name="Calibri", size=11, bold=True, color="1E293B")
    inst_sub_font = Font(name="Calibri", size=9, italic=True, color="64748B")
    title_font = Font(name="Calibri", size=13, bold=True, color="7A110A")
    subtitle_font = Font(name="Calibri", size=9.5, italic=True, color="64748B")
    
    meta_label_font = Font(name="Calibri", size=9.5, bold=True, color="1E293B")
    meta_val_font = Font(name="Calibri", size=9.5, color="334155")
    header_font = Font(name="Calibri", size=10, bold=True, color="FFFFFF")
    cell_font = Font(name="Calibri", size=9.5, color="1E293B")
    sig_title_font = Font(name="Calibri", size=9.5, bold=True, color="1E293B")
    sig_role_font = Font(name="Calibri", size=8.5, color="64748B")
    
    thin_border = Border(
        left=Side(style='thin', color='E2E8F0'),
        right=Side(style='thin', color='E2E8F0'),
        top=Side(style='thin', color='E2E8F0'),
        bottom=Side(style='thin', color='E2E8F0'),
    )
    top_line_border = Border(top=Side(style='medium', color='1E293B'))
    
    current_row = 1
    
    # 1. Official Institutional Header Block
    ws.cell(row=current_row, column=1, value="REPUBLIC OF THE PHILIPPINES").font = inst_sub_font
    current_row += 1
    ws.cell(row=current_row, column=1, value="UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES").font = inst_header_font
    current_row += 1
    ws.cell(row=current_row, column=1, value="Department of Information Technology — Oroquieta Campus").font = inst_dept_font
    current_row += 1
    ws.cell(row=current_row, column=1, value="P-6, Mobod, Oroquieta City, Misamis Occidental 7207 • Email: ustporoquieta.bsit@ustp.edu.ph").font = inst_sub_font
    current_row += 2
    
    # 2. Document Title
    ws.cell(row=current_row, column=1, value=f"DEFENSYS — {title.upper()}").font = title_font
    current_row += 1
    ws.cell(row=current_row, column=1, value=f"Official Academic Record · Generated on {datetime.now().strftime('%Y-%m-%d %I:%M %p')}").font = subtitle_font
    current_row += 2
    
    # 3. Metadata Grid
    if metadata:
        for item in metadata:
            label = item.get('label', '')
            val = item.get('value', '')
            c_label = ws.cell(row=current_row, column=1, value=f"{label}:")
            c_label.font = meta_label_font
            c_val = ws.cell(row=current_row, column=2, value=str(val))
            c_val.font = meta_val_font
            current_row += 1
        current_row += 1
        
    # 4. Table Column Headers
    header_row_idx = current_row
    for col_idx, col in enumerate(columns, start=1):
        cell = ws.cell(row=header_row_idx, column=col_idx, value=col['label'])
        cell.font = header_font
        cell.fill = maroon_fill
        cell.alignment = Alignment(horizontal="center" if col.get('align') == 'center' else "left", vertical="center")
        cell.border = thin_border
    ws.row_dimensions[header_row_idx].height = 24
    current_row += 1
    
    # 5. Data Rows
    stripe_fill = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")
    for r_idx, row in enumerate(rows):
        is_stripe = (r_idx % 2 == 1)
        row_num = current_row + r_idx
        ws.row_dimensions[row_num].height = 19
        
        for col_idx, col in enumerate(columns, start=1):
            key = col['key']
            val = row.get(key, '')
            if isinstance(val, (dict, list)):
                val = str(val)
                
            cell = ws.cell(row=row_num, column=col_idx, value=val)
            cell.font = cell_font
            cell.border = thin_border
            if is_stripe:
                cell.fill = stripe_fill
            align = col.get('align', 'left')
            cell.alignment = Alignment(horizontal=align, vertical="center")
            
    current_row += len(rows) + 2
    
    # 6. Signatures Block
    ws.cell(row=current_row, column=1, value="Prepared by:").font = sig_role_font
    if len(columns) >= 3:
        mid_col = max(2, len(columns) // 2)
        ws.cell(row=current_row, column=mid_col, value="Noted by:").font = sig_role_font
        ws.cell(row=current_row, column=len(columns), value="Approved by:").font = sig_role_font
    current_row += 3
    
    c_p = ws.cell(row=current_row, column=1, value="System Administrator")
    c_p.font = sig_title_font
    c_p.border = top_line_border
    if len(columns) >= 3:
        mid_col = max(2, len(columns) // 2)
        c_n = ws.cell(row=current_row, column=mid_col, value="Capstone Adviser / Panel Chair")
        c_n.font = sig_title_font
        c_n.border = top_line_border
        c_a = ws.cell(row=current_row, column=len(columns), value="IT Program Chairperson")
        c_a.font = sig_title_font
        c_a.border = top_line_border
        
    current_row += 1
    ws.cell(row=current_row, column=1, value="Documenter / Evaluator").font = sig_role_font
    if len(columns) >= 3:
        mid_col = max(2, len(columns) // 2)
        ws.cell(row=current_row, column=mid_col, value="Capstone Adviser").font = sig_role_font
        ws.cell(row=current_row, column=len(columns), value="IT Program Chairperson").font = sig_role_font
        
    # Auto-fit Column Widths
    for col_idx, col in enumerate(columns, start=1):
        col_letter = get_column_letter(col_idx)
        max_len = len(col['label'])
        for row in rows:
            val_str = str(row.get(col['key'], ''))
            if len(val_str) > max_len:
                max_len = len(val_str)
        ws.column_dimensions[col_letter].width = min(max(max_len + 4, 14), 45)
        
    output = io.BytesIO()
    wb.save(output)
    output.seek(0)
    
    if not filename.endswith('.xlsx'):
        filename = f"{filename}.xlsx"
        
    response = HttpResponse(
        output.getvalue(),
        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    return response


def generate_doc_response(title, metadata, columns, rows, filename):
    """
    Generates a Microsoft Word compatible document (.doc) matching the official USTP template.
    """
    header_img_src = _find_header_image_base64()
    
    html_parts = [
        '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">',
        '<head><meta charset="utf-8">',
        '<style>',
        'body { font-family: "Calibri", "Arial", sans-serif; font-size: 10pt; color: #1E293B; margin: 30px; }',
        '.header-banner { width: 100%; max-height: 120px; object-fit: contain; margin-bottom: 8px; }',
        '.inst-title { text-align: center; font-size: 13pt; font-weight: bold; color: #7A110A; margin: 0; }',
        '.inst-dept { text-align: center; font-size: 11pt; font-weight: bold; color: #1E293B; margin: 2px 0; }',
        '.inst-sub { text-align: center; font-size: 8.5pt; color: #64748B; margin-bottom: 12px; }',
        '.doc-title { text-align: center; font-size: 14pt; font-weight: bold; color: #7A110A; margin-top: 10px; margin-bottom: 2px; }',
        '.doc-subtitle { text-align: center; font-size: 9.5pt; color: #64748B; margin-bottom: 16px; font-style: italic; }',
        '.meta-table { margin-bottom: 16px; border-collapse: collapse; width: 100%; background-color: #F8FAFC; border: 1px solid #E2E8F0; }',
        '.meta-table td { padding: 4px 8px; font-size: 9pt; border-bottom: 1px solid #E2E8F0; }',
        '.meta-label { font-weight: bold; color: #1E293B; width: 220px; }',
        '.data-table { border-collapse: collapse; width: 100%; margin-top: 10px; }',
        '.data-table th { background-color: #7A110A; color: #ffffff; font-weight: bold; padding: 6px 8px; font-size: 9pt; border: 1px solid #7A110A; }',
        '.data-table td { padding: 5px 8px; font-size: 8.5pt; border: 1px solid #E2E8F0; }',
        '.data-table tr:nth-child(even) { background-color: #F8FAFC; }',
        '.cert-box { margin-top: 18px; padding: 8px 12px; border: 1px solid #1E293B; background-color: #F8FAFC; font-size: 8.5pt; font-style: italic; }',
        '.sig-table { width: 100%; margin-top: 25px; border-collapse: collapse; }',
        '.sig-table td { text-align: center; vertical-align: top; width: 33.3%; padding: 0 10px; font-size: 9pt; }',
        '.sig-line { border-top: 1px solid #1E293B; margin-top: 35px; padding-top: 3px; font-weight: bold; }',
        '.sig-role { font-size: 8pt; color: #64748B; margin-top: 2px; }',
        '.footer-note { margin-top: 30px; font-size: 8pt; color: #94A3B8; font-style: italic; border-top: 1px solid #E2E8F0; padding-top: 6px; }',
        '</style></head><body>',
    ]
    
    if header_img_src:
        html_parts.append(f'<img src="{header_img_src}" class="header-banner" alt="USTP Department of Information Technology Header"/>')
    else:
        html_parts.append('<div class="inst-title">UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES</div>')
        html_parts.append('<div class="inst-dept">Department of Information Technology — Oroquieta Campus</div>')
        html_parts.append('<div class="inst-sub">P-6, Mobod, Oroquieta City, Misamis Occidental 7207 • ustporoquieta.bsit@ustp.edu.ph</div>')
        
    html_parts.append(f'<div class="doc-title">{title.upper()}</div>')
    html_parts.append(f'<div class="doc-subtitle">Official Defense Deliberation & Academic Grading Registry · {datetime.now().strftime("%B %d, %Y at %I:%M %p")}</div>')
    
    if metadata:
        html_parts.append('<table class="meta-table">')
        for item in metadata:
            label = item.get('label', '')
            val = item.get('value', '')
            html_parts.append(f'<tr><td class="meta-label">{label}:</td><td>{val}</td></tr>')
        html_parts.append('</table>')
        
    html_parts.append('<table class="data-table">')
    html_parts.append('<tr>')
    for col in columns:
        align = col.get('align', 'left')
        html_parts.append(f'<th style="text-align: {align};">{col["label"]}</th>')
    html_parts.append('</tr>')
    
    for row in rows:
        html_parts.append('<tr>')
        for col in columns:
            key = col['key']
            val = row.get(key, '')
            if val is None:
                val = ''
            align = col.get('align', 'left')
            html_parts.append(f'<td style="text-align: {align};">{val}</td>')
        html_parts.append('</tr>')
        
    html_parts.append('</table>')
    
    # Certification & Signatures
    html_parts.append(
        '<div class="cert-box">I hereby certify that the above statements and computational evaluation scores are true and correct to the best of my ability, and I further certify the official accuracy of the foregoing academic defense records.</div>'
    )
    html_parts.append('<table class="sig-table"><tr>')
    html_parts.append('<td>Prepared by:<div class="sig-line">System Administrator</div><div class="sig-role">Documenter / Evaluator</div></td>')
    html_parts.append('<td>Noted by:<div class="sig-line">Capstone Adviser / Panel Chair</div><div class="sig-role">Project Adviser</div></td>')
    html_parts.append('<td>Approved by:<div class="sig-line">IT Program Chairperson</div><div class="sig-role">Department Chairperson</div></td>')
    html_parts.append('</tr></table>')
    
    html_parts.append(f'<div class="footer-note">Confidential Institutional Document — Generated automatically via DefenSYS Academic Audit & Compliance Center on {datetime.now().strftime("%Y-%m-%d %I:%M %p")}</div>')
    html_parts.append('</body></html>')
    
    doc_content = '\n'.join(html_parts).encode('utf-8')
    
    if not filename.endswith('.doc') and not filename.endswith('.docx'):
        filename = f"{filename}.doc"
        
    response = HttpResponse(doc_content, content_type='application/msword')
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    return response


def handle_export_or_preview(export_format, title, subtitle, summary_kpis, metadata, columns, rows, filename, pdf_generator_func, sections=None, generated_by='admin'):
    """
    Unified dispatcher to handle json/preview, csv, xlsx, doc, and pdf exports.
    """
    fmt = (export_format or 'pdf').lower().strip()
    
    if fmt in ('json', 'preview', 'data'):
        pdf_b64 = None
        if pdf_generator_func:
            try:
                raw_pdf = pdf_generator_func()
                if raw_pdf:
                    pdf_b64 = base64.b64encode(raw_pdf).decode('utf-8')
            except Exception:
                pass
        return build_preview_response(
            title, subtitle, summary_kpis, metadata, columns, rows,
            sections=sections, generated_by=generated_by, pdf_base64=pdf_b64,
        )
    elif fmt == 'csv':
        return generate_csv_response(columns, rows, filename)
    elif fmt in ('xlsx', 'excel', 'sheet'):
        return generate_xlsx_response(title, metadata, columns, rows, filename)
    elif fmt in ('doc', 'docx', 'word'):
        return generate_doc_response(title, metadata, columns, rows, filename)
    else:
        pdf_data = pdf_generator_func()
        if not filename.endswith('.pdf'):
            filename = f"{filename}.pdf"
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response
