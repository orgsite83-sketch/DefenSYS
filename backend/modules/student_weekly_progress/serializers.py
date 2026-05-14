from rest_framework import serializers
from .models import WeeklyProgressReport


class WeeklyProgressReportSerializer(serializers.ModelSerializer):
    student_name = serializers.SerializerMethodField()
    team_name = serializers.SerializerMethodField()
    file_url = serializers.SerializerMethodField()
    
    class Meta:
        model = WeeklyProgressReport
        fields = [
            'id',
            'student',
            'student_name',
            'team',
            'team_name',
            'week_number',
            'report_date',
            'accomplishments',
            'contributions',
            'issues',
            'plans',
            'report_file',
            'file_size',
            'file_url',
            'submitted_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'student', 'submitted_at', 'updated_at']
    
    def get_student_name(self, obj):
        full_name = f'{obj.student.first_name} {obj.student.last_name}'.strip()
        return full_name or obj.student.username
    
    def get_team_name(self, obj):
        return obj.team.name if obj.team else None
    
    def get_file_url(self, obj):
        if obj.report_file:
            return f'/api/weekly-progress/{obj.id}/file/'
        return None
