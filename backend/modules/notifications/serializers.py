from rest_framework import serializers
from .models import Notification
from .actions import resolve_actions


class NotificationSerializer(serializers.ModelSerializer):
    def to_representation(self, instance):
        data = super().to_representation(instance)
        if instance.workspace == 'student' and instance.title == 'Defense outcome recorded':
            from grading.grades.dissemination import latest_release
            released = latest_release((instance.action_payload or {}).get('schedule_id'), instance.recipient)
            data.update(title='Defense outcome', message='Your defense outcome and panel feedback are now available.'
                if released else 'Awaiting official release.')
        return data

    sender_name = serializers.SerializerMethodField()
    action = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = [
            'id',
            'recipient',
            'sender',
            'sender_name',
            'title',
            'message',
            'category',
            'priority',
            'action_route',
            'action_payload',
            'action',
            'workspace',
            'is_read',
            'created_at',
        ]
        read_only_fields = ['id', 'recipient', 'sender', 'sender_name', 'created_at']

    def get_sender_name(self, obj):
        if obj.sender:
            full_name = f"{obj.sender.first_name} {obj.sender.last_name}".strip()
            return full_name or obj.sender.username
        return "System"

    def get_action(self, obj):
        actions = self.context.get('actions')
        if actions is None:
            actions = resolve_actions([obj], self.context.get('actor') or obj.recipient)
        return actions.get(obj.pk)
