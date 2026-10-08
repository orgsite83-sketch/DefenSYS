from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.test import SimpleTestCase, TestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from defense.stages.readiness import stage_setup_readiness
from defense.stages.serializers import DefenseStageSerializer
from grading.rubrics.models import Rubric


class StageSetupReadinessTests(SimpleTestCase):
    def setUp(self):
        self.stage = SimpleNamespace(
            is_presentation_only=False,
            deliverables=Mock(),
        )
        self.stage.deliverables.exists.return_value = True
        self.semester = SimpleNamespace(
            capstone_adviser_grading_enabled=True,
            capstone_peer_evaluation_enabled=True,
        )
        self.config = SimpleNamespace(
            panel_weight=50, adviser_weight=30, peer_weight=20,
            panel_rubric=self.rubric('panel'),
            adviser_rubric=self.rubric('adviser'),
            peer_rubric=self.rubric('peer'),
        )

    def rubric(self, role, status='published'):
        return SimpleNamespace(status=status, scope='capstone', evaluation_type=role)

    def readiness(self):
        return stage_setup_readiness(self.stage, self.config, self.semester)

    def test_missing_weighted_rubric_is_reported_even_with_other_rubrics(self):
        self.config.peer_rubric = None
        result = self.readiness()
        self.assertFalse(result['ready'])
        self.assertEqual(result['issues'], ['Attach a peer evaluation rubric.'])

    def test_disabled_and_zero_weight_groups_do_not_require_rubrics(self):
        self.semester.capstone_peer_evaluation_enabled = False
        self.config.peer_rubric = None
        self.config.adviser_weight = 0
        self.config.panel_weight = 80
        self.config.adviser_rubric = None
        result = self.readiness()
        self.assertTrue(result['ready'])
        self.assertEqual(result['required_rubric_roles'], ['panel'])

    def test_presentation_only_has_no_upload_requirement(self):
        self.stage.deliverables.exists.return_value = False
        self.assertFalse(self.readiness()['ready'])
        self.stage.is_presentation_only = True
        self.assertTrue(self.readiness()['ready'])

    def test_signed_minutes_do_not_replace_student_upload_configuration(self):
        self.stage.minutes_required = True
        self.stage.deliverables.exists.return_value = False
        self.assertIn('Add deliverable requirements or select presentation only.', self.readiness()['issues'])

    def test_unpublished_and_wrong_role_rubrics_are_reported(self):
        self.config.panel_rubric = self.rubric('panel', status='draft')
        self.config.peer_rubric = self.rubric('adviser')
        self.assertEqual(self.readiness()['issues'], [
            'Publish the panel evaluation rubric.',
            'Choose a Capstone peer evaluation rubric.',
        ])

    def test_no_active_semester_or_missing_config_is_not_ready(self):
        result = stage_setup_readiness(self.stage, None, None)
        self.assertEqual(result['issues'], ['Activate a semester to configure grading.'])
        result = stage_setup_readiness(self.stage, None, self.semester)
        self.assertFalse(result['ready'])

    def test_invalid_weights_do_not_show_ready(self):
        self.config.panel_weight = 60
        self.assertIn('Grade weights must total 100%.', self.readiness()['issues'])


class StageReadinessSerializerTests(TestCase):
    def test_lock_and_publication_do_not_imply_completion_or_setup_readiness(self):
        year = SchoolYear.objects.create(label='2040-2041')
        semester = Semester.objects.create(school_year=year, label='1st Semester')
        stage = DefenseStage.objects.create(label='Readiness test stage', is_active=True)
        StageDeliverable.objects.create(defense_stage=stage, deliverable_id='PRE', label='Proposal')
        config = StageGradingConfig.objects.create(defense_stage=stage, semester=semester)
        rubric = Rubric.objects.create(
            name='Readiness panel rubric', scope='capstone',
            evaluation_type='panel', status='published', defense_stage=stage, semester=semester,
        )
        config.panel_rubric = rubric
        config.save()
        with patch('defense.stages.serializers.check_stage_locked', return_value=(True, 'Scheduled defenses.')):
            data = DefenseStageSerializer(stage, context={
                'semester': semester, 'ordered_stages': [stage],
            }).data
        self.assertTrue(data['is_active'])
        self.assertTrue(data['is_locked'])
        self.assertFalse(data['is_officially_complete'])
        # Semester switches determine which additional rubrics are required.
        self.assertEqual(data['setup_readiness']['ready'], not (
            semester.capstone_adviser_grading_enabled or semester.capstone_peer_evaluation_enabled
        ))
        self.assertIn('panel', data['setup_readiness']['required_rubric_roles'])
