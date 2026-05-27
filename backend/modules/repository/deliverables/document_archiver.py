"""
Automated Document Archiving System
Intelligently organizes and archives documents based on ML classification
"""

import os
import shutil
from datetime import datetime
from typing import Dict
from pathlib import Path


class DocumentArchiver:
    """Handles intelligent document archiving with category-based organization"""
    
    def __init__(self, base_path: str = None):
        """
        Initialize archiver
        
        Args:
            base_path: Base directory for archived files (defaults to media/digital-vault/)
        """
        if base_path is None:
            # Use Django media directory
            from django.conf import settings
            base_path = os.path.join(settings.MEDIA_ROOT, 'digital-vault')
        
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)
    
    def archive_document(
        self,
        source_file_path: str,
        filename: str,
        category: str,
        confidence: float,
        metadata: Dict[str, str]
    ) -> Dict[str, any]:
        """
        Archive document with intelligent organization
        
        Args:
            source_file_path: Path to source file
            filename: Original filename
            category: ML-predicted category
            confidence: Classification confidence (0-100)
            metadata: Additional metadata (year_level, course_code, team_name, etc.)
            
        Returns:
            Dictionary with archiving results
        """
        try:
            # Extract metadata
            year_level = metadata.get('year_level', 'Unknown')
            course_code = metadata.get('course_code', 'Unknown')
            semester = metadata.get('semester', 'Unknown')
            team_name = metadata.get('team_name', 'Unknown')
            
            # Construct archive path
            # Structure: digital-vault/{Category}/{YearLevel}/{CourseCode}/{Semester}/{filename}
            archive_path = self.base_path / category / year_level / course_code / semester
            archive_path.mkdir(parents=True, exist_ok=True)
            
            # Destination file path
            dest_file_path = archive_path / filename
            
            # Copy file to archive
            shutil.copy2(source_file_path, dest_file_path)
            
            # Create metadata file
            metadata_path = archive_path / f'{filename}.meta.txt'
            self._write_metadata(metadata_path, {
                'filename': filename,
                'category': category,
                'confidence': f'{confidence:.1f}%',
                'year_level': year_level,
                'course_code': course_code,
                'semester': semester,
                'team_name': team_name,
                'archived_at': datetime.now().isoformat(),
                'source_path': source_file_path,
                'archive_path': str(dest_file_path)
            })
            
            # Calculate relative path for database storage
            relative_path = dest_file_path.relative_to(self.base_path)
            
            return {
                'status': 'success',
                'archive_path': str(dest_file_path),
                'relative_path': str(relative_path),
                'category': category,
                'confidence': f'{confidence:.1f}%',
                'message': f'File archived to {category} with {confidence:.1f}% confidence'
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'message': f'Archiving failed: {str(e)}',
                'error': str(e)
            }
    
    def _write_metadata(self, filepath: Path, metadata: Dict[str, str]):
        """Write metadata to text file"""
        with open(filepath, 'w') as f:
            f.write('=' * 80 + '\n')
            f.write('DOCUMENT METADATA\n')
            f.write('=' * 80 + '\n\n')
            
            for key, value in metadata.items():
                f.write(f'{key.replace("_", " ").title()}: {value}\n')
            
            f.write('\n' + '=' * 80 + '\n')
    
    def get_category_stats(self) -> Dict[str, int]:
        """Get document count per category"""
        stats = {}
        
        if not self.base_path.exists():
            return stats
        
        for category_dir in self.base_path.iterdir():
            if category_dir.is_dir():
                # Count PDF files in category
                count = sum(1 for _ in category_dir.rglob('*.pdf'))
                stats[category_dir.name] = count
        
        return stats
    
    def get_archive_structure(self) -> Dict[str, any]:
        """Get complete archive directory structure"""
        structure = {}
        
        if not self.base_path.exists():
            return structure
        
        for category_dir in self.base_path.iterdir():
            if category_dir.is_dir():
                category_name = category_dir.name
                structure[category_name] = {
                    'path': str(category_dir),
                    'year_levels': {}
                }
                
                # Get year levels
                for year_dir in category_dir.iterdir():
                    if year_dir.is_dir():
                        year_name = year_dir.name
                        structure[category_name]['year_levels'][year_name] = {
                            'path': str(year_dir),
                            'courses': {}
                        }
                        
                        # Get courses
                        for course_dir in year_dir.iterdir():
                            if course_dir.is_dir():
                                course_name = course_dir.name
                                structure[category_name]['year_levels'][year_name]['courses'][course_name] = {
                                    'path': str(course_dir),
                                    'semesters': {}
                                }
                                
                                # Get semesters
                                for semester_dir in course_dir.iterdir():
                                    if semester_dir.is_dir():
                                        semester_name = semester_dir.name
                                        files = list(semester_dir.glob('*.pdf'))
                                        structure[category_name]['year_levels'][year_name]['courses'][course_name]['semesters'][semester_name] = {
                                            'path': str(semester_dir),
                                            'file_count': len(files),
                                            'files': [f.name for f in files]
                                        }
        
        return structure


def archive_with_classification(
    file_path: str,
    filename: str,
    extracted_text: str,
    metadata: Dict[str, str]
) -> Dict[str, any]:
    """
    Complete archiving workflow with ML classification
    
    Args:
        file_path: Path to file to archive
        filename: Original filename
        extracted_text: Extracted PDF text for classification
        metadata: File metadata
        
    Returns:
        Dictionary with archiving and classification results
    """
    from .naive_bayes_classifier import classify_document
    
    # Step 1: Classify document
    print(f'Classifying document: {filename}')
    classification = classify_document(extracted_text)
    
    category = classification['predicted_category']
    confidence = classification['confidence_score']
    
    print(f'Category: {category} ({confidence:.1f}% confidence)')
    print(f'Top 3: {[f"{p["category"]} ({p["confidence"]})" for p in classification["top_3"]]}')
    
    # Step 2: Archive document
    print(f'Archiving to: {category}/')
    archiver = DocumentArchiver()
    archive_result = archiver.archive_document(
        source_file_path=file_path,
        filename=filename,
        category=category,
        confidence=confidence,
        metadata=metadata
    )
    
    # Step 3: Combine results
    result = {
        **archive_result,
        'classification': classification
    }
    
    if archive_result['status'] == 'success':
        print(f'{archive_result["message"]}')
    else:
        print(f'{archive_result["message"]}')
    
    return result


if __name__ == '__main__':
    # Test archiving system
    print('Testing Document Archiver...\n')
    
    archiver = DocumentArchiver()
    
    # Test archive
    test_metadata = {
        'year_level': '3rdYear',
        'course_code': 'ITEC101',
        'semester': '1stSemester',
        'team_name': 'TeamAlpha'
    }
    
    print('Archive Statistics:')
    stats = archiver.get_category_stats()
    for category, count in stats.items():
        print(f'{category}: {count} documents')
    
    print('\n Archive Structure:')
    structure = archiver.get_archive_structure()
    for category, data in structure.items():
        print(f'{category}/')
        for year, year_data in data['year_levels'].items():
            print(f'{year}/')
            for course, course_data in year_data['courses'].items():
                print(f'{course}/')
                for semester, semester_data in course_data['semesters'].items():
                    print(f' {semester}/ ({semester_data["file_count"]} files)')
