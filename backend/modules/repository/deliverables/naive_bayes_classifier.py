"""
Naive Bayes Document Classifier
Automatically categorizes documents into technology domains
"""

import os
import pickle
import numpy as np
from typing import Dict, List, Tuple
from sklearn.naive_bayes import MultinomialNB
from sklearn.feature_extraction.text import TfidfVectorizer


# Technology categories
CATEGORIES = [
    'Cybersecurity',
    'Web Development',
    'Mobile Development',
    'Machine Learning',
    'Data Science',
    'Cloud Computing',
    'IoT',
    'Game Development',
    'Desktop Applications',
    'Database Systems',
    'Network Systems',
    'Other'
]

# Category keywords (for initial training)
CATEGORY_KEYWORDS = {
    'Cybersecurity': [
        'encryption', 'firewall', 'security', 'authentication', 'authorization',
        'sql injection', 'xss', 'csrf', 'penetration testing', 'vulnerability',
        'malware', 'antivirus', 'intrusion detection', 'cryptography', 'ssl',
        'tls', 'vpn', 'password', 'hashing', 'digital signature'
    ],
    'Web Development': [
        'html', 'css', 'javascript', 'react', 'angular', 'vue', 'nodejs',
        'express', 'django', 'flask', 'php', 'laravel', 'wordpress', 'frontend',
        'backend', 'rest api', 'graphql', 'responsive design', 'bootstrap', 'tailwind'
    ],
    'Mobile Development': [
        'android', 'ios', 'flutter', 'react native', 'swift', 'kotlin',
        'mobile app', 'xamarin', 'cordova', 'ionic', 'app store', 'play store',
        'mobile ui', 'touch interface', 'push notifications', 'mobile sdk'
    ],
    'Machine Learning': [
        'neural network', 'deep learning', 'tensorflow', 'pytorch', 'keras',
        'classification', 'regression', 'clustering', 'supervised learning',
        'unsupervised learning', 'reinforcement learning', 'model training',
        'feature engineering', 'gradient descent', 'backpropagation'
    ],
    'Data Science': [
        'data analysis', 'pandas', 'numpy', 'matplotlib', 'seaborn', 'jupyter',
        'data visualization', 'statistics', 'data mining', 'big data', 'hadoop',
        'spark', 'data warehouse', 'etl', 'business intelligence', 'analytics'
    ],
    'Cloud Computing': [
        'aws', 'azure', 'google cloud', 'cloud storage', 'serverless', 'lambda',
        'ec2', 's3', 'docker', 'kubernetes', 'microservices', 'cloud deployment',
        'scalability', 'load balancing', 'cloud infrastructure', 'devops'
    ],
    'IoT': [
        'internet of things', 'sensors', 'arduino', 'raspberry pi', 'mqtt',
        'embedded systems', 'smart devices', 'automation', 'home automation',
        'industrial iot', 'edge computing', 'wireless communication', 'bluetooth'
    ],
    'Game Development': [
        'unity', 'unreal engine', 'game engine', 'game design', '3d modeling',
        'animation', 'game physics', 'multiplayer', 'game ai', 'level design',
        'game mechanics', 'sprite', 'texture', 'shader', 'game loop'
    ],
    'Desktop Applications': [
        'desktop app', 'gui', 'electron', 'qt', 'wpf', 'javafx', 'swing',
        'windows forms', 'cross platform', 'native app', 'desktop ui', 'tkinter'
    ],
    'Database Systems': [
        'database', 'sql', 'mysql', 'postgresql', 'mongodb', 'nosql', 'redis',
        'database design', 'normalization', 'indexing', 'query optimization',
        'stored procedures', 'triggers', 'transactions', 'acid', 'orm'
    ],
    'Network Systems': [
        'networking', 'tcp ip', 'routing', 'switching', 'network protocol',
        'network security', 'network topology', 'lan', 'wan', 'vpn', 'dns',
        'dhcp', 'network administration', 'network monitoring', 'bandwidth'
    ],
    'Other': [
        'project', 'system', 'application', 'software', 'development',
        'implementation', 'design', 'testing', 'documentation', 'requirements'
    ]
}


