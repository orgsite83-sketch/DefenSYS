from rest_framework import serializers

from student_teams.models import StudentTeam

from .services import STAGE_OPTIONS, definition_for


class DeliverableUploadSerializer(serializers.Serializer):
    team_id = serializers.IntegerField()
    stage_label = serializers.CharField(max_length=120)
    deliverable_id = serializers.CharField(max_length=20)
    file_name = serializers.CharField(max_length=255)
    file_size = serializers.CharField(max_length=40, required=False, allow_blank=True)

    def validate(self, attrs):
        attrs['deliverable_id'] = (attrs.get('deliverable_id') or '').strip()
        team = StudentTeam.objects.filter(pk=attrs['team_id']).first()
        if team is None:
            raise serializers.ValidationError({'team_id': 'Team not found.'})

        stage_label = attrs.get('stage_label')
        if team.is_capstone:
            from defense.stages.models import DefenseStage
            valid_stages = list(DefenseStage.objects.filter(is_active=True).values_list('label', flat=True))
            if stage_label not in valid_stages:
                raise serializers.ValidationError({'stage_label': f"'{stage_label}' is not a valid Capstone stage."})
        elif team.is_pit:
            from defense.scheduler.models import PitEventGradingConfig
            valid_events = list(PitEventGradingConfig.objects.filter(semester=team.semester).values_list('event_name', flat=True))
            if not any(e.lower() == stage_label.lower() for e in valid_events):
                raise serializers.ValidationError({'stage_label': f"'{stage_label}' is not a valid PIT event for this semester."})
        else:
            raise serializers.ValidationError({'team_id': 'Invalid team type.'})

        if definition_for(team, attrs['stage_label'], attrs['deliverable_id']) is None:
            raise serializers.ValidationError({'deliverable_id': 'Deliverable does not exist for this stage.'})
        attrs['file_name'] = attrs['file_name'].strip()
        if not attrs['file_name']:
            raise serializers.ValidationError({'file_name': 'File name is required.'})
        return attrs


class DeliverableActionSerializer(serializers.Serializer):
    team_id = serializers.IntegerField()
    stage_label = serializers.CharField(max_length=120)
    deliverable_id = serializers.CharField(max_length=20, required=False)

    def validate(self, attrs):
        deliverable_id = (attrs.get('deliverable_id') or '').strip()
        team = StudentTeam.objects.filter(pk=attrs['team_id']).first()
        if team is None:
            raise serializers.ValidationError({'team_id': 'Team not found.'})

        stage_label = attrs.get('stage_label')
        if team.is_capstone:
            from defense.stages.models import DefenseStage
            valid_stages = list(DefenseStage.objects.filter(is_active=True).values_list('label', flat=True))
            if stage_label not in valid_stages:
                raise serializers.ValidationError({'stage_label': f"'{stage_label}' is not a valid Capstone stage."})
        elif team.is_pit:
            from defense.scheduler.models import PitEventGradingConfig
            valid_events = list(PitEventGradingConfig.objects.filter(semester=team.semester).values_list('event_name', flat=True))
            if not any(e.lower() == stage_label.lower() for e in valid_events):
                raise serializers.ValidationError({'stage_label': f"'{stage_label}' is not a valid PIT event for this semester."})
        else:
            raise serializers.ValidationError({'team_id': 'Invalid team type.'})

        if not deliverable_id:
            return attrs

        if definition_for(team, attrs['stage_label'], deliverable_id) is None:
            raise serializers.ValidationError({'deliverable_id': 'Deliverable does not exist for this stage.'})
        return attrs
