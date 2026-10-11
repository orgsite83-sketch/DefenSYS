import csv
import io
import os
import base64
import json
import math
import textwrap
from datetime import datetime
from django.http import HttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.response import Response

try:
    import openpyxl
    from openpyxl.styles import Font, Alignment, Border, Side
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.hyperlink import Hyperlink
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


def _write_xlsx_sheet(wb, title, metadata, columns, rows, *, name, generated_by='', table_only=False):
    """Fit each sheet once, keeping data rows sortable and dates typed."""
    ws = wb.create_sheet(name)
    ws.views.sheetView[0].showGridLines = False

    # Determine widths before writing so headers and wrapped rows can be fitted.
    for col_idx, col in enumerate(columns, start=1):
        lengths = [len(col['label'])]
        lengths.extend(max((len(line) for line in str(row.get(col['key'], '') or '').splitlines()), default=0) for row in rows)
        ws.column_dimensions[get_column_letter(col_idx)].width = col.get('width', min(max(max(lengths) + 3, 16), 46))
    
    # Neutral report typography: plain white cells and bold black headings.
    inst_header_font = Font(name="Calibri", size=13, bold=True, color="000000")
    inst_dept_font = Font(name="Calibri", size=11, bold=True, color="1E293B")
    inst_sub_font = Font(name="Calibri", size=9, italic=True, color="64748B")
    title_font = Font(name="Calibri", size=13, bold=True, color="000000")
    subtitle_font = Font(name="Calibri", size=9.5, italic=True, color="64748B")
    
    meta_label_font = Font(name="Calibri", size=9.5, bold=True, color="1E293B")
    meta_val_font = Font(name="Calibri", size=9.5, color="334155")
    header_font = Font(name="Calibri", size=11, bold=True, color="000000")
    cell_font = Font(name="Calibri", size=11, color="000000")
    
    thin_border = Border(
        left=Side(style='thin', color='000000' if table_only else 'E2E8F0'),
        right=Side(style='thin', color='000000' if table_only else 'E2E8F0'),
        top=Side(style='thin', color='000000' if table_only else 'E2E8F0'),
        bottom=Side(style='thin', color='000000' if table_only else 'E2E8F0'),
    )

    current_row = 1
    if not table_only:
        current_row = 2
        # Official header and context belong above ordinary reports.
        for value, font in (
            ('REPUBLIC OF THE PHILIPPINES', inst_sub_font),
            ('UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES', inst_header_font),
            ('Department of Information Technology — Oroquieta Campus', inst_dept_font),
            ('P-6, Mobod, Oroquieta City, Misamis Occidental 7207 • Email: ustporoquieta.bsit@ustp.edu.ph', inst_sub_font),
        ):
            ws.cell(current_row, 1, value).font = font
            current_row += 1
        current_row += 1
        ws.cell(current_row, 1, f'DEFENSYS — {title.upper()}').font = title_font
        current_row += 1
        ws.cell(current_row, 1, f"Generated {timezone.localtime().strftime('%Y-%m-%d %H:%M %Z')}" + (f' · By {generated_by}' if generated_by else '')).font = subtitle_font
        current_row += 2
        for row_num in (2, 3, 4, 5, 7, 8):
            if len(columns) > 1:
                ws.merge_cells(start_row=row_num, start_column=1, end_row=row_num, end_column=len(columns))
            ws.cell(row_num, 1).alignment = Alignment(vertical='center')
            ws.row_dimensions[row_num].height = 22
        if metadata:
            for item in metadata:
                cell = ws.cell(current_row, 1, f"{item.get('label', '')}: {item.get('value', '')}")
                cell.font = meta_label_font
                cell.alignment = Alignment(vertical='center', wrap_text=True)
                if len(columns) > 1:
                    ws.merge_cells(start_row=current_row, start_column=1, end_row=current_row, end_column=len(columns))
                ws.row_dimensions[current_row].height = 22
                current_row += 1
            current_row += 1
        
    # 4. Table Column Headers
    header_row_idx = current_row
    for col_idx, col in enumerate(columns, start=1):
        cell = ws.cell(row=header_row_idx, column=col_idx, value=col['label'])
        cell.font = header_font
        cell.alignment = Alignment(horizontal="left" if table_only else "center", vertical="center", wrap_text=True)
        cell.border = thin_border
    ws.row_dimensions[header_row_idx].height = 30 if table_only else 36
    current_row += 1
    
    # 5. Data Rows
    for r_idx, row in enumerate(rows):
        row_num = current_row + r_idx
        row_lines = 1
        
        for col_idx, col in enumerate(columns, start=1):
            key = col['key']
            val = row.get(key, '')
            if isinstance(val, (dict, list)):
                val = json.dumps(val, ensure_ascii=False, default=str)
            if col.get('type') == 'datetime' and val:
                parsed = val if isinstance(val, datetime) else parse_datetime(str(val))
                if parsed is not None:
                    val = timezone.localtime(parsed).replace(tzinfo=None) if timezone.is_aware(parsed) else parsed
                
            cell = ws.cell(row=row_num, column=col_idx, value=val)
            # Audit text is data, including text beginning with '='.
            if isinstance(val, str):
                cell.data_type = 's'
            if isinstance(val, datetime):
                cell.number_format = col.get('number_format', 'yyyy-mm-dd hh:mm')
            cell.font = cell_font
            cell.border = thin_border
            align = col.get('align', 'left')
            cell.alignment = Alignment(horizontal=align, vertical="top", wrap_text=True)
            width = max(8, int(ws.column_dimensions[get_column_letter(col_idx)].width - 2))
            display = val.strftime('%Y-%m-%d %H:%M') if isinstance(val, datetime) else str(val if val is not None else '')
            line_count = sum(max(1, len(textwrap.wrap(line, width=width, replace_whitespace=False))) for line in display.split('\n'))
            row_lines = max(row_lines, line_count)
        ws.row_dimensions[row_num].height = min(409, max(21 if table_only else 24, row_lines * 15 + (6 if table_only else 9)))
            
    last_col = get_column_letter(len(columns))
    last_row = header_row_idx + len(rows)
    ws.freeze_panes = f'{"C" if len(columns) > 2 else "A"}{header_row_idx + 1}'
    ws.auto_filter.ref = f'A{header_row_idx}:{last_col}{last_row}'
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.sheet_view.zoomScale = 100 if table_only else 90
    ws.print_options.horizontalCentered = True
    ws.page_setup.orientation = 'landscape' if len(columns) > 5 else 'portrait'
    ws.page_setup.paperSize = ws.PAPERSIZE_A3 if len(columns) > 10 else ws.PAPERSIZE_A4
    # Wide registers remain readable on paper by using horizontal pages.
    ws.page_setup.fitToWidth = max(1, math.ceil(sum(dim.width for dim in ws.column_dimensions.values()) / 190))
    ws.page_setup.fitToHeight = 0
    ws.print_title_rows = f'{header_row_idx}:{header_row_idx}'
    ws.print_area = f'A{1 if table_only else 2}:{last_col}{last_row}'
    ws.oddFooter.center.text = 'DefenSYS | Page &P of &N'
    ws.oddFooter.right.text = 'Confidential'
    if not rows:
        ws.cell(header_row_idx + 1, 1, 'No records match the selected filters.').font = meta_val_font
        ws.row_dimensions[header_row_idx + 1].height = 24
        ws.print_area = f'A{1 if table_only else 2}:{last_col}{header_row_idx + 1}'

    return ws


