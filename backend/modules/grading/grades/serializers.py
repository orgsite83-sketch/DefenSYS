from rest_framework import serializers

from grading.rubrics.models import Rubric
from .models import GradeBreakdown, StudentStageGrade, TeamGrade
from .services import display_name


class GradeBreakdownSerializer(serializers.ModelSerializer):
    rubric_name = serializers.CharField(source='rubric.name', read_only=True, allow_null=True)
    normalized_score = serializers.DecimalField(max_digits=5, decimal_places=2, read_only=True)

    class Meta:
        model = GradeBreakdown
        fields = [
            'id',
            'evaluation_type',
            'rubric_name',
            'criterion_name',
            'score',
            'max_score',
            'normalized_score',
            'remarks',
            'display_order',
        ]


class StudentStageGradeSerializer(serializers.ModelSerializer):
    student_id = serializers.IntegerField(source='student.id', read_only=True)
    username = serializers.CharField(source='student.username', read_only=True)
    student_name = serializers.SerializerMethodField()

    class Meta:
        model = StudentStageGrade
        fields = [
            'id',
            'student_id',
            'username',
            'student_name',
            'panel_score',
            'adviser_score',
            'peer_score',
            'final_grade',
        ]

    def get_student_name(self, obj):
        return display_name(obj.student)


class TeamGradeSerializer(serializers.ModelSerializer):
    schedule_id = serializers.IntegerField(source='schedule.id', read_only=True, allow_null=True)
    defense_stage_id = serializers.IntegerField(source='defense_stage.id', read_only=True, allow_null=True)
    pit_event_config_id = serializers.IntegerField(source='pit_event_config.id', read_only=True, allow_null=True)
    defense_status = serializers.CharField(source='schedule.status', read_only=True, allow_null=True)
    scheduled_date = serializers.DateField(source='schedule.scheduled_date', read_only=True, allow_null=True)
    room = serializers.CharField(source='schedule.room', read_only=True, allow_null=True)
    team_id = serializers.IntegerField(source='team.id', read_only=True)
    team_name = serializers.CharField(source='team.name', read_only=True)
    project_title = serializers.CharField(source='team.project_title', read_only=True)
    team_level = serializers.CharField(source='team.level', read_only=True)
    year_level = serializers.CharField(source='team.year_level', read_only=True)
    team_status = serializers.CharField(source='team.status', read_only=True)
    adviser_name = serializers.SerializerMethodField()
    leader_name = serializers.SerializerMethodField()
    semester_id = serializers.IntegerField(source='semester.id', read_only=True)
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)
    weights = serializers.SerializerMethodField()
    result = serializers.CharField(read_only=True)
    panelists = serializers.SerializerMethodField()
    breakdowns = GradeBreakdownSerializer(many=True, read_only=True)
    peer_per_student = StudentStageGradeSerializer(source='student_grades', many=True, read_only=True)
    published_by_name = serializers.SerializerMethodField()
    peer_eval_complete = serializers.SerializerMethodField()
    peer_submissions_submitted = serializers.SerializerMethodField()
    peer_submissions_required = serializers.SerializerMethodField()
    peer_evaluators_done = serializers.SerializerMethodField()
    peer_evaluators_total = serializers.SerializerMethodField()
    panel_complete = serializers.SerializerMethodField()
    adviser_complete = serializers.SerializerMethodField()
    adviser_required = serializers.SerializerMethodField()
    grading_ready = serializers.SerializerMethodField()
    missing_components = serializers.SerializerMethodField()
    rubric_target_type = serializers.SerializerMethodField()

    class Meta:
        model = TeamGrade
        fields = [
            'id',
            'schedule_id',
            'defense_stage_id',
            'pit_event_config_id',
            'defense_status',
            'scheduled_date',
            'room',
            'team_id',
            'team_name',
            'project_title',
            'team_level',
            'year_level',
            'team_status',
            'leader_name',
            'adviser_name',
            'semester_id',
            'display_semester',
            'scope',
            'stage_label',
            'panel_score',
            'adviser_score',
            'peer_score',
            'final_grade',
            'weights',
            'status',
            'result',
            'panelists',
            'breakdowns',
            'peer_per_student',
            'peer_eval_complete',
            'peer_submissions_submitted',
            'peer_submissions_required',
            'peer_evaluators_done',
            'peer_evaluators_total',
            'panel_complete',
            'adviser_complete',
            'adviser_required',
            'grading_ready',
            'missing_components',
            'rubric_target_type',
            'published_by_name',
            'published_at',
            'created_at',
            'updated_at',
        ]

    def get_rubric_target_type(self, obj):
        if obj.schedule and obj.schedule.rubric:
            return obj.schedule.rubric.target_type
        return 'team'

    def get_adviser_name(self, obj):
        return display_name(obj.team.adviser)

    def get_leader_name(self, obj):
        return display_name(obj.team.leader)

    def get_weights(self, obj):
        return {
            'panel': obj.panel_weight,
            'adviser': obj.adviser_weight,
            'peer': obj.peer_weight,
        }

    def get_panelists(self, obj):
        if not obj.schedule_id:
            return []
        return [
            {
                'id': assignment.panelist_id,
                'username': assignment.panelist.username,
                'name': display_name(assignment.panelist),
            }
            for assignment in obj.schedule.panel_assignments.all()
        ]

    def get_published_by_name(self, obj):
        return display_name(obj.published_by)

    def get_peer_eval_complete(self, obj):
        from .peer_eval import is_team_peer_eval_complete

        return is_team_peer_eval_complete(obj)

    def get_peer_submissions_submitted(self, obj):
        from .peer_eval import peer_submission_count

        return peer_submission_count(obj)

    def get_peer_submissions_required(self, obj):
        from .peer_eval import required_peer_submission_count

        return required_peer_submission_count(obj.team)

    def get_peer_evaluators_done(self, obj):
        from .peer_eval import peer_completion_summary

        return peer_completion_summary(obj)['evaluators_done']

    def get_peer_evaluators_total(self, obj):
        from .peer_eval import peer_completion_summary

        return peer_completion_summary(obj)['evaluators_total']

    def _grading_readiness(self, obj):
        from .services import team_grading_readiness

        return team_grading_readiness(obj, obj.semester, obj.scope)

    def get_panel_complete(self, obj):
        return self._grading_readiness(obj)['panel_complete']

    def get_adviser_complete(self, obj):
        return self._grading_readiness(obj)['adviser_complete']

    def get_adviser_required(self, obj):
        return self._grading_readiness(obj)['adviser_required']

    def get_grading_ready(self, obj):
        return self._grading_readiness(obj)['ready']

    def get_missing_components(self, obj):
        return self._grading_readiness(obj)['missing_components']


