from rest_framework import serializers

from .models import DefenseStage, StageDeliverable, StageGradingConfig


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
            'vault_file_template',
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
            dtype = deliverable_data.get('deliverable_type', StageDeliverable.TYPE_PRE)
            required = deliverable_data.get('required')
            if required is None:
                required = dtype == StageDeliverable.TYPE_PRE
            StageDeliverable.objects.create(
                defense_stage=stage,
                deliverable_id=deliverable_data.get('deliverable_id', ''),
                label=deliverable_data.get('label', ''),
                deliverable_type=dtype,
                required=bool(required),
                display_order=deliverable_data.get('display_order', 1),
                vault_note=deliverable_data.get('vault_note', ''),
                vault_file_template=deliverable_data.get('vault_file_template', ''),
            )


class StageGradingConfigSerializer(serializers.ModelSerializer):
    weights = serializers.SerializerMethodField()
    semester_id = serializers.IntegerField(source='semester.id', read_only=True)
    panel_rubric_id = serializers.IntegerField(source='panel_rubric.id', read_only=True, allow_null=True)
    panel_rubric_name = serializers.CharField(source='panel_rubric.name', read_only=True, allow_null=True)
    adviser_rubric_id = serializers.IntegerField(source='adviser_rubric.id', read_only=True, allow_null=True)
    adviser_rubric_name = serializers.CharField(source='adviser_rubric.name', read_only=True, allow_null=True)
    peer_rubric_id = serializers.IntegerField(source='peer_rubric.id', read_only=True, allow_null=True)
    peer_rubric_name = serializers.CharField(source='peer_rubric.name', read_only=True, allow_null=True)

    class Meta:
        model = StageGradingConfig
        fields = [
            'id',
            'semester_id',
            'panel_weight',
            'adviser_weight',
            'peer_weight',
            'panel_rubric_id',
            'panel_rubric_name',
            'adviser_rubric_id',
            'adviser_rubric_name',
            'peer_rubric_id',
            'peer_rubric_name',
            'weights',
            'updated_at',
        ]
        read_only_fields = ['id', 'semester_id', 'updated_at']

    def get_weights(self, obj):
        return {
            'panel': obj.panel_weight,
            'adviser': obj.adviser_weight,
            'peer': obj.peer_weight,
        }


class StageGradingConfigWriteSerializer(serializers.Serializer):
    panel_weight = serializers.IntegerField(min_value=0, max_value=100, required=False)
    adviser_weight = serializers.IntegerField(min_value=0, max_value=100, required=False)
    peer_weight = serializers.IntegerField(min_value=0, max_value=100, required=False)
    panel_rubric_id = serializers.IntegerField(required=False, allow_null=True)
    adviser_rubric_id = serializers.IntegerField(required=False, allow_null=True)
    peer_rubric_id = serializers.IntegerField(required=False, allow_null=True)

    def _resolve_rubric(self, rubric_id, evaluation_type):
        if rubric_id is None:
            return None
        from grading.rubrics.models import Rubric

        eval_map = {
            'panel': Rubric.EVAL_PANEL,
            'adviser': Rubric.EVAL_ADVISER,
            'peer': Rubric.EVAL_PEER,
        }
        expected_eval = eval_map[evaluation_type]
        field_key = f'{evaluation_type}_rubric_id'
        config = self.context['config']
        try:
            rubric = Rubric.objects.get(pk=rubric_id)
        except Rubric.DoesNotExist as exc:
            raise serializers.ValidationError({field_key: 'Rubric does not exist.'}) from exc
        if rubric.status != Rubric.STATUS_PUBLISHED:
            raise serializers.ValidationError({field_key: 'Only published rubrics can be assigned.'})
        if rubric.scope != Rubric.SCOPE_CAPSTONE:
            raise serializers.ValidationError({field_key: 'Rubric scope must be Capstone.'})
        if rubric.evaluation_type != expected_eval:
            raise serializers.ValidationError(
                {field_key: f'Rubric must use {evaluation_type} evaluation type.'}
            )
        if rubric.defense_stage_id != config.defense_stage_id:
            rubric.defense_stage = config.defense_stage
            rubric.save(update_fields=['defense_stage'])
        return rubric

    def validate(self, attrs):
        config = self.context['config']
        panel_weight = attrs.get('panel_weight', config.panel_weight)
        adviser_weight = attrs.get('adviser_weight', config.adviser_weight)
        peer_weight = attrs.get('peer_weight', config.peer_weight)
        total = panel_weight + adviser_weight + peer_weight
        if total != 100:
            raise serializers.ValidationError(
                {'weights': 'Panel, adviser, and peer weights must total 100%.'},
            )
        attrs['panel_weight'] = panel_weight
        attrs['adviser_weight'] = adviser_weight
        attrs['peer_weight'] = peer_weight
        if 'panel_rubric_id' in attrs:
            attrs['panel_rubric'] = self._resolve_rubric(attrs.pop('panel_rubric_id'), 'panel')
        if 'adviser_rubric_id' in attrs:
            attrs['adviser_rubric'] = self._resolve_rubric(attrs.pop('adviser_rubric_id'), 'adviser')
        if 'peer_rubric_id' in attrs:
            attrs['peer_rubric'] = self._resolve_rubric(attrs.pop('peer_rubric_id'), 'peer')
        return attrs

    def save(self):
        config = self.context['config']
        update_fields = []
        for field in ['panel_weight', 'adviser_weight', 'peer_weight']:
            if field in self.validated_data:
                setattr(config, field, self.validated_data[field])
                update_fields.append(field)
        for field in ['panel_rubric', 'adviser_rubric', 'peer_rubric']:
            if field in self.validated_data:
                setattr(config, field, self.validated_data[field])
                update_fields.append(field)
        if update_fields:
            config.save(update_fields=update_fields + ['updated_at'])
        self._sync_rubrics(config)
        return config

    def _sync_rubrics(self, config):
        from grading.rubrics.models import Rubric

        Rubric.objects.filter(
            scope=Rubric.SCOPE_CAPSTONE,
            defense_stage=config.defense_stage,
            semester=config.semester,
        ).update(
            panel_weight=config.panel_weight,
            adviser_weight=config.adviser_weight,
            peer_weight=config.peer_weight,
        )
