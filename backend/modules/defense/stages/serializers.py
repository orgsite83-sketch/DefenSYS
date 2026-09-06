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
            'archive_note',
            'archive_file_template',
            'is_restricted',
        ]

    def validate_archive_file_template(self, value):
        if value:
            import re
            vars_found = re.findall(r'\{[a-zA-Z0-9_]+\}', value)
            if len(vars_found) > 3:
                raise serializers.ValidationError(
                    f'Archive naming template cannot exceed 3 dynamic variables (found {len(vars_found)}). Phone filenames have character limits.'
                )
        return value


def check_stage_locked(stage, semester=None):
    if not semester:
        from academic_period_management.models import Semester
        semester = Semester.objects.filter(is_active=True).first()
    if not semester:
        return False, None

    config = stage.grading_configs.filter(semester=semester).first()
    if config and config.is_officially_complete:
        return True, 'This stage is officially complete for the active semester.'

    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade

    if DefenseSchedule.objects.filter(defense_stage=stage, semester=semester).exists():
        return True, 'This stage has scheduled defenses for the active semester.'

    if TeamGrade.objects.filter(defense_stage=stage, semester=semester).exclude(status=TeamGrade.STATUS_PENDING).exists():
        return True, 'This stage has recorded evaluation grades.'

    return False, None


