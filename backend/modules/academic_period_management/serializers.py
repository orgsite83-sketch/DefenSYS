from rest_framework import serializers
from django.core.exceptions import ValidationError as DjangoValidationError

from .models import SCHOOL_YEAR_LOCK_REASON, SchoolYear, Semester, validate_school_year_label


class SemesterActivationSerializer(serializers.Serializer):
    force = serializers.BooleanField(default=False)
    reason = serializers.CharField(required=False, allow_blank=True, default='', max_length=3000)
    decisions = serializers.ListField(child=serializers.DictField(), required=False, default=list)
    preview_revision = serializers.CharField(required=False, allow_blank=True, default='', max_length=64)
    request_id = serializers.CharField(required=False, allow_null=True, max_length=64)


class SemesterSerializer(serializers.ModelSerializer):
    school_year_id = serializers.IntegerField(source='school_year.id', read_only=True)
    school_year = serializers.CharField(source='school_year.label', read_only=True)
    display_name = serializers.CharField(read_only=True)

    class Meta:
        model = Semester
        fields = [
            'id',
            'label',
            'is_active',
            'starts_on',
            'ends_on',
            'school_year_id',
            'school_year',
            'display_name',
            'capstone_peer_evaluation_enabled',
            'capstone_adviser_grading_enabled',
            'capstone_team_creation_enabled',
            'capstone_program_phase',
        ]


class SchoolYearSerializer(serializers.ModelSerializer):
    school_year = serializers.CharField(source='label', read_only=True)
    semesters = SemesterSerializer(many=True, read_only=True)
    can_edit_label = serializers.BooleanField(read_only=True)
    edit_lock_reason = serializers.SerializerMethodField()

    def get_edit_lock_reason(self, obj):
        return '' if obj.can_edit_label else SCHOOL_YEAR_LOCK_REASON

    class Meta:
        model = SchoolYear
        fields = ['id', 'label', 'school_year', 'semesters', 'created_at',
                  'can_edit_label', 'edit_lock_reason']


class SchoolYearCreateSerializer(serializers.Serializer):
    label = serializers.CharField(required=False, allow_blank=False, max_length=9)
    school_year = serializers.CharField(required=False, allow_blank=False, max_length=9)

    def validate(self, attrs):
        label = (attrs.get('label') or attrs.get('school_year') or '').strip()
        if not label:
            raise serializers.ValidationError({'school_year': 'This field is required.'})

        try:
            validate_school_year_label(label)
        except Exception as exc:
            raise serializers.ValidationError({'school_year': exc.messages}) from exc

        if SchoolYear.objects.filter(label=label).exists():
            raise serializers.ValidationError({'school_year': 'This school year already exists.'})

        attrs['label'] = label
        return attrs

    def create(self, validated_data):
        return SchoolYear.objects.create(label=validated_data['label'])


class SchoolYearUpdateSerializer(serializers.Serializer):
    label = serializers.CharField(required=False, allow_blank=False, max_length=9)
    school_year = serializers.CharField(required=False, allow_blank=False, max_length=9)

    def validate(self, attrs):
        label = (attrs.get('label') or attrs.get('school_year') or '').strip()
        if not label:
            raise serializers.ValidationError({'school_year': 'This field is required.'})

        try:
            validate_school_year_label(label)
        except Exception as exc:
            raise serializers.ValidationError({'school_year': exc.messages}) from exc

        instance = getattr(self, 'instance', None)
        if instance and instance.label != label and not instance.can_edit_label:
            raise serializers.ValidationError({'school_year': SCHOOL_YEAR_LOCK_REASON})
        qs = SchoolYear.objects.filter(label=label)
        if instance:
            qs = qs.exclude(pk=instance.pk)
        if qs.exists():
            raise serializers.ValidationError({'school_year': 'This school year already exists.'})

        attrs['label'] = label
        return attrs

    def update(self, instance, validated_data):
        instance.label = validated_data['label']
        try:
            instance.save(update_fields=['label'])
        except DjangoValidationError as exc:
            raise serializers.ValidationError({'school_year': exc.messages}) from exc
        return instance


class SemesterCalendarSerializer(serializers.Serializer):
    starts_on = serializers.DateField()
    ends_on = serializers.DateField()

    def validate(self, attrs):
        from .calendar import validate_calendar
        instance = self.context.get('semester')
        validate_calendar(attrs.get('starts_on', getattr(instance, 'starts_on', None)),
                          attrs.get('ends_on', getattr(instance, 'ends_on', None)))
        return attrs


class SemesterCreateSerializer(SemesterCalendarSerializer):
    label = serializers.ChoiceField(choices=[choice[0] for choice in Semester.TERM_CHOICES])
    set_active = serializers.BooleanField(default=False)
    is_active = serializers.BooleanField(required=False, write_only=True)
    active = serializers.BooleanField(required=False, write_only=True)
    force = serializers.BooleanField(default=False)
    reason = serializers.CharField(required=False, allow_blank=True, default='', max_length=3000)
    decisions = serializers.ListField(child=serializers.DictField(), required=False, default=list)
    preview_revision = serializers.CharField(required=False, allow_blank=True, default='', max_length=64)
    request_id = serializers.CharField(required=False, allow_null=True, max_length=64)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        aliases = [attrs.pop(name) for name in ('is_active', 'active') if name in attrs]
        if aliases:
            if len(set(aliases)) != 1 or ('set_active' in self.initial_data and attrs['set_active'] != aliases[0]):
                raise serializers.ValidationError({'set_active': 'Provide one consistent activation choice.'})
            attrs['set_active'] = aliases[0]
        school_year = self.context['school_year']
        label = attrs['label']
        if (not attrs.get('set_active') and
                Semester.objects.filter(school_year=school_year, label=label).exists()):
            raise serializers.ValidationError({'label': 'This semester already exists for the selected school year.'})
        return attrs

    def create(self, validated_data):
        from .services import create_semester
        return create_semester(self.context['school_year'], self.context['request'].user,
                               **validated_data)
