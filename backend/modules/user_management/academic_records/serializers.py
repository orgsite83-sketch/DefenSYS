from django.contrib.auth import get_user_model
from rest_framework import serializers

from academic_period_management.models import Semester
from academic_period_management.serializers import SchoolYearSerializer, SemesterSerializer

from .models import StudentAcademicRecord


User = get_user_model()


def student_display_name(user):
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


class StudentOptionSerializer(serializers.ModelSerializer):
    name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'name', 'email']

    def get_name(self, obj):
        return student_display_name(obj)


class StudentAcademicRecordSerializer(serializers.ModelSerializer):
    student_id = serializers.IntegerField(source='student.id', read_only=True)
    student_username = serializers.CharField(source='student.username', read_only=True)
    student_name = serializers.CharField(read_only=True)
    student_email = serializers.EmailField(source='student.email', read_only=True)
    semester_id = serializers.IntegerField(source='semester.id', read_only=True)
    semester = serializers.CharField(source='semester.label', read_only=True)
    school_year_id = serializers.IntegerField(source='semester.school_year.id', read_only=True)
    school_year = serializers.CharField(source='semester.school_year.label', read_only=True)
    display_semester = serializers.CharField(source='semester.display_name', read_only=True)
    rolled_from_id = serializers.IntegerField(source='rolled_from.id', read_only=True, allow_null=True)
    rolled_from_label = serializers.SerializerMethodField()

    class Meta:
        model = StudentAcademicRecord
        fields = [
            'id',
            'student_id',
            'student_username',
            'student_name',
            'student_email',
            'semester_id',
            'semester',
            'school_year_id',
            'school_year',
            'display_semester',
            'year_level',
            'section',
            'action',
            'rolled_from_id',
            'rolled_from_label',
            'created_at',
        ]

    def get_rolled_from_label(self, obj):
        if not obj.rolled_from_id:
            return None
        return f'{obj.rolled_from.school_year.label} - {obj.rolled_from.semester.label}'


class StudentAcademicRecordWriteSerializer(serializers.Serializer):
    student_id = serializers.IntegerField(required=False)
    student_username = serializers.CharField(required=False, allow_blank=False)
    semester_id = serializers.IntegerField()
    year_level = serializers.ChoiceField(choices=[choice[0] for choice in StudentAcademicRecord.YEAR_LEVEL_CHOICES])
    section = serializers.CharField(required=False, allow_blank=True, max_length=80)

    def validate(self, attrs):
        student = self._student_from_attrs(attrs)
        if student.role != 'student':
            raise serializers.ValidationError({'student_id': 'Selected user is not a student.'})

        try:
            semester = Semester.objects.select_related('school_year').get(pk=attrs['semester_id'])
        except Semester.DoesNotExist as exc:
            raise serializers.ValidationError({'semester_id': 'Semester does not exist.'}) from exc

        record_id = self.context.get('record_id')
        existing = StudentAcademicRecord.objects.filter(student=student, semester=semester)
        if record_id:
            existing = existing.exclude(pk=record_id)
        if existing.exists():
            raise serializers.ValidationError({'semester_id': 'This student already has a record for this semester.'})

        attrs['student'] = student
        attrs['semester'] = semester
        return attrs

    def create(self, validated_data):
        return StudentAcademicRecord.objects.create(
            student=validated_data['student'],
            semester=validated_data['semester'],
            year_level=validated_data['year_level'],
            section=' '.join((validated_data.get('section') or '').strip().split()),
        )

    def update(self, instance, validated_data):
        instance.student = validated_data['student']
        instance.semester = validated_data['semester']
        instance.year_level = validated_data['year_level']
        instance.section = ' '.join((validated_data.get('section') or '').strip().split())
        instance.save()
        return instance

    def _student_from_attrs(self, attrs):
        if attrs.get('student_id') is not None:
            try:
                return User.objects.get(pk=attrs['student_id'])
            except User.DoesNotExist as exc:
                raise serializers.ValidationError({'student_id': 'Student does not exist.'}) from exc

        username = attrs.get('student_username')
        if username:
            try:
                return User.objects.get(username=username)
            except User.DoesNotExist as exc:
                raise serializers.ValidationError({'student_username': 'Student does not exist.'}) from exc

        raise serializers.ValidationError({'student_id': 'This field is required.'})


class RolloverActionSerializer(serializers.Serializer):
    record_id = serializers.IntegerField()
    action = serializers.ChoiceField(choices=['promote', 'retain', 'drop'])


class AcademicRecordsOptionsSerializer(serializers.Serializer):
    school_years = SchoolYearSerializer(many=True)
    active_semester = SemesterSerializer(allow_null=True)
    students = StudentOptionSerializer(many=True)
