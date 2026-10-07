"""Section-aware, evidence-backed Naive Bayes project classification.

No network calls or ORM writes. Bootstrap scores are model outputs, not
calibrated accuracy claims. Uncertain projects remain explicitly unresolved.
"""
import hashlib
import json
import logging
import pickle
import re
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

from sklearn.feature_extraction.text import TfidfVectorizer, ENGLISH_STOP_WORDS
from sklearn.naive_bayes import MultinomialNB

from .classification_taxonomy import (
    MODEL_VERSION, TRAINING_SOURCE, TRAINING_EXAMPLES, FOCUS_SIGNALS,
    DOMAIN_SIGNALS, TECHNOLOGY_SIGNALS,
)

logger = logging.getLogger(__name__)
MIN_SCORE = 60.0
MIN_MARGIN = 12.0
GENERIC_WORDS = {'project', 'system', 'application', 'software', 'development',
                 'implementation', 'design', 'testing', 'documentation',
                 'requirements', 'proposed', 'prototype', 'provide', 'using'}
HEADER = re.compile(
    r'^\s*(?:\d+(?:\.\d+)*[.)]?\s+)?'
    r'(abstract|introduction(?:\s*/\s*background)?|background|problem statement|'
    r'project purpose|objectives|proposed system features|system features|'
    r'scope(?: and boundaries)?|methodology|target beneficiaries|expected outputs(?: and outcomes)?|'
    r'preliminary technology considerations|success indicators|related (?:work|literature)|'
    r'literature review|references|bibliography|technical architecture|implementation|'
    r'technology stack|conclusion|results)\s*[:.]?\s*(.*)$', re.I,
)
METADATA = re.compile(r'^(?:team members?|adviser|advisor|section|category|course|'
                      r'concept paper page|page \d|submitted by|submitted to)\b', re.I)
TENTATIVE = re.compile(r'\b(?:may be used|could be used|might use|consider using|'
                       r'future work|not implemented|does not use)\b', re.I)


def input_hash(text):
    return hashlib.sha256((text or '').encode('utf-8')).hexdigest()


def matches(text, term):
    return bool(_term_pattern(term).search(text))


@lru_cache(maxsize=512)
def _term_pattern(term):
    return re.compile(r'(?<![\w])' + re.escape(term) + r'(?![\w])', re.I)


def section_chunks(text):
    """Preserve evidence passages while excluding metadata and citations."""
    lines = (text or '')[:80000].splitlines()
    # When a structured manuscript has sections, its cover/title page is not
    # enough to establish the implemented computing focus.
    section, weight = 'Project description', 0 if any(HEADER.match(line) for line in lines) else 1
    chunks, seen = [], set()
    for line in lines:
        line = re.sub(r'\(cid:\d+\)', ' ', line)
        line = re.sub(r'\s+', ' ', line).strip(' •\t')
        if not line or METADATA.match(line):
            continue
        heading = HEADER.match(line)
        if heading:
            section = heading[1].title()
            key = heading[1].lower()
            weight = 0 if key in ('related work', 'related literature', 'literature review',
                                  'references', 'bibliography', 'preliminary technology considerations') else (
                1 if key in ('scope', 'scope and boundaries', 'success indicators') else 3)
            line = heading[2].strip()
            if not line:
                continue
        if not weight or TENTATIVE.search(line):
            continue
        # De-duplicate repeated headers/boilerplate within one document.
        fingerprint = line.casefold()
        if fingerprint in seen:
            continue
        seen.add(fingerprint)
        chunks.append({'section': section, 'text': line, 'weight': weight})
    return chunks


def _signals(chunks, taxonomy):
    found = {}
    ranked_chunks = sorted(chunks, key=lambda c: -c['weight'])
    for label, terms in taxonomy.items():
        evidence = []
        for term in terms:
            hit = next((c for c in ranked_chunks
                        if matches(c['text'], term)), None)
            if hit:
                evidence.append({'label': label, 'term': term,
                                 'section': hit['section'], 'excerpt': hit['text'][:360]})
        if evidence:
            found[label] = evidence
    return found