class TeamGradeUpdateSerializer(serializers.Serializer):
    panel_score = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=0,
        max_value=100,
        required=False,
        allow_null=True,
    )
    adviser_score = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=0,
        max_value=100,
        required=False,
        allow_null=True,
    )
    peer_score = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=0,
        max_value=100,
        required=False,
        allow_null=True,
    )
    status = serializers.ChoiceField(
        choices=[choice[0] for choice in TeamGrade.STATUS_CHOICES],
        required=False,
    )

    def validate(self, attrs):
        if not attrs:
            raise serializers.ValidationError('At least one score or status field is required.')
        if attrs.get('status') == TeamGrade.STATUS_PUBLISHED:
            instance = self.context['grade']
            score_map = {
                'panel_score': instance.panel_score,
                'adviser_score': instance.adviser_score,
                'peer_score': instance.peer_score,
            }
            score_map.update({key: value for key, value in attrs.items() if key in score_map})
            missing = [
                field
                for field in instance.required_score_fields
                if score_map.get(field) is None
            ]
            if missing:
                raise serializers.ValidationError({'status': 'Only complete grades can be published.'})
        return attrs

    def save(self):
        grade = self.context['grade']
        for field in ['panel_score', 'adviser_score', 'peer_score']:
            if field in self.validated_data:
                setattr(grade, field, self.validated_data[field])
        if 'status' in self.validated_data and self.validated_data['status'] != TeamGrade.STATUS_PUBLISHED:
            grade.status = self.validated_data['status']
        grade.save()
        from .services import maybe_auto_finalize_passed_grade

        maybe_auto_finalize_passed_grade(grade)
        return grade


class GradeCenterOptionsSerializer(serializers.Serializer):
    statuses = serializers.ListField(child=serializers.CharField())
    year_levels = serializers.ListField(child=serializers.CharField())
    scopes = serializers.ListField(child=serializers.DictField())