def _write_xlsx_signatories(ws, signatories, generated_by, *, table_only=False):
    """Place signing space below the data without extending the filter range."""
    if signatories and isinstance(signatories, list):
        signers = [s for s in signatories if isinstance(s, dict) and any(s.get(key) for key in ('label', 'name', 'role'))]
    else:
        signers = [
            {'label': 'Prepared by:', 'name': generated_by, 'role': 'Academic Documenter / Evaluator'},
            {'label': 'Noted by:', 'name': '', 'role': 'Project Adviser / Panel Chair'},
            {'label': 'Approved by:', 'name': 'IT Program Chairperson', 'role': 'IT Program Chairperson'},
        ]
    if not signers:
        return

    last_column = min(2, ws.max_column)
    width = max(8, int(sum(ws.column_dimensions[get_column_letter(col)].width for col in range(1, last_column + 1)) - 2))
    next_row = ws.max_row + 3
    for signer in signers:
        for offset, key, bold in ((0, 'label', False), (2, 'name', True), (3, 'role', False)):
            value = str(signer.get(key) or ('Signed by:' if key == 'label' else '')).strip()
            row = next_row + offset
            if last_column > 1:
                ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=last_column)
            cell = ws.cell(row, 1, value)
            cell.data_type = 's'
            cell.font = Font(name='Calibri', size=11, bold=bold, color='000000')
            cell.alignment = Alignment(vertical='top', wrap_text=True)
            lines = sum(max(1, len(textwrap.wrap(line, width=width))) for line in value.split('\n'))
            ws.row_dimensions[row].height = min(409, max(21, lines * 15 + 6))
            if key == 'name':
                for col in range(1, last_column + 1):
                    ws.cell(row, col).border = Border(top=Side(style='thin', color='000000'))
        ws.row_dimensions[next_row + 1].height = 24
        next_row += 5

    first_row = 1 if table_only else 2
    ws.print_area = f'A{first_row}:{get_column_letter(ws.max_column)}{ws.max_row}'


