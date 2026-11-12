"""Inspect exported current manuscripts offline; no Django, DB or model writes.

This reports processing coverage, never accuracy: expected labels stay unused.
Legacy export source boundaries are reconstructed only when lengths agree
exactly. New exports retain each source text and upload timestamp explicitly.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend/modules'))

from curriculum_analytics.application_areas import application_area
from repository.deliverables.project_classification import ProjectFocusClassifier, FEATURE_VERSION, input_hash
from repository.deliverables.classification_evaluation import source_documents, source_priority


def inspect_project(row, model):
    documents = source_documents(row)
    # Mirrors the source-copy deduplication policy, never document voting.
    documents = list({input_hash(d['_raw_text']): d for d in documents}.values())
    for document in documents:
        document['classification'] = model.classify_document(document['_raw_text'])
    usable = [d for d in documents if d['classification']['status'] == 'estimated']
    primary = max(usable, key=lambda d: source_priority(d, d['classification']), default=None)
    # Legacy exports lack upload timestamps; preserve their explicit source
    # ordering as an approximation, disclosed in every report.
    ordered = sorted(documents, key=lambda d: (d.get('uploaded_at', ''), d.get('_legacy_order', 0)), reverse=True)
    area = application_area(ordered, primary['id'] if primary else None)
    return dict(project_id=row['project_id'], project_title=row['project_title'],
                category=primary['classification']['predicted_category'] if primary else 'Unclassified',
                decision_method=primary['classification']['decision_method'] if primary else None,
                **area,
                sources=[dict(id=d['id'], label=d['label'], text_characters=len(d['_raw_text']),
                              predicted=d['classification']['predicted_category'],
                              candidate=d['classification']['candidate_category'],
                              score=d['classification']['confidence_score'],
                              reason=d['classification']['reason_code'],
                              top_3=d['classification']['top_3']) for d in documents])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = json.loads(args.dataset.read_text(encoding='utf-8'))
    model = ProjectFocusClassifier()
    results = [inspect_project(row, model) for row in rows]
    report = dict(projects=len(results), model_version=model.model_version, feature_version=FEATURE_VERSION, training_source=model.training_source,
        accuracy=None, categories=dict(Counter(r['category'] for r in results)),
        application_areas=dict(Counter(r['application_area'] for r in results)),
        area_reasons=dict(Counter(r['application_area_reason_code'] for r in results)),
        note='Unlabelled processing diagnostics, not an accuracy evaluation. Legacy exports lack upload times; numeric source IDs approximate recency.',
        details=results)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(report, output, indent=2, ensure_ascii=False)
    print(json.dumps({k: v for k, v in report.items() if k != 'details'}, indent=2))


if __name__ == '__main__':
    main()
