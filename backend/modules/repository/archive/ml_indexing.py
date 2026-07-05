"""Apply pdfplumber + TF-IDF + Naive Bayes fields to a VaultEntry instance."""


def apply_ml_from_pdf(entry, *, force: bool = False) -> bool:
    if not entry.file:
        return False
    if entry.extracted_text and not force:
        return False

    from repository.deliverables.pdf_processor import extract_pdf_from_file_object

    try:
        with entry.file.open('rb') as stored:
            result = extract_pdf_from_file_object(
                stored,
                entry.file.name or entry.file_name,
                classify=True,
            )
    except Exception as exc:
        print(f'Warning: PDF extraction failed for {entry.file_name}: {exc}')
        return False

    entry.extracted_text = result.get('text', '') or ''
    entry.topics = result.get('topics', []) or []
    entry.summary = result.get('summary', '') or ''
    entry.category = result.get('category', '') or ''
    classification = result.get('classification') or {}
    confidence = result.get('confidence_score')
    if confidence is None and classification:
        confidence = classification.get('confidence_score')
    entry.category_confidence = confidence
    return True
