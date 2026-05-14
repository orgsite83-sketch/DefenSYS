"""
PDF Content Extraction and Topic Modeling
Uses pdfplumber for text extraction and scikit-learn for TF-IDF keyword extraction
"""

import os
import re
from typing import Dict, List


def extract_pdf_content(file_path: str, classify: bool = False) -> Dict[str, any]:
    """
    Extract text content from PDF and generate topics/keywords using TF-IDF
    
    Args:
        file_path: Path to the PDF file
        classify: Whether to classify document category using Naive Bayes
        
    Returns:
        Dictionary with:
        - text: Full extracted text
        - topics: List of top keywords/topics
        - summary: First 500 characters as summary
        - category: ML-predicted category (if classify=True)
        - confidence: Classification confidence (if classify=True)
    """
    result = {
        'text': '',
        'topics': [],
        'summary': '',
        'category': None,
        'confidence': None,
        'classification': None
    }
    
    # Check if file exists
    if not os.path.exists(file_path):
        print(f'⚠️ PDF file not found: {file_path}')
        return result
    
    # Check if file is actually a PDF
    if not file_path.lower().endswith('.pdf'):
        print(f'⚠️ Not a PDF file: {file_path}')
        return result
    
    try:
        import pdfplumber
        
        # Extract text from PDF
        full_text = []
        with pdfplumber.open(file_path) as pdf:
            print(f'📄 Extracting text from {len(pdf.pages)} pages...')
            
            for page_num, page in enumerate(pdf.pages, 1):
                try:
                    text = page.extract_text()
                    if text:
                        full_text.append(text)
                        print(f'   ✓ Page {page_num}: {len(text)} chars')
                except Exception as e:
                    print(f'   ⚠️ Page {page_num} extraction failed: {e}')
                    continue
        
        # Combine all text
        combined_text = '\n'.join(full_text)
        result['text'] = combined_text
        
        # Generate summary (first 500 characters)
        clean_text = re.sub(r'\s+', ' ', combined_text).strip()
        result['summary'] = clean_text[:500] + ('...' if len(clean_text) > 500 else '')
        
        print(f'✅ Extracted {len(combined_text)} characters')
        
        # Extract topics using TF-IDF
        if combined_text:
            topics = extract_topics_tfidf(combined_text)
            result['topics'] = topics
            print(f'🏷️ Extracted {len(topics)} topics: {topics[:5]}...')
        
        # Classify document category using Naive Bayes (optional)
        if classify and combined_text:
            try:
                from .naive_bayes_classifier import classify_document
                classification = classify_document(combined_text)
                result['category'] = classification['predicted_category']
                result['confidence'] = classification['confidence']
                result['classification'] = classification
                print(f'🧠 Classified as: {classification["predicted_category"]} ({classification["confidence"]})')
            except Exception as e:
                print(f'⚠️ Classification failed: {e}')
        
    except ImportError:
        print('❌ pdfplumber not installed. Run: pip install pdfplumber')
    except Exception as e:
        print(f'❌ PDF extraction error: {e}')
    
    return result


def extract_topics_tfidf(text: str, max_topics: int = 10) -> List[str]:
    """
    Extract top keywords/topics from text using TF-IDF
    
    Args:
        text: Input text
        max_topics: Maximum number of topics to extract
        
    Returns:
        List of top keywords
    """
    try:
        from sklearn.feature_extraction.text import TfidfVectorizer
        import numpy as np
        
        # Clean and preprocess text
        text = text.lower()
        text = re.sub(r'[^\w\s]', ' ', text)  # Remove punctuation
        text = re.sub(r'\s+', ' ', text).strip()  # Normalize whitespace
        
        # Check if text is too short
        if len(text.split()) < 10:
            print('   ⚠️  Text too short for topic extraction')
            return []
        
        # TF-IDF vectorization with adjusted parameters for small corpus
        vectorizer = TfidfVectorizer(
            max_features=50,  # Consider top 50 terms (reduced from 100)
            stop_words='english',  # Remove common English words
            ngram_range=(1, 2),  # Include single words and 2-word phrases
            min_df=1,  # Minimum document frequency (must appear in at least 1 doc)
            max_df=1.0,  # Maximum document frequency (allow all frequencies)
        )
        
        # Fit and transform
        tfidf_matrix = vectorizer.fit_transform([text])
        feature_names = vectorizer.get_feature_names_out()
        
        # Get TF-IDF scores
        tfidf_scores = tfidf_matrix.toarray()[0]
        
        # Sort by score and get top keywords
        top_indices = np.argsort(tfidf_scores)[::-1][:max_topics]
        topics = [feature_names[i] for i in top_indices if tfidf_scores[i] > 0]
        
        return topics
        
    except ImportError:
        print('❌ scikit-learn not installed. Run: pip install scikit-learn')
        return []
    except Exception as e:
        print(f'❌ Topic extraction error: {e}')
        return []


def clean_text_for_search(text: str) -> str:
    """
    Clean extracted text for search indexing
    
    Args:
        text: Raw extracted text
        
    Returns:
        Cleaned text suitable for search
    """
    # Remove excessive whitespace
    text = re.sub(r'\s+', ' ', text)
    
    # Remove special characters but keep alphanumeric and basic punctuation
    text = re.sub(r'[^\w\s.,!?-]', '', text)
    
    # Normalize case
    text = text.lower()
    
    return text.strip()


def extract_metadata_from_text(text: str) -> Dict[str, str]:
    """
    Extract common metadata patterns from PDF text
    
    Args:
        text: Extracted PDF text
        
    Returns:
        Dictionary with extracted metadata
    """
    metadata = {}
    
    # Common patterns
    patterns = {
        'title': r'(?i)title[:\s]+([^\n]{5,100})',
        'author': r'(?i)author[:\s]+([^\n]{3,50})',
        'date': r'(?i)date[:\s]+([^\n]{5,30})',
        'abstract': r'(?i)abstract[:\s]+([^\n]{20,500})',
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, text)
        if match:
            metadata[key] = match.group(1).strip()
    
    return metadata