class ProjectFocusClassifier:
    def __init__(self):
        self.vectorizer = TfidfVectorizer(
            max_features=5000, stop_words=sorted(set(ENGLISH_STOP_WORDS) | GENERIC_WORDS),
            ngram_range=(1, 2), sublinear_tf=True, norm=None, min_df=1,
        )
        self.classifier = MultinomialNB(alpha=0.5)
        self.categories = list(TRAINING_EXAMPLES)
        self.is_trained = False
        self.training_source = TRAINING_SOURCE
        self.model_version = MODEL_VERSION

    def train_from_examples(self, examples=None, *, training_source=TRAINING_SOURCE):
        examples = TRAINING_EXAMPLES if examples is None else examples
        texts, labels = [], []
        for label, passages in examples.items():
            if label not in FOCUS_SIGNALS or not passages:
                raise ValueError('Training categories must have labelled project descriptions.')
            for passage in passages:
                if not isinstance(passage, str) or not passage.strip():
                    raise ValueError('Training passages must be non-empty text.')
                texts.append(passage)
                labels.append(label)
        if len(set(labels)) < 2:
            raise ValueError('At least two labelled categories are required.')
        self.classifier.fit(self.vectorizer.fit_transform(texts), labels)
        self.categories = list(self.classifier.classes_)
        self.is_trained = True
        self.training_source = training_source
        fingerprint = hashlib.sha256(json.dumps(examples, sort_keys=True).encode('utf-8')).hexdigest()[:12]
        self.model_version = f'{MODEL_VERSION}-{fingerprint}'

    def train_from_keywords(self):
        # Compatibility for existing callers; never repeat keyword lists.
        self.train_from_examples()

    def predict(self, text):
        if not self.is_trained:
            self.train_from_examples()
        text = text or ''
        chunks = section_chunks(text)
        focus = _signals(chunks, FOCUS_SIGNALS)
        domains = _signals(chunks, DOMAIN_SIGNALS)
        technologies = _signals(chunks, TECHNOLOGY_SIGNALS)
        prepared = '\n'.join(c['text'] for c in chunks for _ in range(c['weight']))
        features = self.vectorizer.transform([prepared])
        probabilities = self.classifier.predict_proba(features)[0]
        candidates = sorted(({'category': str(c), 'probability': float(p * 100),
                              'confidence': f'{p * 100:.1f}%'}
                             for c, p in zip(self.classifier.classes_, probabilities)),
                            key=lambda r: -r['probability'])
        best = candidates[0]
        score = best['probability']
        margin = score - candidates[1]['probability']
        label = best['category']
        evidence = focus.get(label, [])
        # Different phrases containing the same token are not independent cues.
        independent = []
        for hit in sorted(evidence, key=lambda h: len(h['term'])):
            # Singular/plural mentions such as sensor/sensors or booking/bookings
            # are one cue, not two independent pieces of support.
            family = lambda term: re.sub(r'\b(\w{4,})s\b', r'\1', term.lower())
            if not any(matches(family(hit['term']), family(e['term'])) for e in independent):
                independent.append(hit)
        if len(re.sub(r'\s+', '', text)) < 40:
            status, reason_code = 'unresolved', 'unreadable'
            reason = 'The document has too little extracted text for project classification.'
        elif not focus or features.nnz == 0:
            status, reason_code = 'unresolved', 'insufficient_evidence'
            reason = 'Readable text is available, but it does not establish a supported computing focus.'
        elif len(independent) < 2:
            status, reason_code = 'unresolved', 'insufficient_evidence'
            reason = 'The leading category has too few independent supporting terms for an estimate.'
        elif score < MIN_SCORE:
            status, reason_code = 'unresolved', 'low_score'
            reason = 'The model score is below the acceptance threshold; candidate categories need review.'
        elif margin < MIN_MARGIN:
            status, reason_code = 'unresolved', 'ambiguous'
            reason = 'The leading computing categories are too close to choose a primary focus.'
        else:
            status, reason_code = 'estimated', 'supported'
            reason = f'Estimated {label} from {", ".join(h["term"] for h in independent[:4])} in the project description.'
        domain = max(domains, key=lambda d: len(domains[d])) if domains else 'Unresolved domain'
        return {
            'predicted_category': label if status == 'estimated' else 'Other',
            'candidate_category': label, 'status': status, 'reason_code': reason_code,
            'reason': reason, 'confidence_score': round(score, 2),
            'confidence': f'{score:.1f}%', 'margin': round(margin, 2),
            'all_probabilities': candidates, 'top_3': candidates[:3],
            'secondary_categories': [c for c in focus if c != label and len(focus[c]) >= 2],
            'domain': domain, 'domain_evidence': domains.get(domain, [])[:4],
            'technologies': [{'name': name, 'evidence': hits[:2]} for name, hits in technologies.items()],
            'evidence': independent[:6], 'model_version': self.model_version,
            'training_source': self.training_source, 'input_hash': input_hash(text),
            'classified_at': datetime.now(timezone.utc).isoformat(),
            'acceptance': {'minimum_score': MIN_SCORE, 'minimum_margin': MIN_MARGIN,
                           'minimum_independent_terms': 2},
        }

    def save_model(self, filepath):
        if not self.is_trained:
            raise ValueError('Model must be trained before saving.')
        destination = Path(filepath)
        temporary = destination.with_suffix('.tmp')
        with temporary.open('wb') as output:
            pickle.dump({'vectorizer': self.vectorizer, 'classifier': self.classifier,
                         'schema_version': MODEL_VERSION, 'model_version': self.model_version,
                         'training_source': self.training_source}, output)
        temporary.replace(destination)

    def load_model(self, filepath):
        path = Path(filepath)
        if path.is_file():
            # Only the application-owned model path is used by production callers.
            with path.open('rb') as source:
                data = pickle.load(source)
            if data.get('schema_version') == MODEL_VERSION:
                self.vectorizer, self.classifier = data['vectorizer'], data['classifier']
                self.categories = list(self.classifier.classes_)
                self.training_source = data.get('training_source', TRAINING_SOURCE)
                self.model_version = data['model_version']
                self.is_trained = True
                return
            logger.info('Legacy project classifier detected; using versioned development examples.')
        self.train_from_examples()


def prediction_for_text(text):
    # Lazy import avoids a cycle with the backwards-compatible public module.
    from .naive_bayes_classifier import get_classifier
    return get_classifier().predict(text)


def classification_for_document(text, cached=None):
    from .naive_bayes_classifier import get_classifier
    classifier = get_classifier()
    if isinstance(cached, dict) and cached.get('model_version') == classifier.model_version and cached.get('input_hash') == input_hash(text):
        return cached
    return classifier.predict(text)
