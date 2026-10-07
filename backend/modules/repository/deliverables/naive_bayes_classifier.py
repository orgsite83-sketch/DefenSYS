"""Public compatibility API for the versioned project-focus classifier."""
from pathlib import Path

from .classification_taxonomy import FOCUS_SIGNALS, TRAINING_EXAMPLES
from .project_classification import ProjectFocusClassifier

CATEGORIES = list(TRAINING_EXAMPLES) + ['Other']
CATEGORY_KEYWORDS = FOCUS_SIGNALS
NaiveBayesClassifier = ProjectFocusClassifier
_classifier = None


def get_classifier():
    global _classifier
    if _classifier is None:
        _classifier = NaiveBayesClassifier()
        _classifier.load_model(Path(__file__).with_name('naive_bayes_model.pkl'))
    return _classifier


def classify_document(text):
    return get_classifier().predict(text)


def train_and_save_model():
    classifier = NaiveBayesClassifier()
    classifier.train_from_examples()
    classifier.save_model(Path(__file__).with_name('naive_bayes_model.pkl'))
    global _classifier
    _classifier = classifier
    return classifier


if __name__ == '__main__':
    trained = train_and_save_model()
    print(f'Trained {len(trained.categories)} computing categories from development examples.')
    print('Real-project accuracy requires evaluation on faculty-reviewed, held-out projects.')
