from rest_framework.test import APITestCase

from defense.stages.models import DefenseStage
from . import tests as fixtures
from .models import StudentTeam
from .concept_policy import resolve_policy


class ConceptImportTests(APITestCase):
    setUp = fixtures.StudentTeamApiTests.setUp
    _activate_capstone_intake_semester = fixtures.StudentTeamApiTests._activate_capstone_intake_semester

    def rows(self):
        return [{'team_name': 'Unassigned team', 'level': StudentTeam.LEVEL_3_CAPSTONE,
            'section': 'BSIT-3A', 'member_ids': ['Juan Dela Cruz'], 'leader_id': 'Juan Dela Cruz'},
            {'team_name': 'Assigned module team', 'project_title': 'Patient Records',
             'system_name': 'Hospital Management System', 'level': StudentTeam.LEVEL_3_CAPSTONE,
             'section': 'BSIT-3A', 'member_ids': ['Maria Santos'], 'leader_id': 'Maria Santos'}]

    def test_manual_creation_retains_first_title_and_requires_configured_four(self):
        from repository.deliverables import concepts
        self._activate_capstone_intake_semester()
        stage = DefenseStage.objects.first()
        stage.concept_config = {'enabled': True, 'required_count': 4}
        stage.save()
        response = self.client.post('/api/teams/', {'name': 'Manual four concepts',
            'project_title': 'Staff supplied idea', 'section': 'BSIT-3A',
            'level': StudentTeam.LEVEL_3_CAPSTONE, 'leader_id': self.student_1.pk,
            'member_ids': [self.student_1.pk]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        team = StudentTeam.objects.get(name='Manual four concepts')
        self.assertEqual([c['title'] for c in concepts.get_round(team, stage).concepts], ['Staff supplied idea', '', '', ''])

    def test_admin_can_supply_first_title_before_concept_work_starts(self):
        from repository.deliverables import concepts
        self._activate_capstone_intake_semester()
        response = self.client.post('/api/teams/', {'name': 'Later title team',
            'project_title': '', 'section': 'BSIT-3A', 'level': StudentTeam.LEVEL_3_CAPSTONE,
            'leader_id': self.student_1.pk, 'member_ids': [self.student_1.pk]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        team = StudentTeam.objects.get(name='Later title team')
        stage = DefenseStage.objects.first()
        stage.concept_config = {'enabled': True, 'required_count': 3}
        stage.save()
        payload = {'name': team.name, 'project_title': 'Admin supplied later', 'section': team.section,
            'level': team.level, 'leader_id': self.student_1.pk, 'member_ids': [self.student_1.pk]}
        updated = self.client.patch(f'/api/teams/{team.pk}/', payload, format='json')
        self.assertEqual(updated.status_code, 200, updated.data)
        team.refresh_from_db()
        self.assertTrue(team.project_pending)
        self.assertEqual([c['title'] for c in concepts.get_round(team, stage).concepts], ['Admin supplied later', '', ''])

    def test_normalized_file_upload_headers_work_in_preview_and_commit(self):
        self._activate_capstone_intake_semester()
        # readTeamImportFiles normalizes CSV and XLSX to this row-based schema.
        data = {'teams': [self.rows()[1]], 'csv_columns': [
            'team_name', 'project_title', 'level', 'year_level', 'member_ids', 'leader_id',
            'adviser_name', 'instructor_name', 'section', 'system_name', 'project_manager', 'group_key']}
        preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
        self.assertTrue(preview.data['rows'][0]['ready'], preview.data)
        self.assertFalse(StudentTeam.objects.exists())
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.data['created_count'], 1, imported.data)

    def test_supported_member_header_aliases_are_accepted_by_backend(self):
        self._activate_capstone_intake_semester()
        for member_header in ('Team Members', 'Members', 'Names', 'Student Name',
                              'student_name', 'Student Names', 'Student', 'Students'):
            with self.subTest(header=member_header):
                preview = self.client.post('/api/teams/bulk-import/preview/', {
                    'teams': [self.rows()[1]],
                    'csv_columns': ['Team Name:', 'Capstone Project', 'Section', 'Adviser', member_header],
                }, format='json')
                self.assertTrue(preview.data['rows'][0]['ready'], preview.data)

    def test_unrecognized_grouping_headers_still_block_preview_and_commit(self):
        self._activate_capstone_intake_semester()
        data = {'teams': [self.rows()[1]], 'csv_columns': ['Title', 'Students']}
        preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
        self.assertFalse(preview.data['rows'][0]['ready'])
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.data['created_count'], 0, imported.data)

    def test_preview_and_import_keep_assignment_intent_for_mixed_section(self):
        self._activate_capstone_intake_semester()
        stage = DefenseStage.objects.first()
        stage.concept_config = {'enabled': True, 'required_count': 3}
        stage.save()
        data = {'teams': self.rows()}
        preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual([r['concept_requirement']['required_count'] for r in preview.data['rows']], [3, 3])
        self.assertEqual(preview.data['summary']['concept_sections']['BSIT-3A'], {'assigned': 0, 'proposals': 2})
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.status_code, 201, imported.data)
        self.assertEqual(imported.data['created_count'], 2, imported.data)
        unassigned = StudentTeam.objects.get(name='Unassigned team')
        assigned = StudentTeam.objects.get(name='Assigned module team')
        self.assertEqual(unassigned.concept_assignment['mode'], 'proposals')
        self.assertEqual(assigned.concept_assignment['assigned_title'], 'Patient Records')
        self.assertEqual(resolve_policy(unassigned, stage)['required_count'], 3)
        self.assertEqual(resolve_policy(assigned, stage)['required_count'], 3)
        from repository.deliverables import concepts
        self.assertEqual([c['title'] for c in concepts.get_round(assigned, stage).concepts], ['Patient Records', '', ''])
        self.client.force_authenticate(assigned.leader)
        task = self.client.get('/api/teams/my-setup/').data['teams'][0]['concept_tasks'][0]
        self.assertEqual((task['required_count'], task['remaining_count']), (3, 2))

    def test_optional_column_and_empty_value_both_import_as_proposals(self):
        self._activate_capstone_intake_semester()
        rows = self.rows()
        rows[1]['project_title'] = '   '
        data = {'teams': rows, 'csv_columns': ['team_name', 'team_members', 'section']}
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.status_code, 201, imported.data)
        self.assertEqual(imported.data['created_count'], 2, imported.data)
        self.assertEqual(set(StudentTeam.objects.values_list('concept_assignment__mode', flat=True)), {'proposals'})

    def test_missing_project_import_prompts_leader_for_three_concepts(self):
        from repository.deliverables import concepts
        self._activate_capstone_intake_semester()
        # The feature flag, not a fixed stage name, provides the concept task.
        stage = DefenseStage.objects.first()
        stage.label = 'Research Idea Hearing'
        stage.concept_config = {'enabled': True, 'required_count': 3}
        stage.save()
        for title_fields in ({}, {'project_title': ''}):
            with self.subTest(project_column_present=bool(title_fields)):
                row = {**self.rows()[0], **title_fields}
                data = {'teams': [row], 'csv_columns': [
                    'team_name', 'level', 'year_level', 'member_ids', 'leader_id',
                    'adviser_name', 'instructor_name', 'section', 'group_key', *title_fields]}
                preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
                self.assertTrue(preview.data['rows'][0]['ready'], preview.data)
                self.assertEqual(preview.data['rows'][0]['concept_requirement']['required_count'], 3)
                self.assertFalse(StudentTeam.objects.exists())
                imported = self.client.post('/api/teams/bulk-import/', data, format='json')
                self.assertEqual(imported.data['created_count'], 1, imported.data)
                team = StudentTeam.objects.get()
                self.assertTrue(team.project_pending)
                self.assertEqual(team.project_title, '')
                self.client.force_authenticate(self.student_1)
                tasks = self.client.get('/api/teams/my-setup/').data['teams']
                task = next(t for t in tasks if t['id'] == team.pk)
                self.assertFalse(task['needs_name'])
                self.assertEqual(task['concept_tasks'][0]['stage_label'], stage.label)
                self.assertEqual(task['concept_tasks'][0]['required_count'], 3)
                current = concepts.get_round(team, stage)
                self.assertEqual(len(current.concepts), 3)
                self.assertTrue(all(c['title'] == '' for c in current.concepts))
                from .models import StudentCapstonePlacement, StudentCapstoneParticipation
                StudentCapstonePlacement.objects.all().delete()
                StudentCapstoneParticipation.objects.all().delete()
                StudentTeam.objects.all().delete()
                self.client.force_authenticate(self.admin)
                self.client.force_authenticate(self.admin)

    def test_old_assigned_section_does_not_block_imports_without_titles(self):
        from .models import SectionAssignment
        from .concept_policy import context_key
        self._activate_capstone_intake_semester()
        stage = DefenseStage.objects.first()
        stage.concept_config = {'enabled': True, 'required_count': 3}
        stage.save()
        SectionAssignment.objects.create(section='BSIT-3A', semester=self.second_semester,
            year_level='3rd Year', concept_policies={context_key(stage): {'mode': 'assigned'}})
        data = {'teams': [self.rows()[0]]}
        preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
        self.assertTrue(preview.data['rows'][0]['ready'])
        self.assertEqual(preview.data['rows'][0]['concept_requirement']['required_count'], 3)
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.data['created_count'], 1)

    def test_section_proposals_policy_does_not_silently_discard_retained_title(self):
        from .models import SectionAssignment
        from .concept_policy import context_key
        self._activate_capstone_intake_semester()
        stage = DefenseStage.objects.first()
        stage.concept_config = {'enabled': True, 'required_count': 2}
        stage.save()
        SectionAssignment.objects.create(section='BSIT-3A', semester=self.second_semester,
            year_level='3rd Year', concept_policies={context_key(stage): {'mode': 'proposals', 'required_count': 2}})
        data = {'teams': [self.rows()[1]]}
        preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
        self.assertTrue(preview.data['rows'][0]['ready'])
        self.assertEqual(preview.data['rows'][0]['concept_requirement']['required_count'], 2)
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.data['created_count'], 1)
        from repository.deliverables import concepts
        self.assertEqual([c['title'] for c in concepts.get_round(StudentTeam.objects.get(), stage).concepts], ['Patient Records', ''])
