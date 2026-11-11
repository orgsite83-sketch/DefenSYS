"""PDF extraction must produce database-safe text without changing uploads."""
from tempfile import NamedTemporaryFile, TemporaryDirectory
from unittest.mock import MagicMock, patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from . import tests as deliverable_tests
from .models import DeliverableSubmission
from .pdf_processor import extract_pdf_content


class PdfTextExtractionTests(SimpleTestCase):
    def extract_pages(self, pages):
        pdf = MagicMock()
        pdf.pages = [MagicMock(extract_text=MagicMock(return_value=text)) for text in pages]
        with NamedTemporaryFile(suffix='.pdf') as source, \
                patch('pdfplumber.open') as open_pdf, \
                patch('repository.deliverables.pdf_processor.extract_topics_tfidf', return_value=[]) as topics, \
                patch('repository.deliverables.naive_bayes_classifier.classify_document') as classify:
            open_pdf.return_value.__enter__.return_value = pdf
            classify.return_value = {'predicted_category': 'Technology', 'confidence': 0.9}
            result = extract_pdf_content(source.name, classify=True)
        return result, topics, classify

    def test_nul_is_removed_before_summary_topics_and_classification(self):
        result, topics, classify = self.extract_pages(['Thrive\x00 United\nChapter 1-3', 'Café\x00 manuscript'])
        expected = 'Thrive United\nChapter 1-3\fCafé manuscript'
        self.assertEqual(result['text'], expected)
        self.assertEqual(result['summary'], 'Thrive United Chapter 1-3 Café manuscript')
        topics.assert_called_once_with(expected)
        classify.assert_called_once_with(expected)

    def test_ordinary_text_and_page_boundaries_are_preserved(self):
        expected = 'Thrive United\nChapter 1-3\t— Café\f\fNext page'
        result, _, _ = self.extract_pages(['Thrive United\nChapter 1-3\t— Café', None, 'Next page'])
        self.assertEqual(result['text'], expected)

    def test_nul_only_document_has_no_derived_metadata(self):
        result, topics, classify = self.extract_pages(['\x00\x00'])
        self.assertEqual(result['text'], '')
        self.assertEqual(result['summary'], '')
        self.assertEqual(result['topics'], [])
        topics.assert_not_called()
        classify.assert_not_called()


class PdfUploadTextTests(APITestCase):
    setUp = deliverable_tests.CapstoneDeliverablesApiTests.setUp
    upload_payload = deliverable_tests.CapstoneDeliverablesApiTests.upload_payload

    def test_student_upload_with_nul_in_pdf_text_preserves_name_and_bytes(self):
        self.client.force_authenticate(self.student)
        filename = 'Thrive United_Manuscript(Chapter 1-3).pdf'
        content = b'%PDF-1.4\noriginal upload bytes\x00'
        pdf = MagicMock()
        pdf.pages = [MagicMock(extract_text=MagicMock(return_value='Thrive\x00 United manuscript'))]
        with TemporaryDirectory() as media, override_settings(MEDIA_ROOT=media), \
                patch('pdfplumber.open') as open_pdf, \
                patch('repository.deliverables.pdf_processor.extract_topics_tfidf', return_value=[]), \
                patch('repository.deliverables.naive_bayes_classifier.classify_document', return_value={
                    'predicted_category': 'Technology', 'confidence': 0.9,
                }):
            open_pdf.return_value.__enter__.return_value = pdf
            response = self.client.post('/api/repository/deliverables/upload/', self.upload_payload(
                file_name=filename,
                file=SimpleUploadedFile(filename, content, content_type='application/pdf'),
            ), format='multipart')
            self.assertEqual(response.status_code, 200, response.data)
            submission = DeliverableSubmission.objects.get(team=self.team, deliverable_id='D1')
            document = submission.files.get(is_current=True)
            for row in (submission, document):
                self.assertEqual(row.file_name, filename)
                self.assertEqual(row.extracted_text, 'Thrive United manuscript')
                self.assertEqual(row.summary, 'Thrive United manuscript')
                with row.file.open('rb') as stored:
                    self.assertEqual(stored.read(), content)

    def test_actual_nul_in_filename_is_rejected_before_saving(self):
        response = self.client.post('/api/repository/deliverables/upload/', self.upload_payload(
            file_name='Manu\x00script.pdf',
        ), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('file_name', response.data)
        self.assertFalse(DeliverableSubmission.objects.filter(team=self.team).exists())
