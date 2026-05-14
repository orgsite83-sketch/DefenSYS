from rest_framework import serializers

from .services import STAGE_OPTIONS, definition_for


class DeliverableUploadSerializer(serializers.Serializer):
    team_id = serializers.IntegerField()
    stage_label = serializers.ChoiceField(choices=STAGE_OPTIONS)
    deliverable_id = serializers.CharField(max_length=20)
    file_name = serializers.CharField(max_length=255)
    file_size = serializers.CharField(max_length=40, required=False, allow_blank=True)

    def validate(self, attrs):
        if definition_for(attrs['stage_label'], attrs['deliverable_id']) is None:
            raise serializers.ValidationError({'deliverable_id': 'Deliverable does not exist for this stage.'})
        attrs['file_name'] = attrs['file_name'].strip()
        if not attrs['file_name']:
            raise serializers.ValidationError({'file_name': 'File name is required.'})
        return attrs


class DeliverableActionSerializer(serializers.Serializer):
    team_id = serializers.IntegerField()
    stage_label = serializers.ChoiceField(choices=STAGE_OPTIONS)
    deliverable_id = serializers.CharField(max_length=20, required=False)

    def validate(self, attrs):
        deliverable_id = attrs.get('deliverable_id')
        if deliverable_id and definition_for(attrs['stage_label'], deliverable_id) is None:
            raise serializers.ValidationError({'deliverable_id': 'Deliverable does not exist for this stage.'})
        return attrs


class DemoFillSerializer(serializers.Serializer):
    stage_label = serializers.ChoiceField(choices=STAGE_OPTIONS, default=STAGE_OPTIONS[0], required=False)
