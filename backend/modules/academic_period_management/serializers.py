from rest_framework import serializers

from .models import SchoolYear, Semester, validate_school_year_label


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
            'school_year_id',
            'school_year',
            'display_name',
            'capstone_peer_evaluation_enabled',
            'capstone_adviser_grading_enabled',
        ]


class SchoolYearSerializer(serializers.ModelSerializer):
    school_year = serializers.CharField(source='label', read_only=True)
    semesters = SemesterSerializer(many=True, read_only=True)

    class Meta:
        model = SchoolYear
        fields = ['id', 'label', 'school_year', 'semesters', 'created_at']


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


class SemesterCreateSerializer(serializers.Serializer):
    label = serializers.ChoiceField(choices=[choice[0] for choice in Semester.TERM_CHOICES])

    def validate(self, attrs):
        school_year = self.context['school_year']
        label = attrs['label']
        if Semester.objects.filter(school_year=school_year, label=label).exists():
            raise serializers.ValidationError({'label': 'This semester already exists for the selected school year.'})
        return attrs

    def create(self, validated_data):
        return Semester.objects.create(
            school_year=self.context['school_year'],
            label=validated_data['label'],
        )
