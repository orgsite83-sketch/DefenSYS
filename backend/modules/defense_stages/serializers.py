from rest_framework import serializers

from .models import DefenseStage, StageDeliverable


class StageDeliverableSerializer(serializers.ModelSerializer):
    class Meta:
        model = StageDeliverable
        fields = [
            'id',
            'deliverable_id',
            'label',
            'deliverable_type',
            'required',
            'display_order',
            'vault_note',
        ]


class DefenseStageSerializer(serializers.ModelSerializer):
    previous_stage_id = serializers.SerializerMethodField()
    previous_stage_label = serializers.SerializerMethodField()
    previous_stage_code = serializers.SerializerMethodField()
    deliverables = StageDeliverableSerializer(many=True, read_only=True)
    deliverables_count = serializers.SerializerMethodField()

    class Meta:
        model = DefenseStage
        fields = [
            'id',
            'label',
            'code',
            'display_order',
            'description',
            'is_active',
            'previous_stage_id',
            'previous_stage_label',
            'previous_stage_code',
            'deliverables',
            'deliverables_count',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['code', 'previous_stage_id', 'previous_stage_label', 'previous_stage_code', 'deliverables', 'deliverables_count']

    def get_deliverables_count(self, obj):
        return obj.deliverables.count()

    def get_previous_stage_id(self, obj):
        previous = self._previous_stage(obj)
        return previous.id if previous else None

    def get_previous_stage_label(self, obj):
        previous = self._previous_stage(obj)
        return previous.label if previous else None

    def get_previous_stage_code(self, obj):
        previous = self._previous_stage(obj)
        return previous.code if previous else None

    def _previous_stage(self, obj):
        stages = self.context.get('ordered_stages')
        if not stages:
            return None

        for index, stage in enumerate(stages):
            if stage.id == obj.id:
                return stages[index - 1] if index > 0 else None
        return None


class DefenseStageWriteSerializer(serializers.ModelSerializer):
    deliverables = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        write_only=True,
    )

    class Meta:
        model = DefenseStage
        fields = ['label', 'display_order', 'description', 'is_active', 'deliverables']
        extra_kwargs = {
            'display_order': {'required': False},
            'description': {'required': False, 'allow_blank': True},
            'is_active': {'required': False},
        }

    def validate_label(self, value):
        queryset = DefenseStage.objects.filter(label__iexact=value.strip())
        if self.instance is not None:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError('A defense stage with this label already exists.')
        return value.strip()

    def create(self, validated_data):
        deliverables_data = validated_data.pop('deliverables', [])
        
        if not validated_data.get('display_order'):
            max_order = DefenseStage.objects.order_by('-display_order').values_list('display_order', flat=True).first()
            validated_data['display_order'] = (max_order or 0) + 1
        
        stage = super().create(validated_data)
        self._create_deliverables(stage, deliverables_data)
        return stage

    def update(self, instance, validated_data):
        deliverables_data = validated_data.pop('deliverables', None)
        stage = super().update(instance, validated_data)
        
        if deliverables_data is not None:
            # Delete existing deliverables and recreate them
            instance.deliverables.all().delete()
            self._create_deliverables(stage, deliverables_data)
        
        return stage

    def _create_deliverables(self, stage, deliverables_data):
        """Create deliverables for a stage"""
        for deliverable_data in deliverables_data:
            StageDeliverable.objects.create(
                defense_stage=stage,
                deliverable_id=deliverable_data.get('deliverable_id', ''),
                label=deliverable_data.get('label', ''),
                deliverable_type=deliverable_data.get('deliverable_type', 'pre'),
                required=deliverable_data.get('required', False),
                display_order=deliverable_data.get('display_order', 1),
                vault_note=deliverable_data.get('vault_note', ''),
            )
