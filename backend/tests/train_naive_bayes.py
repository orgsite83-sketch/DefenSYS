"""Train explicitly, or evaluate on reviewed projects without updating the model.

Dataset JSON: [{project_id, text, label, split: train|test, reviewed: true}].
All files from one project must stay in a single split. Generated examples and
smoke tests are never reported as measured real-project accuracy.
"""
import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
import django
django.setup()

from sklearn.metrics import classification_report
from repository.deliverables.naive_bayes_classifier import NaiveBayesClassifier, get_classifier, train_and_save_model


def reviewed_dataset(path):
    records = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(records, list) or not records:
        raise ValueError('Dataset must contain reviewed, labelled project records.')
    groups = defaultdict(set)
    for record in records:
        if record.get('reviewed') is not True or not record.get('project_id') or not record.get('text') or not record.get('label'):
            raise ValueError('Every record needs project_id, text, label and reviewed=true.')
        if record.get('split') not in ('train', 'test'):
            raise ValueError('Every record needs an explicit train or test split.')
        groups[record['project_id']].add(record['split'])
    if any(len(splits) != 1 for splits in groups.values()):
        raise ValueError('Documents from one project cannot appear in both training and testing.')
    return records


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', help='Reviewed JSON dataset with project-level train/test splits.')
    parser.add_argument('--train', action='store_true', help='Explicitly replace the application model after evaluation.')
    options = parser.parse_args(argv)
    if not options.dataset:
        model = train_and_save_model() if options.train else get_classifier()
        print(json.dumps({'model_version': model.model_version, 'training_source': model.training_source,
                          'accuracy': None, 'note': 'No faculty-reviewed test dataset supplied.'}, indent=2))
        return
    records = reviewed_dataset(options.dataset)
    training = defaultdict(list)
    tests = []
    for record in records:
        if record['split'] == 'train':
            training[record['label']].append(record['text'])
        else:
            tests.append(record)
    if not tests or not training:
        raise ValueError('Separate reviewed training and test projects are required.')
    model = NaiveBayesClassifier()
    model.train_from_examples(dict(training), training_source='Supplied reviewed project descriptions')
    # Report one result per test project. Multiple files cannot inflate accuracy.
    grouped = defaultdict(list)
    for record in tests:
        grouped[record['project_id']].append(record)
    actual, predicted = [], []
    for project_records in grouped.values():
        labels = {r['label'] for r in project_records}
        if len(labels) != 1:
            raise ValueError('A project must have one reviewed primary computing focus.')
        result = model.predict('\n'.join(dict.fromkeys(r['text'] for r in project_records)))
        actual.append(next(iter(labels)))
        predicted.append(result['predicted_category'])
    print(json.dumps({'test_projects': len(actual), 'report': classification_report(actual, predicted, output_dict=True, zero_division=0),
                      'note': 'Model scores are uncalibrated. Assess per-category precision, recall and unresolved coverage.'}, indent=2))
    if options.train:
        model.save_model(ROOT / 'modules/repository/deliverables/naive_bayes_model.pkl')
        print('Saved reviewed model. Reclassify cached documents with the management command.')


if __name__ == '__main__':
    main()