def generate_xlsx_response(title, metadata, columns, rows, filename, *, extra_sheets=None, generated_by='', sheet_name='Report Data', table_only=False, include_signatures=False, signatories=None):
    """Generate a fitted register with optional evidence/history sheets."""
    if not HAS_OPENPYXL:
        return generate_csv_response(columns, rows, filename.replace('.xlsx', '.csv'))
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    wb.properties.title = title
    if generated_by:
        wb.properties.creator = generated_by
    register = _write_xlsx_sheet(wb, title, metadata, columns, rows, name=sheet_name, generated_by=generated_by, table_only=table_only)
    if include_signatures:
        _write_xlsx_signatories(register, signatories, generated_by, table_only=table_only)
    references = {}
    for spec in extra_sheets or []:
        sheet = _write_xlsx_sheet(wb, spec['title'], spec.get('metadata', []), spec['columns'], spec['rows'], name=spec['name'], generated_by=generated_by)
        if spec.get('link_key'):
            first_data_row = int(sheet.auto_filter.ref.split(':')[0][1:]) + 1
            locations = {}
            for index, row in enumerate(spec['rows'], start=first_data_row):
                locations.setdefault(row[spec['link_key']], index)
            references[spec['name']] = (spec['link_key'], locations)
    first_data_row = int(register.auto_filter.ref.split(':')[0][1:]) + 1
    for column_index, column in enumerate(columns, start=1):
        sheet_name = column.get('link_to')
        if sheet_name not in references:
            continue
        key, locations = references[sheet_name]
        for row_index, row in enumerate(rows, start=first_data_row):
            location = locations.get(row.get(key))
            if location is not None:
                cell = register.cell(row_index, column_index)
                escaped_name = sheet_name.replace("'", "''")
                cell.hyperlink = Hyperlink(ref=cell.coordinate, location=f"'{escaped_name}'!A{location}")
        
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


def handle_export_or_preview(export_format, title, subtitle, summary_kpis, metadata, columns, rows, filename, pdf_generator_func, sections=None, generated_by='admin', *, include_signatures=False, signatories=None):
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
        return generate_xlsx_response(title, metadata, columns, rows, filename,
                                      generated_by=generated_by, include_signatures=include_signatures, signatories=signatories)
    elif fmt in ('doc', 'docx', 'word'):
        return generate_doc_response(title, metadata, columns, rows, filename)
    else:
        pdf_data = pdf_generator_func()
        if not filename.endswith('.pdf'):
            filename = f"{filename}.pdf"
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response
