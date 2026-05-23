"""
Train Naive Bayes classifier for document categorization
"""

import os
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from repository.deliverables.naive_bayes_classifier import train_and_save_model, classify_document


def main():
    print('\n' + '='*80)
    print('TRAINING NAIVE BAYES CLASSIFIER')
    print('='*80 + '\n')
    
    # Train and save model
    classifier = train_and_save_model()
    
    print('\n' + '='*80)
    print('TESTING CLASSIFIER')
    print('='*80 + '\n')
    
    # Test with sample documents
    test_documents = [
        {
            'text': 'This project focuses on developing a secure authentication system using encryption and firewall technologies to protect against SQL injection attacks and XSS vulnerabilities. We implemented password hashing and SSL/TLS protocols.',
            'expected': 'Cybersecurity'
        },
        {
            'text': 'We built a responsive web application using React, Node.js, Express, and MongoDB. The frontend uses Bootstrap for responsive design and the backend provides REST API endpoints with JWT authentication.',
            'expected': 'Web Development'
        },
        {
            'text': 'The mobile application was developed using Flutter for cross-platform deployment on Android and iOS. We implemented push notifications, touch gestures, and integrated with Firebase for backend services.',
            'expected': 'Mobile Development'
        },
        {
            'text': 'Our machine learning model uses TensorFlow and neural networks for image classification. We trained a deep learning model using convolutional neural networks with backpropagation and gradient descent optimization.',
            'expected': 'Machine Learning'
        },
        {
            'text': 'The data analysis project uses Python with Pandas, NumPy, and Matplotlib for data visualization. We performed statistical analysis and created interactive dashboards using Jupyter notebooks.',
            'expected': 'Data Science'
        },
        {
            'text': 'We deployed the application on AWS using EC2 instances, S3 for storage, and Lambda for serverless functions. The infrastructure uses Docker containers orchestrated with Kubernetes for scalability.',
            'expected': 'Cloud Computing'
        },
        {
            'text': 'The IoT system uses Arduino and Raspberry Pi with MQTT protocol for communication between sensors and the cloud. We implemented home automation with smart devices and edge computing.',
            'expected': 'IoT'
        },
        {
            'text': 'The game was developed using Unity game engine with C# scripting. We implemented 3D modeling, animation, game physics, and multiplayer networking with real-time synchronization.',
            'expected': 'Game Development'
        },
        {
            'text': 'We designed a relational database using PostgreSQL with proper normalization and indexing. The system includes stored procedures, triggers, and transaction management with ACID properties.',
            'expected': 'Database Systems'
        },
        {
            'text': 'The network infrastructure includes routing, switching, and VPN configuration. We implemented network security with firewalls, intrusion detection systems, and network monitoring tools.',
            'expected': 'Network Systems'
        }
    ]
    
    correct = 0
    total = len(test_documents)
    
    for i, doc in enumerate(test_documents, 1):
        print(f'\n[{i}/{total}] Testing document:')
        print(f'Text: "{doc["text"][:80]}..."')
        print(f'Expected: {doc["expected"]}')
        
        result = classify_document(doc['text'])
        
        print(f'Predicted: {result["predicted_category"]} ({result["confidence"]})')
        print(f'Top 3: {[f"{p["category"]} ({p["confidence"]})" for p in result["top_3"]]}')
        
        if result['predicted_category'] == doc['expected']:
            print(f'CORRECT')
            correct += 1
        else:
            print(f'INCORRECT')
    
    accuracy = (correct / total) * 100
    
    print('\n' + '='*80)
    print('TRAINING COMPLETE')
    print('='*80)
    print(f'\n Accuracy: {correct}/{total} ({accuracy:.1f}%)')
    print(f'Correct predictions: {correct}')
    print(f'Incorrect predictions: {total - correct}')
    
    if accuracy >= 80:
        print(f'\n Excellent! Classifier is ready for production use.')
    elif accuracy >= 60:
        print(f'\nWarning: Good, but could be improved with more training data.')
    else:
        print(f'\n Poor accuracy. Consider adding more training data or adjusting parameters.')


if __name__ == '__main__':
    main()
