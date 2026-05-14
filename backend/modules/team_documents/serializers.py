from rest_framework import serializers
from .models import TeamDocument


class TeamDocumentSerializer(serializers.ModelSerializer):
    team_name = serializers.CharField(source='team.name', read_only=True)
    uploaded_by_name = serializers.SerializerMethodField()
    file_size_mb = serializers.ReadOnlyField()
    file_url = serializers.ReadOnlyField()  # Add file_url
    
    class Meta:
        model = TeamDocument
        fields = [
            'id',
            'team',
            'team_name',
            'uploaded_by',
            'uploaded_by_name',
            'document_type',
            'file_name',
            'file_size',
            'file_size_mb',
            'file_url',  # Include file_url
            'mime_type',
            'description',
            'uploaded_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'uploaded_by', 'uploaded_at', 'updated_at']
    
    def get_uploaded_by_name(self, obj):
        if obj.uploaded_by:
            return f"{obj.uploaded_by.first_name} {obj.uploaded_by.last_name}".strip() or obj.uploaded_by.username
        return "Unknown"


class TeamDocumentUploadSerializer(serializers.Serializer):
    team_id = serializers.IntegerField()
    document_type = serializers.ChoiceField(choices=TeamDocument.DOCUMENT_TYPES)
    description = serializers.CharField(required=False, allow_blank=True)
    file = serializers.FileField()
    
    def validate_file(self, value):
        # Limit file size to 10MB
        if value.size > 10 * 1024 * 1024:
            raise serializers.ValidationError("File size cannot exceed 10MB")
        return value
