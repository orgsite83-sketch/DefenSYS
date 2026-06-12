from rest_framework import serializers
from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = [
            'id',
            'recipient',
            'sender',
            'sender_name',
            'title',
            'message',
            'is_read',
            'created_at',
        ]
        read_only_fields = ['id', 'recipient', 'sender', 'sender_name', 'created_at']

    def get_sender_name(self, obj):
        if obj.sender:
            full_name = f"{obj.sender.first_name} {obj.sender.last_name}".strip()
            return full_name or obj.sender.username
        return "System"
