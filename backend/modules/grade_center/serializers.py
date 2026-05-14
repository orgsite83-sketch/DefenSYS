from rest_framework import serializers

from rubric_engine.models import Rubric
from .models import GradeBreakdown, StudentPeerGrade, TeamGrade
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


class StudentPeerGradeSerializer(serializers.ModelSerializer):
    student_id = serializers.IntegerField(source='student.id', read_only=True)
    username = serializers.CharField(source='student.username', read_only=True)
    student_name = serializers.SerializerMethodField()
    normalized_score = serializers.DecimalField(max_digits=5, decimal_places=2, read_only=True)

    class Meta:
        model = StudentPeerGrade
        fields = [
            'id',
            'student_id',
            'username',
            'student_name',
            'average_score',
            'max_score',
            'normalized_score',
        ]

    def get_student_name(self, obj):
        return display_name(obj.student)


class TeamGradeSerializer(serializers.ModelSerializer):
    schedule_id = serializers.IntegerField(source='schedule.id', read_only=True, allow_null=True)
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
    peer_per_student = StudentPeerGradeSerializer(source='peer_member_grades', many=True, read_only=True)
    published_by_name = serializers.SerializerMethodField()

    class Meta:
        model = TeamGrade
        fields = [
            'id',
            'schedule_id',
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
            'published_by_name',
            'published_at',
            'created_at',
            'updated_at',
        ]

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
        return grade


class GradeCenterOptionsSerializer(serializers.Serializer):
    statuses = serializers.ListField(child=serializers.CharField())
    year_levels = serializers.ListField(child=serializers.CharField())
    scopes = serializers.ListField(child=serializers.DictField())