class NaiveBayesClassifier:
    """Naive Bayes classifier for document categorization"""
    
    def __init__(self):
        self.vectorizer = TfidfVectorizer(
            max_features=500,
            stop_words='english',
            ngram_range=(1, 2),
            min_df=1,
            max_df=0.8
        )
        self.classifier = MultinomialNB(alpha=1.0)
        self.categories = CATEGORIES
        self.is_trained = False
    
    def train_from_keywords(self):
        """Train classifier using predefined keywords"""
        print('Training Naive Bayes classifier from keywords...')
        
        # Generate training documents from keywords
        training_docs = []
        training_labels = []
        
        for category, keywords in CATEGORY_KEYWORDS.items():
            # Create multiple training documents per category
            for i in range(5):  # 5 variations per category
                # Combine keywords with some randomness
                doc = ' '.join(keywords * (i + 1))
                training_docs.append(doc)
                training_labels.append(category)
        
        # Vectorize training documents
        X_train = self.vectorizer.fit_transform(training_docs)
        
        # Train classifier
        self.classifier.fit(X_train, training_labels)
        self.is_trained = True
        self.categories = list(self.classifier.classes_)
        
        print(f'Classifier trained on {len(training_docs)} documents')
        print(f'Categories: {len(self.categories)}')
        print(f'Features: {len(self.vectorizer.get_feature_names_out())}')
    
    def predict(self, text: str) -> Dict[str, any]:
        """
        Predict category for given text
        
        Args:
            text: Document text to classify
            
        Returns:
            Dictionary with prediction results
        """
        if not self.is_trained:
            self.train_from_keywords()
        
        # Vectorize input text
        X = self.vectorizer.transform([text])
        
        # Predict category
        predicted_category = self.classifier.predict(X)[0]
        
        # Get probabilities for all categories
        probabilities = self.classifier.predict_proba(X)[0]
        
        # Get confidence (max probability)
        confidence = max(probabilities) * 100
        
        # Build results
        all_probabilities = []
        for category, prob in zip(self.classifier.classes_, probabilities):
            all_probabilities.append({
                'category': str(category),
                'probability': prob * 100,
                'confidence': f'{prob * 100:.1f}%'
            })
        
        # Sort by probability
        all_probabilities.sort(key=lambda x: x['probability'], reverse=True)
        
        return {
            'predicted_category': predicted_category,
            'confidence': f'{confidence:.1f}%',
            'confidence_score': confidence,
            'all_probabilities': all_probabilities,
            'top_3': all_probabilities[:3]
        }
    
    def save_model(self, filepath: str):
        """Save trained model to disk"""
        if not self.is_trained:
            raise ValueError('Model must be trained before saving')
        
        model_data = {
            'vectorizer': self.vectorizer,
            'classifier': self.classifier,
            'categories': self.categories,
            'is_trained': self.is_trained
        }
        
        with open(filepath, 'wb') as f:
            pickle.dump(model_data, f)
        
        print(f'Model saved to {filepath}')
    
    def load_model(self, filepath: str):
        """Load trained model from disk"""
        if not os.path.exists(filepath):
            print(f'Warning: Model file not found: {filepath}')
            print('Training new model from keywords...')
            self.train_from_keywords()
            return
        
        with open(filepath, 'rb') as f:
            model_data = pickle.load(f)
        
        self.vectorizer = model_data['vectorizer']
        self.classifier = model_data['classifier']
        self.categories = model_data['categories']
        self.is_trained = model_data['is_trained']
        
        print(f'Model loaded from {filepath}')


# Global classifier instance
_classifier = None

def get_classifier() -> NaiveBayesClassifier:
    """Get or create global classifier instance"""
    global _classifier
    
    if _classifier is None:
        _classifier = NaiveBayesClassifier()
        
        # Try to load saved model
        model_path = os.path.join(os.path.dirname(__file__), 'naive_bayes_model.pkl')
        _classifier.load_model(model_path)
    
    return _classifier


def classify_document(text: str) -> Dict[str, any]:
    """
    Classify document text into technology category
    
    Args:
        text: Document text to classify
        
    Returns:
        Dictionary with classification results
    """
    classifier = get_classifier()
    return classifier.predict(text)


def train_and_save_model():
    """Train classifier and save to disk"""
    classifier = NaiveBayesClassifier()
    classifier.train_from_keywords()
    
    model_path = os.path.join(os.path.dirname(__file__), 'naive_bayes_model.pkl')
    classifier.save_model(model_path)
    
    return classifier


if __name__ == '__main__':
    # Train and save model
    print('Training Naive Bayes classifier...')
    classifier = train_and_save_model()
    
    # Test classification
    test_texts = [
        "This project focuses on developing a secure authentication system using encryption and firewall technologies to protect against SQL injection attacks",
        "We built a responsive web application using React, Node.js, and MongoDB with REST API integration",
        "The mobile app was developed using Flutter for cross-platform deployment on Android and iOS",
        "Our machine learning model uses TensorFlow and neural networks for image classification"
    ]
    
    print('\n Testing classifier:')
    for text in test_texts:
        result = classifier.predict(text)
        print(f'\n   Text: "{text[:60]}..."')
        print(f'Category: {result["predicted_category"]} ({result["confidence"]})')
        print(f'Top 3: {[f"{p["category"]} ({p["confidence"]})" for p in result["top_3"]]}')
