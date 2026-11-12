"""Reviewed, project-level evaluation; no model persistence or database writes.

Rules and raw NB suggestions are diagnostics alongside the accepted NB result.
An abstention or processing failure stays in the accuracy denominator.
"""
from collections import Counter, defaultdict
import hashlib
import json
from math import sqrt
from pathlib import Path
import re

from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

from .classification_taxonomy import TRAINING_EXAMPLES
from .project_classification import FEATURE_VERSION


STUDY_LABELS = (
    'Web Development', 'Mobile Development', 'Machine Learning', 'IoT',
    'Information Systems', 'Data Science', 'Cybersecurity',
)
LABEL_ALIASES = {
    'Mobile Application': 'Mobile Development', 'Internet of Things': 'IoT',
    'Internet of Things (IoT)': 'IoT', 'Data Analytics': 'Data Science',
}
UNRESOLVED = 'Unresolved'
OUTSIDE = 'Out of taxonomy'


def _text_hash(text):
    return hashlib.sha256(' '.join(text.casefold().split()).encode('utf-8')).hexdigest()


def source_documents(row):
    """Keep revision boundaries; never concatenate PDFs into one prediction."""
    if 'documents' in row:
        if not isinstance(row['documents'], list) or any(
                not isinstance(d, dict) or not isinstance(d.get('text'), str) for d in row['documents']):
            raise ValueError('Export documents must be a list of source records with text.')
        return [dict(source, _raw_text=source['text'], display_name=source.get('display_name', source.get('label', 'Project manuscript')))
                for source in row['documents']]
    if not row.get('sources'):
        return [dict(id=row['project_id'], label='Project manuscript', display_name='Project manuscript',
                     uploaded_at='', _raw_text=row['text'])]
    sources, text = row['sources'], row['text']
    lengths = [source['extracted_characters'] for source in sources]
    if all(length == len(text) for length in lengths):
        texts = [text] * len(sources)
    elif sum(lengths) + 2 * (len(lengths) - 1) == len(text):
        texts, start = [], 0
        for length in lengths:
            texts.append(text[start:start + length])
            start += length
            if start < len(text):
                if text[start:start + 2] != '\n\n':
                    raise ValueError('Legacy source separator mismatch: ' + row['project_id'])
                start += 2
    else:
        raise ValueError('Re-export this project with individual document texts; legacy source lengths do not agree: ' + row['project_id'])
    return [dict(source, _raw_text=value, display_name=source['label'],
                 uploaded_at='', _legacy_order=int(source['id'].split(':')[-1]))
            for source, value in zip(sources, texts)]


def source_priority(document, prediction):
    return (bool(re.search(r'proposal|manuscript|final paper|concept', document.get('label', ''), re.I)),
            document.get('uploaded_at', ''), document.get('_legacy_order', 0),
            prediction.get('confidence_score') or 0)


def project_prediction(model, documents, *, fallback):
    results = []
    for document in documents:
        try:
            result = model.predict(document['_raw_text'], allow_function_fallback=fallback)
        except Exception as error:
            result = dict(status='unresolved', predicted_category='Other', reason_code='processing_error',
                          error_type=type(error).__name__, top_3=[], decision_method='processing_error', confidence_score=None)
        results.append((document, result))
    usable = [(d, r) for d, r in results if r['status'] == 'estimated']
    if usable:
        source, result = max(usable, key=lambda pair: source_priority(*pair))
    else:
        source, result = max(results, key=lambda pair: pair[1].get('confidence_score') or 0)
    return dict(result, selected_source_id=source.get('id'))


def reviewed_dataset(path):
    records = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(records, list) or not records:
        raise ValueError('Dataset must contain reviewed, labelled project records.')
    families, texts, project_labels, projects = (defaultdict(set) for _ in range(4))
    for record in records:
        if (not isinstance(record, dict) or record.get('reviewed') is not True or
                not isinstance(record.get('project_id'), str) or not record['project_id'] or
                not isinstance(record.get('text'), str) or not isinstance(record.get('label'), str) or not record['label']):
            raise ValueError('Every record needs project_id, text, label and reviewed=true. Empty test text is retained as an extraction failure.')
        if record.get('split') not in ('train', 'test'):
            raise ValueError('Every record needs an explicit train or test split.')
        record['label'] = LABEL_ALIASES.get(record['label'], record['label'])
        if record['label'] not in TRAINING_EXAMPLES:
            raise ValueError('Unknown computing-focus label: ' + str(record['label']))
        family = str(record.get('project_family_id') or record['project_id'])
        families[family].add(record['split'])
        projects[record['project_id']].add(record['split'])
        project_labels[record['project_id']].add(record['label'])
        sources = source_documents(record)
        readable = [source['_raw_text'] for source in sources if source['_raw_text'].strip()]
        for text in readable:
            texts[_text_hash(text)].add(record['split'])
        if not readable and record['split'] == 'train':
            raise ValueError('Training records must have readable text; test extraction failures remain eligible.')
    if any(len(splits) != 1 for splits in families.values()) or any(len(splits) != 1 for splits in projects.values()):
        raise ValueError('Versions from one project family cannot appear in both training and testing.')
    if any(len(splits) != 1 for splits in texts.values()):
        raise ValueError('Duplicate manuscript text cannot appear in both training and testing.')
    if any(len(labels) != 1 for labels in project_labels.values()):
        raise ValueError('A project must have one reviewed primary computing focus.')
    return records