class DefenseStageSerializer(serializers.ModelSerializer):
    previous_stage_id = serializers.SerializerMethodField()
    previous_stage_label = serializers.SerializerMethodField()
    previous_stage_code = serializers.SerializerMethodField()
    deliverables = StageDeliverableSerializer(many=True, read_only=True)
    deliverables_count = serializers.SerializerMethodField()
    is_officially_complete = serializers.SerializerMethodField()
    is_locked = serializers.SerializerMethodField()
    lock_reason = serializers.SerializerMethodField()
    rubric_name = serializers.SerializerMethodField()
    rubric_info = serializers.SerializerMethodField()
    rubrics_count = serializers.SerializerMethodField()

    class Meta:
        model = DefenseStage
        fields = [
            'id',
            'label',
            'code',
            'display_order',
            'description',
            'is_active',
            'is_presentation_only',
            'previous_stage_id',
            'previous_stage_label',
            'previous_stage_code',
            'deliverables',
            'deliverables_count',
            'rubric_name',
            'rubric_info',
            'rubrics_count',
            'is_officially_complete',
            'is_locked',
            'lock_reason',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'code',
            'previous_stage_id',
            'previous_stage_label',
            'previous_stage_code',
            'deliverables',
            'deliverables_count',
            'rubric_name',
            'rubric_info',
            'rubrics_count',
            'is_officially_complete',
            'is_locked',
            'lock_reason',
        ]

    def _get_stage_grading_config(self, obj):
        semester = self.context.get('semester')
        if not semester:
            from academic_period_management.models import Semester
            semester = Semester.objects.filter(is_active=True).first()
        if not semester:
            return None
        return obj.grading_configs.filter(semester=semester).select_related(
            'panel_rubric', 'adviser_rubric', 'peer_rubric'
        ).first()

    def get_rubrics_count(self, obj):
        config = self._get_stage_grading_config(obj)
        if not config:
            return 0
        count = 0
        if config.panel_rubric_id:
            count += 1
        if config.adviser_rubric_id:
            count += 1
        if config.peer_rubric_id:
            count += 1
        return count

    def get_rubric_name(self, obj):
        config = self._get_stage_grading_config(obj)
        if not config:
            return None
        attached = []
        if config.panel_rubric:
            attached.append(f'Panel: {config.panel_rubric.name}')
        if config.adviser_rubric:
            attached.append(f'Adviser: {config.adviser_rubric.name}')
        if config.peer_rubric:
            attached.append(f'Peer: {config.peer_rubric.name}')
        
        if not attached:
            return None
        if len(attached) == 1:
            return attached[0]
        if len(attached) == 3:
            return 'All 3 Rubrics Attached'
        return f'{len(attached)}/3 Rubrics Attached'

    def get_rubric_info(self, obj):
        config = self._get_stage_grading_config(obj)
        if not config:
            return {
                'count': 0,
                'has_rubrics': False,
                'summary': 'None attached',
                'panel_rubric_name': None,
                'adviser_rubric_name': None,
                'peer_rubric_name': None,
            }

        panel_name = config.panel_rubric.name if config.panel_rubric else None
        adviser_name = config.adviser_rubric.name if config.adviser_rubric else None
        peer_name = config.peer_rubric.name if config.peer_rubric else None

        count = sum(1 for x in [panel_name, adviser_name, peer_name] if x is not None)

        if count == 0:
            summary = 'None attached'
        elif count == 3:
            summary = 'All 3 Rubrics Attached'
        elif count == 1 and panel_name:
            summary = f'Panel: {panel_name}'
        elif count == 1 and adviser_name:
            summary = f'Adviser: {adviser_name}'
        elif count == 1 and peer_name:
            summary = f'Peer: {peer_name}'
        else:
            summary = f'{count}/3 Rubrics Attached'

        return {
            'count': count,
            'has_rubrics': count > 0,
            'summary': summary,
            'panel_rubric_name': panel_name,
            'adviser_rubric_name': adviser_name,
            'peer_rubric_name': peer_name,
        }

    def get_deliverables_count(self, obj):
        return obj.deliverables.count()

    def get_is_officially_complete(self, obj):
        semester = self.context.get('semester')
        if not semester:
            from academic_period_management.models import Semester
            semester = Semester.objects.filter(is_active=True).first()
        if not semester:
            return False
        config = obj.grading_configs.filter(semester=semester).first()
        return config.is_officially_complete if config else False

    def get_is_locked(self, obj):
        locked, _ = check_stage_locked(obj, self.context.get('semester'))
        return locked

    def get_lock_reason(self, obj):
        _, reason = check_stage_locked(obj, self.context.get('semester'))
        return reason

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
        fields = ['label', 'code', 'display_order', 'description', 'is_active', 'is_presentation_only', 'deliverables']
        extra_kwargs = {
            'code': {'required': False, 'allow_blank': True},
            'display_order': {'required': False},
            'description': {'required': False, 'allow_blank': True},
            'is_active': {'required': False},
            'is_presentation_only': {'required': False},
        }

    def validate_label(self, value):
        queryset = DefenseStage.objects.filter(label__iexact=value.strip())
        if self.instance is not None:
            queryset = queryset.exclude(pk=self.instance.pk)
        if queryset.exists():
            raise serializers.ValidationError('A defense stage with this label already exists.')
        return value.strip()

    def validate_code(self, value):
        if value and value.strip():
            from .models import clean_custom_code
            code = clean_custom_code(value.strip())
            queryset = DefenseStage.objects.filter(code__iexact=code)
            if self.instance is not None:
                queryset = queryset.exclude(pk=self.instance.pk)
            if queryset.exists():
                raise serializers.ValidationError('A defense stage with this code already exists.')
            return code
        return ''

    def validate_deliverables(self, value):
        if value is not None:
            for item in value:
                label = item.get('label', '')
                if isinstance(label, str):
                    label = label.strip()
                if not label:
                    raise serializers.ValidationError('Deliverable label cannot be blank.')
        return value

    def create(self, validated_data):
        deliverables_data = validated_data.pop('deliverables', [])
        
        if not validated_data.get('display_order'):
            max_order = DefenseStage.objects.order_by('-display_order').values_list('display_order', flat=True).first()
            validated_data['display_order'] = (max_order or 0) + 1
        
        stage = super().create(validated_data)
        self._create_deliverables(stage, deliverables_data)
        return stage

    def update(self, instance, validated_data):
        semester = self.context.get('semester')
        locked, reason = check_stage_locked(instance, semester)
        if locked:
            raise serializers.ValidationError(
                {'non_field_errors': [reason or 'This defense stage is locked and cannot be edited.']}
            )

        deliverables_data = validated_data.pop('deliverables', None)
        stage = super().update(instance, validated_data)
        
        if deliverables_data is not None:
            # Delete existing deliverables and recreate them
            instance.deliverables.all().delete()
            self._create_deliverables(stage, deliverables_data)
        
        return stage

    def _create_deliverables(self, stage, deliverables_data):
        """Create deliverables for a stage"""
        import re
        for deliverable_data in deliverables_data:
            dtype = deliverable_data.get('deliverable_type', StageDeliverable.TYPE_PRE)
            required = deliverable_data.get('required')
            if required is None:
                required = dtype == StageDeliverable.TYPE_PRE
            tpl = (deliverable_data.get('archive_file_template') or '').strip()
            if dtype == StageDeliverable.TYPE_POST and not tpl:
                tpl = '{project}'
            if tpl:
                vars_found = re.findall(r'\{[a-zA-Z0-9_]+\}', tpl)
                if len(vars_found) > 3:
                    label = deliverable_data.get('label') or 'Deliverable'
                    raise serializers.ValidationError({
                        'deliverables': f'Template for "{label}" exceeds 3 variables ({len(vars_found)} found). Mobile phone file names have character limits.'
                    })
            StageDeliverable.objects.create(
                defense_stage=stage,
                deliverable_id=deliverable_data.get('deliverable_id', ''),
                label=deliverable_data.get('label', ''),
                deliverable_type=dtype,
                required=bool(required),
                display_order=deliverable_data.get('display_order', 1),
                archive_note=deliverable_data.get('archive_note', ''),
                archive_file_template=tpl,
                is_restricted=bool(deliverable_data.get('is_restricted', False)),
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
    is_locked = serializers.SerializerMethodField()
    lock_reason = serializers.SerializerMethodField()

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
            'is_locked',
            'lock_reason',
            'updated_at',
        ]
        read_only_fields = ['id', 'semester_id', 'is_locked', 'lock_reason', 'updated_at']

    def get_weights(self, obj):
        return {
            'panel': obj.panel_weight,
            'adviser': obj.adviser_weight,
            'peer': obj.peer_weight,
        }

    def get_is_locked(self, obj):
        locked, _ = check_stage_locked(obj.defense_stage, obj.semester)
        return locked

    def get_lock_reason(self, obj):
        _, reason = check_stage_locked(obj.defense_stage, obj.semester)
        return reason


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
        from django.db.models import Q

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

        # Check if rubric is already assigned to a different stage in the same semester
        other_config = StageGradingConfig.objects.filter(
            semester=config.semester
        ).exclude(
            defense_stage=config.defense_stage
        ).filter(
            Q(panel_rubric=rubric) | Q(adviser_rubric=rubric) | Q(peer_rubric=rubric)
        ).select_related('defense_stage').first()

        if other_config:
            raise serializers.ValidationError(
                {field_key: f"This rubric is already assigned to stage '{other_config.defense_stage.label}'."}
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

        # Check lock status if weights or rubrics are being changed
        changing_panel_w = 'panel_weight' in attrs and attrs['panel_weight'] != config.panel_weight
        changing_adviser_w = 'adviser_weight' in attrs and attrs['adviser_weight'] != config.adviser_weight
        changing_peer_w = 'peer_weight' in attrs and attrs['peer_weight'] != config.peer_weight
        changing_panel_r = 'panel_rubric_id' in attrs and attrs['panel_rubric_id'] != (config.panel_rubric_id)
        changing_adviser_r = 'adviser_rubric_id' in attrs and attrs['adviser_rubric_id'] != (config.adviser_rubric_id)
        changing_peer_r = 'peer_rubric_id' in attrs and attrs['peer_rubric_id'] != (config.peer_rubric_id)

        if changing_panel_w or changing_adviser_w or changing_peer_w or changing_panel_r or changing_adviser_r or changing_peer_r:
            locked, reason = check_stage_locked(config.defense_stage, config.semester)
            if locked:
                raise serializers.ValidationError(
                    {'rubric': reason or 'Stage configuration cannot be changed because defenses are already scheduled or officially completed.'}
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
        old_rubrics = [config.panel_rubric, config.adviser_rubric, config.peer_rubric]
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

        # Clear defense_stage linkage for old rubrics that were unassigned
        for old_r in old_rubrics:
            if old_r and old_r not in [config.panel_rubric, config.adviser_rubric, config.peer_rubric]:
                # Check if unassigned from all fields
                still_used = StageGradingConfig.objects.filter(
                    semester=config.semester
                ).filter(
                    Q(panel_rubric=old_r) | Q(adviser_rubric=old_r) | Q(peer_rubric=old_r)
                ).exists()
                if not still_used:
                    old_r.defense_stage = None
                    old_r.save(update_fields=['defense_stage'])

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
