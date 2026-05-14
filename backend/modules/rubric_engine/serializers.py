from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import serializers

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from defense_stages.models import DefenseStage
from defense_stages.serializers import DefenseStageSerializer
from .models import Rubric, RubricCriterion, default_max_score


User = get_user_model()


def display_name(user):
    if user is None:
        return None
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


class RubricCriterionSerializer(serializers.ModelSerializer):
    class Meta:
        model = RubricCriterion
        fields = [
            'id',
            'name',
            'description',
            'scale',
            'max_score',
            'weight',
            'display_order',
        ]
        read_only_fields = ['id']


class RubricSerializer(serializers.ModelSerializer):
    semester_id = serializers.IntegerField(source='semester.id', read_only=True)
    semester = serializers.CharField(source='semester.label', read_only=True)
    school_year = serializers.CharField(source='semester.school_year.label', read_only=True)
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)
    defense_stage_id = serializers.IntegerField(source='defense_stage.id', read_only=True, allow_null=True)
    defense_stage_label = serializers.CharField(source='defense_stage.label', read_only=True, allow_null=True)
    context_label = serializers.CharField(read_only=True)
    created_by_name = serializers.SerializerMethodField()
    criteria_count = serializers.IntegerField(read_only=True)
    criteria = RubricCriterionSerializer(many=True, read_only=True)
    weights = serializers.SerializerMethodField()

    class Meta:
        model = Rubric
        fields = [
            'id',
            'name',
            'scope',
            'semester_id',
            'semester',
            'school_year',
            'display_semester',
            'defense_stage_id',
            'defense_stage_label',
            'event_name',
            'context_label',
            'evaluation_type',
            'scale',
            'status',
            'is_locked',
            'panel_weight',
            'adviser_weight',
            'peer_weight',
            'weights',
            'criteria_count',
            'criteria',
            'created_by_name',
            'created_at',
            'updated_at',
        ]

    def get_created_by_name(self, obj):
        return display_name(obj.created_by)

    def get_weights(self, obj):
        return {
            'panel': obj.panel_weight,
            'adviser': obj.adviser_weight,
            'peer': obj.peer_weight,
        }


class RubricWriteSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=160)
    scope = serializers.ChoiceField(choices=[choice[0] for choice in Rubric.SCOPE_CHOICES], default=Rubric.SCOPE_CAPSTONE)
    semester_id = serializers.IntegerField(required=False)
    defense_stage_id = serializers.IntegerField(required=False, allow_null=True)
    event_name = serializers.CharField(required=False, allow_blank=True, max_length=120)
    evaluation_type = serializers.ChoiceField(choices=[choice[0] for choice in Rubric.EVALUATION_TYPE_CHOICES])
    scale = serializers.ChoiceField(choices=[choice[0] for choice in Rubric.SCALE_CHOICES], default=Rubric.SCALE_10)
    status = serializers.ChoiceField(choices=[choice[0] for choice in Rubric.STATUS_CHOICES], default=Rubric.STATUS_DRAFT)
    panel_weight = serializers.IntegerField(required=False, min_value=0, max_value=100)
    adviser_weight = serializers.IntegerField(required=False, min_value=0, max_value=100)
    peer_weight = serializers.IntegerField(required=False, min_value=0, max_value=100)
    criteria = RubricCriterionSerializer(many=True, min_length=1)

    def validate(self, attrs):
        attrs['name'] = attrs['name'].strip()
        if not attrs['name']:
            raise serializers.ValidationError({'name': 'Rubric name is required.'})

        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if user and getattr(user, 'is_pit_lead', False) and getattr(user, 'role', None) != 'admin':
            attrs['scope'] = Rubric.SCOPE_PIT

        attrs['semester'] = self._resolve_semester(attrs)
        scope = attrs.get('scope', Rubric.SCOPE_CAPSTONE)
        attrs['defense_stage'] = self._resolve_defense_stage(attrs, scope)
        attrs['event_name'] = (attrs.get('event_name') or '').strip()

        if scope == Rubric.SCOPE_PIT:
            if attrs['evaluation_type'] == Rubric.EVAL_ADVISER:
                raise serializers.ValidationError({'evaluation_type': 'PIT rubrics do not support adviser evaluation.'})
            if not attrs['event_name']:
                raise serializers.ValidationError({'event_name': 'PIT rubrics require an event name.'})
            attrs['defense_stage'] = None
            attrs['panel_weight'] = attrs.get('panel_weight', 80)
            attrs['adviser_weight'] = 0
            attrs['peer_weight'] = attrs.get('peer_weight', 20)
        else:
            if attrs['defense_stage'] is None:
                raise serializers.ValidationError({'defense_stage_id': 'Capstone rubrics require a defense stage.'})
            attrs['event_name'] = ''
            attrs['panel_weight'] = attrs.get('panel_weight', 50)
            attrs['adviser_weight'] = attrs.get('adviser_weight', 30)
            attrs['peer_weight'] = attrs.get('peer_weight', 20)

        self._validate_weights(attrs)
        self._validate_duplicate(attrs)
        attrs['criteria'] = self._normalized_criteria(attrs['criteria'])
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        criteria = validated_data.pop('criteria')
        rubric = Rubric.objects.create(
            name=validated_data['name'],
            scope=validated_data['scope'],
            semester=validated_data['semester'],
            defense_stage=validated_data.get('defense_stage'),
            event_name=validated_data.get('event_name', ''),
            evaluation_type=validated_data['evaluation_type'],
            scale=validated_data.get('scale', Rubric.SCALE_10),
            status=validated_data.get('status', Rubric.STATUS_DRAFT),
            panel_weight=validated_data['panel_weight'],
            adviser_weight=validated_data['adviser_weight'],
            peer_weight=validated_data['peer_weight'],
            created_by=getattr(self.context.get('request'), 'user', None),
        )
        self._sync_criteria(rubric, criteria)
        return rubric

    @transaction.atomic
    def update(self, instance, validated_data):
        criteria = validated_data.pop('criteria')
        instance.name = validated_data['name']
        instance.scope = validated_data['scope']
        instance.semester = validated_data['semester']
        instance.defense_stage = validated_data.get('defense_stage')
        instance.event_name = validated_data.get('event_name', '')
        instance.evaluation_type = validated_data['evaluation_type']
        instance.scale = validated_data.get('scale', Rubric.SCALE_10)
        instance.status = validated_data.get('status', instance.status)
        instance.panel_weight = validated_data['panel_weight']
        instance.adviser_weight = validated_data['adviser_weight']
        instance.peer_weight = validated_data['peer_weight']
        instance.is_locked = instance.status == Rubric.STATUS_PUBLISHED
        instance.save()
        self._sync_criteria(instance, criteria)
        return instance

    def _resolve_semester(self, attrs):
        semester_id = attrs.get('semester_id')
        if semester_id:
            try:
                return Semester.objects.select_related('school_year').get(pk=semester_id)
            except Semester.DoesNotExist as exc:
                raise serializers.ValidationError({'semester_id': 'Semester does not exist.'}) from exc

        semester = Semester.objects.select_related('school_year').filter(is_active=True).first()
        if semester is None:
            raise serializers.ValidationError({'semester_id': 'No active semester is configured.'})
        return semester

    def _resolve_defense_stage(self, attrs, scope):
        if scope == Rubric.SCOPE_PIT:
            return None

        stage_id = attrs.get('defense_stage_id')
        if not stage_id:
            return None

        try:
            return DefenseStage.objects.get(pk=stage_id, is_active=True)
        except DefenseStage.DoesNotExist as exc:
            raise serializers.ValidationError({'defense_stage_id': 'Defense stage does not exist or is inactive.'}) from exc

    def _validate_weights(self, attrs):
        total = attrs['panel_weight'] + attrs['adviser_weight'] + attrs['peer_weight']
        if total != 100:
            raise serializers.ValidationError({'weights': 'Panel, adviser, and peer weights must total 100%.'})

    def _validate_duplicate(self, attrs):
        queryset = Rubric.objects.filter(
            semester=attrs['semester'],
            name__iexact=attrs['name'],
        )
        if self.instance is not None:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError({'name': 'A rubric with this name already exists for this semester.'})

    def _normalized_criteria(self, criteria):
        normalized = []
        seen_names = set()
        for index, item in enumerate(criteria):
            name = item['name'].strip()
            if not name:
                continue
            key = name.lower()
            if key in seen_names:
                raise serializers.ValidationError({'criteria': f'Duplicate criterion name: {name}.'})
            seen_names.add(key)
            scale = item.get('scale') or Rubric.SCALE_10
            normalized.append({
                'name': name,
                'description': (item.get('description') or '').strip(),
                'scale': scale,
                'max_score': item.get('max_score') or default_max_score(scale),
                'weight': item.get('weight', 1),
                'display_order': item.get('display_order', index),
            })

        if not normalized:
            raise serializers.ValidationError({'criteria': 'At least one criterion is required.'})
        return normalized

    def _sync_criteria(self, rubric, criteria):
        rubric.criteria.all().delete()
        RubricCriterion.objects.bulk_create([
            RubricCriterion(rubric=rubric, **item)
            for item in criteria
        ])


class RubricWeightsSerializer(serializers.Serializer):
    panel_weight = serializers.IntegerField(min_value=0, max_value=100)
    adviser_weight = serializers.IntegerField(min_value=0, max_value=100, required=False)
    peer_weight = serializers.IntegerField(min_value=0, max_value=100)

    def validate(self, attrs):
        rubric = self.context['rubric']
        adviser_weight = attrs.get('adviser_weight', 0 if rubric.scope == Rubric.SCOPE_PIT else rubric.adviser_weight)
        if rubric.scope == Rubric.SCOPE_PIT:
            adviser_weight = 0
        total = attrs['panel_weight'] + adviser_weight + attrs['peer_weight']
        if total != 100:
            raise serializers.ValidationError({'weights': 'Weights must total 100%.'})
        attrs['adviser_weight'] = adviser_weight
        return attrs

    def save(self):
        rubric = self.context['rubric']
        rubric.panel_weight = self.validated_data['panel_weight']
        rubric.adviser_weight = self.validated_data['adviser_weight']
        rubric.peer_weight = self.validated_data['peer_weight']
        rubric.save()
        return rubric


class RubricOptionsSerializer(serializers.Serializer):
    active_semester = SemesterSerializer(allow_null=True)
    semesters = SemesterSerializer(many=True)
    defense_stages = DefenseStageSerializer(many=True)
