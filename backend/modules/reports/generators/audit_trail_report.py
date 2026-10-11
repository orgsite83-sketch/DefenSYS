from reportlab.lib.units import inch
from xml.sax.saxutils import escape
from django.utils import timezone
import json
from authentication_access_control.audit import audit_evidence
from authentication_access_control.audit_references import AuditReferenceResolver
from reports.pdf_builder import DefensysPdfReportBuilder
from reports.export_formatters import generate_xlsx_response, HAS_OPENPYXL


def _evidence_text(value):
    if isinstance(value, str) and value:
        return value
    return json.dumps(value, ensure_ascii=False, default=str)


def generate_audit_trail_xlsx(logs, title, metadata, columns, rows, filename, generated_by, *, include_signatures=False, signatories=None):
    """Keep the register compact; retain complete snapshots and review decisions."""
    if not HAS_OPENPYXL:
        return generate_xlsx_response(title, metadata, columns, rows, filename)
    evidence_rows = []
    history_rows = []
    register_rows = []
    chunk_size = 1000  # Fitted rows stay within Excel's maximum row height.
    reference_resolver = AuditReferenceResolver(logs)
    for log, row in zip(logs, rows):
        before = log.old_values if isinstance(log.old_values, dict) else {}
        after = log.new_values if isinstance(log.new_values, dict) else {}
        display_before = reference_resolver.display_values(log, 'old_values')
        display_after = reference_resolver.display_values(log, 'new_values')
        values = [
            (key, _evidence_text(display_before[key]) if key in before else 'Not recorded',
             _evidence_text(display_after[key]) if key in after else 'Not recorded',
             _evidence_text(before[key]) if key in before else 'Not recorded',
             _evidence_text(after[key]) if key in after else 'Not recorded')
            for key in dict.fromkeys([*before, *after])
        ]
        if log.reason:
            values.append(('Action reason', 'Not applicable', log.reason, 'Not applicable', log.reason))
        for key, old_text, new_text, raw_old, raw_new in values:
            parts = max(1, (max(map(len, (old_text, new_text, raw_old, raw_new))) + chunk_size - 1) // chunk_size)
            for part in range(parts):
                evidence_rows.append({
                    'event_id': log.pk, 'action': log.action, 'field': key, 'part': part + 1,
                    'timestamp': row['created_at'], 'target': row['target'],
                    'before': old_text[part * chunk_size:(part + 1) * chunk_size],
                    'after': new_text[part * chunk_size:(part + 1) * chunk_size],
                    'raw_before': raw_old[part * chunk_size:(part + 1) * chunk_size],
                    'raw_after': raw_new[part * chunk_size:(part + 1) * chunk_size],
                })
        reviews = list(log.reviews.all())
        for review in reviews:
            note = review.reason or 'No review note recorded'
            for part in range(max(1, (len(note) + chunk_size - 1) // chunk_size)):
                history_rows.append({
                    'event_id': log.pk, 'review_id': review.pk, 'created_at': review.created_at,
                    'event_timestamp': row['created_at'], 'target': row['target'],
                    'reviewer': review.reviewer_name or 'Reviewer not recorded',
                    'role': ('PIT Lead - ' + review.reviewer_year) if review.reviewer_role == 'pit_lead' else ('Admin' if review.reviewer_role == 'admin' else 'Not recorded'),
                    'from_status': review.get_from_status_display(),
                    'to_status': review.get_to_status_display(), 'part': part + 1,
                    'note': note[part * chunk_size:(part + 1) * chunk_size],
                })
        register = dict(row)
        register['review_history'] = f'{len(reviews)} decision(s) - see Review History' if reviews else 'No review history recorded'
        if len(register['reason']) > 500:
            register['reason'] = register['reason'][:500] + '\n[Full reason in Event Evidence]'
        register_rows.append(register)
    supporting_sheets = [
        {
            'name': 'Event Evidence', 'title': 'Recorded event evidence',
            'link_key': 'event_id',
            'metadata': [*metadata, {'label': 'Reading values', 'value': 'Not recorded = absent from snapshot; null = recorded empty value. Parts continue in order for the same event and field.'}],
            'columns': [
                {'key': 'timestamp', 'label': 'Timestamp', 'width': 23, 'type': 'datetime', 'number_format': 'm/d/yyyy hh:mm'},
                {'key': 'target', 'label': 'Target Entity', 'width': 25},
                {'key': 'action', 'label': 'Action', 'width': 30},
                {'key': 'field', 'label': 'Recorded Field', 'width': 26},
                {'key': 'part', 'label': 'Part', 'width': 10, 'align': 'right'},
                {'key': 'before', 'label': 'Before', 'width': 66},
                {'key': 'after', 'label': 'After', 'width': 66},
                {'key': 'raw_before', 'label': 'Raw Before', 'width': 44},
                {'key': 'raw_after', 'label': 'Raw After', 'width': 44},
            ], 'rows': evidence_rows,
        },
        {
            'name': 'Review History', 'title': 'Recorded review decisions',
            'link_key': 'event_id',
            'metadata': [{'label': 'Review record', 'value': 'One entry per recorded decision; long notes continue in numbered parts. Missing historical reviewers are not inferred.'}],
            'columns': [
                {'key': 'event_timestamp', 'label': 'Timestamp', 'width': 23, 'type': 'datetime', 'number_format': 'm/d/yyyy hh:mm'},
                {'key': 'target', 'label': 'Target Entity', 'width': 25},
                {'key': 'created_at', 'label': 'Decision Timestamp', 'width': 23, 'type': 'datetime', 'number_format': 'm/d/yyyy hh:mm'},
                {'key': 'reviewer', 'label': 'Reviewer', 'width': 25},
                {'key': 'role', 'label': 'Reviewer Role', 'width': 22},
                {'key': 'from_status', 'label': 'Previous Status', 'width': 22},
                {'key': 'to_status', 'label': 'Decision', 'width': 22},
                {'key': 'part', 'label': 'Note Part', 'width': 10, 'align': 'right'},
                {'key': 'note', 'label': 'Review Note', 'width': 70},
            ], 'rows': history_rows,
        },
    ]
    return generate_xlsx_response(title, metadata, columns, register_rows, filename,
                                  extra_sheets=supporting_sheets, generated_by=generated_by, sheet_name='Audit Register', table_only=True,
                                  include_signatures=include_signatures, signatories=signatories)


def generate_audit_trail_pdf(logs, filters_desc, generated_by_user, signatories=None, include_signatures=False):
    """
    Generate an official USTP DIT PDF audit trail compilation for official ISO compliance monitoring.
    """
    builder = DefensysPdfReportBuilder(
        title="ISO 9001:2015 System Audit Trail Register",
        subtitle="Official Security Governance, Access Integrity & System Action Audit Logs",
        generated_by=generated_by_user,
    )

    total_logs = len(logs)

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Compliance Standard", "ISO 9001:2015 Quality Management System (Clause 9.2 Audit Log)"),
        ("Total Audit Log Records", f"{total_logs} Log Entries Captured"),
        ("Review Tracking", "Evidence capture and human review are tracked separately; missing attribution is identified"),
    ]
    if filters_desc:
        for k, v in filters_desc.items():
            metadata_rows.append((f"Active Filter ({k})", str(v)))

    builder.add_metadata_grid(metadata_rows)

    # 3. Main Log Table
    builder.add_section_header("System Compliance Action Logs")

    headers = [
        "Date / Time",
        "Process Area",
        "Control Activity",
        "Responsible User",
        "Action Details & Review Evidence",
    ]

    rows = []
    reference_resolver = AuditReferenceResolver(logs)
    for log in logs:
        time_str = timezone.localtime(log.created_at).strftime('%Y-%m-%d %H:%M %Z') if log.created_at else ""

        actor_name = log.actor_name if hasattr(log, 'actor_name') else ""
        if not actor_name and log.actor:
            actor_name = log.actor.get_full_name() or log.actor.username
        if not actor_name:
            actor_name = "System"

        category_lbl = log.category_label if hasattr(log, 'category_label') else (dict(log.CATEGORY_CHOICES).get(log.category, log.category))
        evidence = audit_evidence(log)
        reason = log.reason or ('Reason required - not recorded' if evidence['reason_required'] else 'Not required for this event')
        detail_reason = f"<b>Event:</b> #{log.pk} - {escape(reference_resolver.target_label(log))}"
        detail_reason += f"<br/><b>Evidence:</b> {escape(evidence['label'])}"
        detail_reason += f"<br/>{escape(evidence['summary'])}"
        detail_reason += f"<br/><b>Reason:</b> {escape(reason)}"
        detail_reason += f"<br/><b>Review:</b> {'Reviewed' if log.review_status == 'reviewed' else 'Pending review'}"
        if log.reviewed_by_name:
            role = f'PIT Lead · {log.reviewed_by_year}' if log.reviewed_by_role == 'pit_lead' else ('Admin' if log.reviewed_by_role == 'admin' else 'Role not recorded')
            detail_reason += f"<br/><b>Last reviewed by:</b> {escape(log.reviewed_by_name)} ({escape(role)})"
        elif log.review_status == 'reviewed':
            detail_reason += '<br/>Reviewer not recorded'
        if log.reviewed_at:
            detail_reason += f"<br/>{timezone.localtime(log.reviewed_at).strftime('%Y-%m-%d %H:%M %Z')}"
        rows.append([
            time_str,
            category_lbl or "",
            log.action or "",
            escape(actor_name),
            detail_reason,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.0 * inch, 1.1 * inch, 1.2 * inch, 1.1 * inch, 2.0 * inch],
        bold_cols=[3],
        repeat_headers=True,
    )

    # History flows as paragraphs so long review notes can continue onto another page.
    reviewed_logs = [log for log in logs if log.reviews.all()]
    if reviewed_logs:
        builder.add_section_header('Review Decision History')
        for log in reviewed_logs:
            builder.add_subsection_header(f'Event #{log.pk} - {escape(log.action)}')
            for review in reversed(list(log.reviews.all())):
                if review.to_status == 'reviewed':
                    decision = 'Reviewed'
                elif review.from_status == 'reviewed':
                    decision = 'Reopened for review'
                else:
                    decision = review.get_to_status_display()
                role = f'PIT Lead - {review.reviewer_year}' if review.reviewer_role == 'pit_lead' else ('Admin' if review.reviewer_role == 'admin' else 'Role not recorded')
                timestamp = timezone.localtime(review.created_at).strftime('%Y-%m-%d %H:%M %Z')
                builder.add_paragraph(
                    f'<b>{escape(decision)}</b> by {escape(review.reviewer_name)} '
                    f'({escape(role)}) - {timestamp}',
                )
                if review.reason:
                    builder.add_paragraph(escape(review.reason))
                builder.add_spacer(0.06)

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Compliance Officer / System Admin",
        noted_by="Quality Management Officer",
        noted_role="Quality Assurance Coordinator",
        approved_by="IT Program Chairperson / Dean",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
