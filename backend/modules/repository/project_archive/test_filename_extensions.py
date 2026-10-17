from django.test import SimpleTestCase

from .services import resolve_archive_file_template


class ArchiveFilenameExtensionTests(SimpleTestCase):
    def test_recommendations_use_configured_format_with_default_or_pdf_template(self):
        for file_format, extension in (
            ('archive', 'zip'), ('video', 'mp4'), ('image', 'png'),
            ('spreadsheet', 'xlsx'), ('audio', 'mp3'), ('pdf', 'pdf'),
        ):
            for template in ('', '{project}_{deliverable}.pdf', '{project}_{deliverable}'):
                with self.subTest(file_format=file_format, template=template):
                    self.assertEqual(
                        resolve_archive_file_template(
                            template, None, 'Final Defense',
                            deliverable_label='Prototype Source Code', file_format=file_format,
                        ),
                        f'ProjectTitle_PrototypeSourceCode.{extension}',
                    )

    def test_uploaded_extension_overrides_default_and_explicit_template_suffix(self):
        for template in ('', '{project}_{deliverable}.pdf', '{project}_{deliverable}.zip'):
            for extension in ('zip', '.rar', '7z'):
                with self.subTest(template=template, extension=extension):
                    self.assertEqual(
                        resolve_archive_file_template(
                            template, None, 'Final Defense',
                            deliverable_label='Prototype Source Code', file_format='archive',
                            file_extension=extension,
                        ),
                        f'ProjectTitle_PrototypeSourceCode.{extension.lstrip(".")}',
                    )

    def test_compatible_template_suffixes_and_legacy_defaults_are_preserved(self):
        for template, file_format, expected in (
            ('{project}.rar', 'archive', 'ProjectTitle.rar'),
            ('{project}.pdf', 'presentation', 'ProjectTitle.pdf'),
            ('{project}.pptx', 'any', 'ProjectTitle.pptx'),
            ('{project}.{semester}', 'any', 'ProjectTitle.1stSemester.pdf'),
        ):
            with self.subTest(template=template, file_format=file_format):
                self.assertEqual(
                    resolve_archive_file_template(template, None, 'Final Defense', file_format=file_format),
                    expected,
                )
