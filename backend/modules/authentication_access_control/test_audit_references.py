import io
from datetime import date, time

import openpyxl
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage, StageGradingConfig
from student_teams.models import StudentTeam
from user_management.models import ExternalEvaluator, GuestPanelistCode

from .audit import audit_evidence, log_high_impact_action
from .audit_references import AuditReferenceResolver
from .models import SystemAuditLog
from .serializers import SystemAuditLogSerializer


class AuditReferenceTests(APITestCase):
    def setUp(self):
        users = get_user_model()
        self.admin = users.objects.create_user(username='reference-admin', role='admin')
        self.student = users.objects.create_user(username='reference-student', role='student')
        self.faculty = users.objects.create_user(
            username='reference-panel', role='faculty', first_name='Grace', last_name='Hopper',
        )
        self.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2026-2027'), label=Semester.FIRST,
        )
        self.team = StudentTeam.objects.create(
            name='Team Atlas', project_title='Atlas', level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year', semester=self.semester, leader=self.student,
        )
        self.stage = DefenseStage.objects.get(label='Project Proposal')
        self.schedule = DefenseSchedule.objects.create(
            team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=date(2026, 10, 12), start_time=time(9), room='Room 101',
        )
        self.external = ExternalEvaluator.objects.create(name='Maria Santos')
        self.invitation = GuestPanelistCode.objects.create(guest_name=self.external.name, evaluator=self.external)
        self.client.force_authenticate(self.admin)

    def capture(self, **kwargs):
        return log_high_impact_action(
            category=kwargs.pop('category', 'guest_access'),
            action=kwargs.pop('action', 'external_invitation.create'),
            target=kwargs.pop('target', self.invitation), actor=self.admin, strict=True,
            new_values=kwargs.pop('new_values', {
                'semester': self.semester.pk, 'evaluator_id': self.external.pk,
                'schedule_ids': [self.schedule.pk],
            }), **kwargs,
        )

    def test_invitation_has_readable_evaluator_semester_and_schedule_with_raw_ids(self):
        log = self.capture()
        response = self.client.get('/api/audit-logs/')
        row = next(row for row in response.data['audit_logs'] if row['id'] == log.pk)
        self.assertEqual(row['new_values']['schedule_ids'], [self.schedule.pk])
        self.assertEqual(row['display_new_values']['evaluator_id'], f'Maria Santos (ID: {self.external.pk})')
        self.assertIn('1st Semester, A.Y. 2026-2027', row['display_new_values']['semester'])
        schedule = row['display_new_values']['schedule_ids'][0]
        for text in ('Team Atlas', 'Project Proposal', 'Oct 12, 2026', '09:00 AM', f'ID: {self.schedule.pk}'):
            self.assertIn(text, schedule)
        self.assertIn('Maria Santos', row['target_label'])
        self.assertNotIn(self.invitation.code, row['target_label'])
        self.assertEqual(audit_evidence(log)['summary'], '3 field(s) recorded after the action.')

    def test_captured_names_survive_rename_and_schedule_deletion(self):
        log = self.capture()
        self.external.name = 'Renamed Evaluator'
        self.external.save(update_fields=['name'])
        self.team.name = 'Renamed Team'
        self.team.save(update_fields=['name'])
        DefenseSchedule.objects.filter(pk=self.schedule.pk).delete()
        log.refresh_from_db()
        row = SystemAuditLogSerializer(log).data
        self.assertIn('Maria Santos', row['display_new_values']['evaluator_id'])
        self.assertIn('Team Atlas', row['display_new_values']['schedule_ids'][0])
        self.assertNotIn('current record', str(row['display_new_values']))

    def test_before_and_after_panelists_resolve_independently_and_keep_nested_ids(self):
        other = get_user_model().objects.create_user(username='new-panel', role='faculty', first_name='Alan', last_name='Turing')
        log = self.capture(
            category='scheduling', action='schedule.operational_change', target=self.schedule,
            old_values={'panelist_ids': [self.faculty.pk], 'chair_panelist_id': self.faculty.pk},
            new_values={'panelist_ids': [other.pk], 'chair_panelist_id': other.pk,
                        'changes': [{'team_id': self.team.pk, 'student_id': self.student.pk}]},
        )
        row = SystemAuditLogSerializer(log).data
        self.assertIn('Grace Hopper', row['display_old_values']['panelist_ids'][0])
        self.assertIn('Alan Turing', row['display_new_values']['panelist_ids'][0])
        self.assertIn('Team Atlas', row['display_new_values']['changes'][0]['team_id'])
        self.assertEqual(log.new_values['changes'][0]['team_id'], self.team.pk)

    def test_evaluator_ids_use_the_correct_model_for_guest_and_peer_events(self):
        peer = self.capture(category='grade_center', action='grade.peer_reset', new_values={'evaluator_id': self.faculty.pk})
        self.assertIn('Grace Hopper', SystemAuditLogSerializer(peer).data['display_new_values']['evaluator_id'])
        guest = self.capture()
        self.assertIn('Maria Santos', SystemAuditLogSerializer(guest).data['display_new_values']['evaluator_id'])

    def test_grading_settings_target_includes_stage_and_academic_period(self):
        config = StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.semester)
        log = self.capture(target=config, category='grade_center', action='grading.settings_update',
                           new_values={'panel_weight': 50})
        row = SystemAuditLogSerializer(log).data
        self.assertIn('Project Proposal', row['target_label'])
        self.assertIn('1st Semester, A.Y. 2026-2027', row['target_label'])
        self.assertIn('grading settings', row['target_label'])

    def test_target_name_can_be_captured_after_resource_deletion(self):
        identifier = self.schedule.pk
        DefenseSchedule.objects.filter(pk=identifier).delete()
        self.schedule.pk = None
        log = self.capture(target=self.schedule, target_id=identifier, category='scheduling',
                           action='schedule.delete', old_values={'schedule_id': identifier},
                           new_values={'deleted': True})
        row = SystemAuditLogSerializer(log).data
        self.assertIn('Team Atlas', row['target_label'])
        self.assertIn('Team Atlas', row['display_old_values']['schedule_id'])

    def test_reschedule_reference_preserves_the_recorded_before_date(self):
        before = {'schedule_id': self.schedule.pk, 'team_name': 'Team Atlas',
                  'stage_label': 'Project Proposal', 'scheduled_date': '2026-10-10', 'start_time': '08:00:00'}
        log = self.capture(target=self.schedule, category='scheduling', action='schedule.operational_change',
                           old_values=before, new_values={**before, 'scheduled_date': '2026-10-12', 'start_time': '09:00:00'})
        row = SystemAuditLogSerializer(log).data
        self.assertIn('Oct 10, 2026 08:00 AM', row['display_old_values']['schedule_id'])
        self.assertIn('Oct 12, 2026 09:00 AM', row['display_new_values']['schedule_id'])

    def test_legacy_names_are_marked_current_and_missing_ids_remain_identifiable(self):
        log = SystemAuditLog.objects.create(
            category='guest_access', action='external_invitation.create', target_type='GuestPanelistCode',
            target_id=str(self.invitation.pk),
            new_values={'evaluator_id': self.external.pk, 'schedule_ids': [self.schedule.pk, 987654321],
                        'semester': '1st Semester', 'session_id': 'opaque-session'},
        )
        row = SystemAuditLogSerializer(log).data
        self.assertIn('Maria Santos', row['display_new_values']['evaluator_id'])
        self.assertIn('current record', row['display_new_values']['evaluator_id'])
        self.assertIn('Unavailable', row['display_new_values']['schedule_ids'][1])
        self.assertIn('987654321', row['display_new_values']['schedule_ids'][1])
        self.assertEqual(row['display_new_values']['semester'], '1st Semester')
        self.assertEqual(row['display_new_values']['session_id'], 'opaque-session')
        log.refresh_from_db()
        self.assertEqual(log.reference_labels, {})

    def test_existing_snapshot_name_takes_precedence_over_current_name(self):
        log = SystemAuditLog.objects.create(
            category='scheduling', action='schedule.update', target_type='DefenseSchedule',
            target_id=str(self.schedule.pk),
            old_values={'documenter_id': self.faculty.pk, 'documenter_name': 'Historical Name'},
            new_values={'documenter_id': self.faculty.pk, 'documenter_name': 'Grace Hopper'},
        )
        row = SystemAuditLogSerializer(log).data
        self.assertEqual(row['display_old_values']['documenter_id'], f'Historical Name (ID: {self.faculty.pk})')

    def test_lookup_count_is_per_model_for_an_entire_page(self):
        logs = [SystemAuditLog(category='scheduling', action='schedule.update', target_type='Unknown',
                               new_values={'team_id': self.team.pk, 'panelist_ids': [self.faculty.pk]}) for _ in range(100)]
        with self.assertNumQueries(2):
            resolver = AuditReferenceResolver(logs)
            for log in logs:
                self.assertIn('Grace Hopper', resolver.display_values(log, 'new_values')['panelist_ids'][0])

    def test_invalid_and_non_reference_numbers_are_left_unchanged(self):
        values = {'team_id': 'not-an-id', 'semester': False, 'panelist_ids': [],
                  'evaluator_id': 10**100, 'panel_weight': 50, 'revision': 3, 'student_id': 1.5}
        log = self.capture(new_values=values)
        self.assertEqual(SystemAuditLogSerializer(log).data['display_new_values'], values)

    def test_audit_search_matches_saved_reference_names(self):
        log = self.capture()
        response = self.client.get('/api/audit-logs/', {'search': 'Maria Santos'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([row['id'] for row in response.data['audit_logs']], [log.pk])

    def test_export_uses_names_and_retains_raw_evidence(self):
        log = self.capture()
        for export_format in ('json', 'csv', 'pdf'):
            response = self.client.get('/api/reports/audit-trail/', {'log_id': log.pk, 'export_format': export_format})
            self.assertEqual(response.status_code, 200)
            if export_format == 'json':
                self.assertIn('Maria Santos', response.data['rows'][0]['target'])
            elif export_format == 'csv':
                self.assertIn(b'Maria Santos', response.content)
            else:
                self.assertTrue(response.content.startswith(b'%PDF'))
        response = self.client.get('/api/reports/audit-trail/', {'log_id': log.pk, 'export_format': 'xlsx'})
        workbook = openpyxl.load_workbook(io.BytesIO(response.content))
        evidence = workbook['Event Evidence']
        header_row = int(evidence.auto_filter.ref.split(':')[0][1:])
        last_row = openpyxl.utils.range_boundaries(evidence.auto_filter.ref)[3]
        headers = [cell.value for cell in evidence[header_row]]
        rows = [dict(zip(headers, row)) for row in evidence.iter_rows(min_row=header_row + 1, max_row=last_row, values_only=True)]
        evaluator = next(row for row in rows if row['Recorded Field'] == 'evaluator_id')
        self.assertIn('Maria Santos', evaluator['After'])
        self.assertEqual(evaluator['Raw After'], str(self.external.pk))