def _accepted(result, labels):
    if result['status'] != 'estimated':
        return UNRESOLVED
    label = result['predicted_category']
    return label if label in labels else OUTSIDE


def _metrics(actual, predicted, labels):
    accepted = [i for i, label in enumerate(predicted) if label not in (UNRESOLVED, OUTSIDE)]
    correct = sum(a == p for a, p in zip(actual, predicted))
    count = len(actual)
    accuracy = float(accuracy_score(actual, predicted))
    # Wilson interval illustrates the uncertainty of a small project sample.
    z = 1.959963984540054
    denominator = 1 + z * z / count
    center = (accuracy + z * z / (2 * count)) / denominator
    half = z * sqrt(accuracy * (1 - accuracy) / count + z * z / (4 * count * count)) / denominator
    matrix_labels = list(labels) + [UNRESOLVED, OUTSIDE]
    return dict(eligible_projects=count, correct_projects=correct, accuracy=accuracy,
                accuracy_percent=round(100 * accuracy, 2),
                accuracy_interval_95=[round(max(0, center - half), 4), round(min(1, center + half), 4)],
                accepted_projects=len(accepted), accepted_coverage=len(accepted) / count,
                accepted_precision=(sum(actual[i] == predicted[i] for i in accepted) / len(accepted)
                                    if accepted else None),
                unresolved_projects=predicted.count(UNRESOLVED), outside_taxonomy_projects=predicted.count(OUTSIDE),
                confusion_matrix_labels=matrix_labels,
                confusion_matrix=confusion_matrix(actual, predicted, labels=matrix_labels).tolist(),
                per_theme=classification_report(actual, predicted, labels=list(labels), output_dict=True, zero_division=0))


def evaluate_projects(model, records, *, labels=STUDY_LABELS, target_accuracy=0.92):
    if not 0 < target_accuracy <= 1:
        raise ValueError('Target accuracy must be greater than zero and at most one.')
    grouped = defaultdict(list)
    for record in records:
        if record['split'] == 'test':
            if record['label'] not in labels:
                raise ValueError('Reviewed test labels fall outside the selected taxonomy. Do not silently exclude projects.')
            grouped[record['project_id']].append(record)
    if not grouped:
        raise ValueError('At least one independently reviewed test project is required.')
    actual, ml, raw, hybrid, ledger = [], [], [], [], []
    for project_id, documents in sorted(grouped.items()):
        expected = {record['label'] for record in documents}
        if len(expected) != 1:
            raise ValueError('A project must have one reviewed primary computing focus.')
        sources = [source for record in documents for source in source_documents(record)]
        sources = list({_text_hash(s['_raw_text']): s for s in sources}.values())
        if not sources:
            sources = [dict(id=project_id, label='', uploaded_at='', _raw_text='')]
        text = '\n\n'.join(source['_raw_text'] for source in sources)
        predictions = {}
        for name, fallback in (('naive_bayes', False), ('hybrid', True)):
            predictions[name] = project_prediction(model, sources, fallback=fallback)
        nb, combined = predictions['naive_bayes'], predictions['hybrid']
        best = nb.get('top_3', [{}])[0] if nb.get('top_3') else {}
        raw_label = best.get('category', UNRESOLVED)
        actual.append(next(iter(expected)))
        ml.append(_accepted(nb, labels))
        hybrid.append(_accepted(combined, labels))
        raw.append(raw_label if raw_label in labels or raw_label == UNRESOLVED else OUTSIDE)
        ledger.append(dict(project_id=project_id, expected=actual[-1], input_hash=_text_hash(text),
                           extraction='readable' if len(''.join(text.split())) >= 40 else 'missing_or_unreadable',
                           naive_bayes=ml[-1], naive_bayes_reason=nb['reason_code'],
                           naive_bayes_source=nb.get('selected_source_id'),
                           naive_bayes_error=nb.get('error_type'),
                           raw_candidate=raw[-1], raw_candidate_score=best.get('probability'),
                           hybrid=hybrid[-1], hybrid_method=combined.get('decision_method'),
                           hybrid_source=combined.get('selected_source_id'),
                           hybrid_error=combined.get('error_type'),
                           hybrid_reason=combined['reason_code']))
    primary = _metrics(actual, ml, labels)
    primary.update(target_accuracy=target_accuracy, meets_target=primary['accuracy'] >= target_accuracy,
                   study_minimum_accuracy=0.85, meets_study_minimum=primary['accuracy'] >= 0.85,
                   abstention_reasons=dict(Counter(row['naive_bayes_reason'] for row in ledger
                                                  if row['naive_bayes'] == UNRESOLVED)))
    return dict(model_version=model.model_version, feature_version=FEATURE_VERSION, training_source=model.training_source,
                dataset_hash=hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest(),
                theme_labels=list(labels), primary_naive_bayes=primary,
                diagnostic_raw_candidate=_metrics(actual, raw, labels),
                deployed_hybrid=_metrics(actual, hybrid, labels), predictions=ledger,
                note='Model scores are uncalibrated. Independently reviewed held-out projects are required; a passing score alone does not establish training/tuning independence. Matrix rows are actual labels, columns are predictions. Abstentions and processing failures count as unsuccessful predictions. Individual current sources are classified separately and one primary source is selected; legacy exports without timestamps approximate recency using numeric source IDs.')
