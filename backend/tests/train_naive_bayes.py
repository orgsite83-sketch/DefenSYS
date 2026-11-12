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

from repository.deliverables.naive_bayes_classifier import NaiveBayesClassifier, get_classifier
from repository.deliverables.classification_evaluation import STUDY_LABELS, reviewed_dataset, evaluate_projects
from repository.deliverables.classification_taxonomy import TRAINING_EXAMPLES


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', help='Reviewed JSON dataset with project-level train/test splits.')
    parser.add_argument('--train', action='store_true', help='Explicitly replace the application model after evaluation.')
    parser.add_argument('--use-current-model', action='store_true', help='Evaluate all test projects against the existing model without training on them.')
    parser.add_argument('--target-accuracy', type=float, default=0.92)
    parser.add_argument('--label-set', choices=('study7', 'all'), default='study7')
    parser.add_argument('--report', type=Path, help='Write a JSON report and project prediction ledger; refuses to overwrite.')
    options = parser.parse_args(argv)
    if not options.dataset:
        if options.train:
            parser.error('--train requires a reviewed dataset and a passing held-out evaluation.')
        model = get_classifier()
        print(json.dumps({'model_version': model.model_version, 'training_source': model.training_source,
                          'accuracy': None, 'note': 'No faculty-reviewed test dataset supplied.'}, indent=2))
        return
    records = reviewed_dataset(options.dataset)
    if options.train and options.use_current_model:
        parser.error('--train cannot be combined with --use-current-model.')
    labels = STUDY_LABELS if options.label_set == 'study7' else tuple(TRAINING_EXAMPLES)
    if any(r['label'] not in labels for r in records):
        parser.error('Dataset includes labels outside the chosen taxonomy. Use --label-set all or independently review the study taxonomy; do not omit hard cases.')
    training = defaultdict(list)
    tests = []
    for record in records:
        if record['split'] == 'train':
            training[record['label']].append(record['text'])
        else:
            tests.append(record)
    if not tests or (not training and not options.use_current_model):
        raise ValueError('Separate reviewed training and test projects are required.')
    if options.use_current_model:
        model = get_classifier()
    else:
        model = NaiveBayesClassifier()
        model.train_from_examples(dict(training), training_source='Supplied reviewed project descriptions')
    report = evaluate_projects(model, records, labels=labels, target_accuracy=options.target_accuracy)
    report['evaluation_mode'] = 'existing_frozen_model' if options.use_current_model else 'reviewed_training_candidate'
    report['runtime_versions'] = {package: __import__(package).__version__ for package in ('sklearn', 'numpy', 'scipy')}
    if options.report:
        options.report.parent.mkdir(parents=True, exist_ok=True)
        with options.report.open('x', encoding='utf-8') as output:
            json.dump(report, output, indent=2)
    print(json.dumps(report, indent=2))
    if options.train:
        if not report['primary_naive_bayes']['meets_target']:
            raise ValueError('Held-out NB accuracy did not meet the requested target. Application model was not changed.')
        model.save_model(ROOT / 'modules/repository/deliverables/naive_bayes_model.pkl')
        print('Saved reviewed model. Reclassify cached documents with the management command.')


if __name__ == '__main__':
    main()
