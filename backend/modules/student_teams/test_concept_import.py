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

    def test_preview_and_import_keep_assignment_intent_for_mixed_section(self):
        self._activate_capstone_intake_semester()
        stage = DefenseStage.objects.first()
        stage.concept_config = {'enabled': True, 'required_count': 3}
        stage.save()
        data = {'teams': self.rows()}
        preview = self.client.post('/api/teams/bulk-import/preview/', data, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual([r['concept_requirement']['required_count'] for r in preview.data['rows']], [3, 1])
        self.assertEqual(preview.data['summary']['concept_sections']['BSIT-3A'], {'assigned': 1, 'proposals': 1})
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.status_code, 201, imported.data)
        self.assertEqual(imported.data['created_count'], 2, imported.data)
        unassigned = StudentTeam.objects.get(name='Unassigned team')
        assigned = StudentTeam.objects.get(name='Assigned module team')
        self.assertEqual(unassigned.concept_assignment['mode'], 'proposals')
        self.assertEqual(assigned.concept_assignment['assigned_title'], 'Patient Records')
        self.assertEqual(resolve_policy(unassigned, stage)['required_count'], 3)
        self.assertEqual(resolve_policy(assigned, stage)['required_count'], 1)

    def test_optional_column_and_empty_value_both_import_as_proposals(self):
        self._activate_capstone_intake_semester()
        rows = self.rows()
        rows[1]['project_title'] = '   '
        data = {'teams': rows, 'csv_columns': ['team_name', 'team_members', 'section']}
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.status_code, 201, imported.data)
        self.assertEqual(imported.data['created_count'], 2, imported.data)
        self.assertEqual(set(StudentTeam.objects.values_list('concept_assignment__mode', flat=True)), {'proposals'})

    def test_assigned_section_rejects_future_imports_without_a_team_title(self):
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
        self.assertFalse(preview.data['rows'][0]['ready'])
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.data['created_count'], 0)

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
        self.assertFalse(preview.data['rows'][0]['ready'])
        self.assertIn('policy conflicts', ' '.join(preview.data['rows'][0]['issues']))
        imported = self.client.post('/api/teams/bulk-import/', data, format='json')
        self.assertEqual(imported.data['created_count'], 0)
