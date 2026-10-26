from io import BytesIO

import openpyxl

from grading.grades.test_masterlist import GradeMasterlistTests


class GradeMasterlistReportTests(GradeMasterlistTests):
    def report(self, **params):
        return self.client.get('/api/reports/grade-masterlist/', {
            'scope': 'pit', 'semester_id': self.term.pk, 'pit_event_config_id': self.event.pk,
            'export_format': 'json', **params})

    def test_masterlist_preview_and_download_include_all_pages(self):
        response = self.report(page=2, page_size=10)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['total_rows'], 13)
        self.assertEqual(len(response.data['rows']), 13)
        self.assertTrue(response.data['pdf_base64'])
        exported = self.report(export_format='xlsx', page=2, page_size=10)
        self.assertEqual(exported.status_code, 200)
        workbook = openpyxl.load_workbook(BytesIO(exported.content))
        self.assertEqual(workbook.active.freeze_panes, 'C4')
        values = list(workbook.active.values)
        names = [cell for row in values for cell in row if isinstance(cell, str)]
        self.assertIn(self.students[12].username, names)
        numeric = [cell for row in values for cell in row if isinstance(cell, (float, int))]
        self.assertIn(.86, numeric)

    def test_full_export_has_supporting_sheets_and_filters(self):
        response = self.report(detail_level='full', search=self.students[0].username)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data['rows']), 1)
        self.assertEqual({sheet['name'] for sheet in response.data['excel_sheets']},
                         {'Grade calculation', 'Panel criteria', 'Peer ratings', 'Feedback'})
        self.assertTrue(response.data['pdf_base64'])
        self.assertEqual(response.data['excel_sheets'][0]['rows'][0]['subject'], self.students[0].get_full_name())

    def test_team_export_uses_team_result_and_member_sheet(self):
        response = self.client.get('/api/reports/team-grade-masterlist/', {
            'scope': 'pit', 'semester_id': self.term.pk, 'pit_event_config_id': self.event.pk,
            'export_format': 'json', 'detail_level': 'full'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['rows'][0]['final'], 88)
        member_sheet = next(sheet for sheet in response.data['excel_sheets'] if sheet['name'] == 'Member grades')
        self.assertEqual(len(member_sheet['rows']), 2)

    def test_report_access_and_semester_cells_match_masterlist(self):
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.report().data['total_rows'], 13)
        self.assertEqual(self.report(year_level='1st Year').status_code, 403)
        self.assertEqual(self.report(scope='capstone').status_code, 403)
        response = self.report(coverage='semester')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIn(f'pit:{self.event.pk}', response.data['rows'][0])
        self.assertIn(f'pit:{self.event2.pk}', response.data['rows'][0])

    def test_detailed_export_contains_real_scoped_criteria_and_received_peer_ratings(self):
        import os
        from pathlib import Path
        self.panel_evidence()
        response = self.report(detail_level='full', search=self.students[0].username)
        self.assertEqual(response.status_code, 200, response.data)
        sheets = {sheet['name']: sheet for sheet in response.data['excel_sheets']}
        self.assertEqual(len(sheets['Panel criteria']['rows']), 4)
        self.assertEqual(len(sheets['Peer ratings']['rows']), 4)
        self.assertTrue(all(row['recipient'] == self.students[0].get_full_name() for row in sheets['Peer ratings']['rows']))
        self.assertEqual(len(sheets['Feedback']['rows']), 2)
        self.assertTrue(response.data['pdf_base64'])
        if os.environ.get('DEFENSYS_CAPTURE_PREVIEW') == '1':
            import base64
            output = Path(__file__).resolve().parents[3] / '.tmp' / 'masterlist-qa'
            output.mkdir(parents=True, exist_ok=True)
            (output / 'student-full.pdf').write_bytes(base64.b64decode(response.data['pdf_base64']))
            (output / 'student-full.xlsx').write_bytes(self.report(detail_level='full', export_format='xlsx').content)

    def test_panel_assignment_does_not_grant_raw_peer_rater_export(self):
        panelists = self.panel_evidence()
        self.client.force_authenticate(panelists[0])
        response = self.report(detail_level='full')
        self.assertEqual(response.status_code, 200, response.data)
        sheet = next(s for s in response.data['excel_sheets'] if s['name'] == 'Peer ratings')
        self.assertEqual(len(sheet['rows']), 2)
        self.assertTrue(all(row['evaluator'] == 'Aggregate only' for row in sheet['rows']))
