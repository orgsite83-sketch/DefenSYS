from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView as APIView

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from user_management.permissions import IsSystemAdmin
from .grading_config import (
    get_or_create_stage_grading_config,
    grading_config_payload,
    resolve_semester,
)
from .models import DefenseStage, StageDeliverable
from .serializers import (
    DefenseStageSerializer,
    DefenseStageWriteSerializer,
    StageDeliverableSerializer,
    StageGradingConfigSerializer,
    StageGradingConfigWriteSerializer,
)


def record_setup_event(stage, request, action, *, semester=None, old_values=None, values=None):
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    semester = semester or resolve_semester()
    log_high_impact_action(category=SystemAuditLog.CATEGORY_RUBRICS,
        action=action, target=stage, request=request, strict=True, old_values=old_values,
        new_values={'scope': 'capstone', 'defense_stage_id': stage.pk,
            'stage_label': stage.label, 'semester_id': semester.pk if semester else None,
            'actor_snapshot': {'id': request.user.pk,
                'name': request.user.get_full_name() or request.user.username}, **(values or {})})


def normalize_stage_orders():
    """Ensure all defense stages have contiguous, unique display_order values (1, 2, 3...)."""
    stages = list(DefenseStage.objects.all().order_by('display_order', 'id'))
    with transaction.atomic():
        for index, stage in enumerate(stages, start=1):
            if stage.display_order != index:
                DefenseStage.objects.filter(pk=stage.pk).update(display_order=index)


def ordered_stages(include_inactive=True):
    queryset = DefenseStage.objects.all()
    if not include_inactive:
        queryset = queryset.filter(is_active=True)
    return list(queryset.prefetch_related('deliverables').order_by('display_order', 'id'))


def counts_payload():
    stages = DefenseStage.objects.all()
    return {
        'total': stages.count(),
        'active': stages.filter(is_active=True).count(),
        'inactive': stages.filter(is_active=False).count(),
    }


def stage_list_payload(semester=None):
    if not semester:
        from academic_period_management.models import Semester
        semester = Semester.objects.filter(is_active=True).first()
    stages = ordered_stages()
    active = [stage for stage in stages if stage.is_active]
    return {
        'stages': DefenseStageSerializer(
            stages,
            many=True,
            context={'ordered_stages': stages, 'semester': semester},
        ).data,
        'active_stages': DefenseStageSerializer(
            active,
            many=True,
            context={'ordered_stages': active, 'semester': semester},
        ).data,
        'counts': counts_payload(),
    }


class DefenseStageListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [IsSystemAdmin()]

    def get(self, request):
        semester = resolve_semester(request.query_params.get('semester_id'))
        payload = stage_list_payload(semester)
        from student_teams.capstone_history import history_payload, history_teams_for
        history = history_payload(history_teams_for(request.user), request.query_params,
            user=request.user, include_details=False)
        payload['capstone_history'] = history['capstone_history']
        grouped = {}
        for row in history['teams']:
            term_id = row['semester_id']
            group = grouped.setdefault(term_id, {'semester_id': term_id,
                'phase': row['phase'], 'phase_label': row['phase_label'],
                'display_semester': row['display_semester'], 'stage_ids': set(),
                'read_only': request.query_params.get('scope') == 'history' or not semester or term_id != semester.pk})
            group['stage_ids'].update(r['id'] for r in row['stage_requirements'])
        for group in grouped.values():
            term = Semester.objects.select_related('school_year').get(pk=group['semester_id'])
            ids = group.pop('stage_ids')
            selected = request.query_params.get('stage_key', '')
            if selected:
                ids = {i for i in ids if f'{term.pk}:{i}' == selected}
            stages = list(DefenseStage.objects.filter(pk__in=ids).order_by('display_order', 'pk'))
            group['stages'] = [{**s, 'semester_id': term.pk,
                'history_read_only': group['read_only']} for s in DefenseStageSerializer(stages, many=True,
                    context={'semester': term, 'ordered_stages': ordered_stages()}).data]
        payload['phase_groups'] = list(grouped.values())
        if request.query_params.get('scope') == 'history' and not grouped:
            payload.update(stages=[], active_stages=[], counts={'total': 0, 'active': 0, 'inactive': 0})
        return Response(payload)

    def post(self, request):
        from .serializers import check_stage_structure_locked as check_stage_locked

        requested_order = request.data.get('display_order')
        if requested_order is not None:
            try:
                requested_order = int(requested_order)
                all_existing = list(DefenseStage.objects.all().order_by('display_order', 'id'))
                for s in all_existing:
                    locked, _ = check_stage_locked(s)
                    if locked and s.display_order >= requested_order:
                        return Response(
                            {'display_order': 'New defense stages cannot be placed before locked defense stages.'},
                            status=status.HTTP_400_BAD_REQUEST,
                        )
            except (ValueError, TypeError):
                pass

        serializer = DefenseStageWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        with transaction.atomic():
            stage = serializer.save()
            # If a specific display_order was requested, place it and re-normalize
            requested_order = serializer.validated_data.get('display_order')
            all_stages = list(DefenseStage.objects.exclude(pk=stage.pk).order_by('display_order', 'id'))
            if requested_order is not None:
                insert_idx = max(0, min(requested_order - 1, len(all_stages)))
                all_stages.insert(insert_idx, stage)
            else:
                all_stages.append(stage)
            
            for index, s in enumerate(all_stages, start=1):
                DefenseStage.objects.filter(pk=s.pk).update(display_order=index)
            stage.refresh_from_db()

            record_setup_event(stage, request, 'capstone.stage_created',
                values={'display_order': stage.display_order})

        return Response(
            {
                'stage': DefenseStageSerializer(
                    stage,
                    context={'ordered_stages': ordered_stages()},
                ).data,
                **stage_list_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


def _stage_detail_payload(stage, request):
    semester = resolve_semester(request.query_params.get('semester_id'))
    config = stage.grading_configs.filter(semester=semester).first() if semester else None
    payload = {
        'stage': DefenseStageSerializer(
            stage,
            context={'ordered_stages': ordered_stages(), 'semester': semester},
        ).data,
    }
    if semester:
        payload['active_semester'] = SemesterSerializer(semester).data
        payload['grading_config'] = (
            StageGradingConfigSerializer(config).data if config else grading_config_payload(None)
        )
    return payload


class DefenseStageDetailView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [IsSystemAdmin()]

    def get_object(self, stage_id):
        return get_object_or_404(DefenseStage, pk=stage_id)

    def get(self, request, stage_id):
        stage = self.get_object(stage_id)
        return Response(_stage_detail_payload(stage, request))

    def patch(self, request, stage_id):
        from .serializers import check_stage_structure_locked as check_stage_locked

        stage = self.get_object(stage_id)
        locked, reason = check_stage_locked(stage)

        requested_order = request.data.get('display_order')
        if requested_order is not None:
            try:
                requested_order = int(requested_order)
                if locked and requested_order != stage.display_order:
                    return Response(
                        {'display_order': reason or 'Locked defense stages cannot change sequence position.'},
                        status=status.HTTP_409_CONFLICT,
                    )
                if not locked and requested_order != stage.display_order:
                    other_stages = list(DefenseStage.objects.exclude(pk=stage.pk).order_by('display_order', 'id'))
                    insert_idx = max(0, min(requested_order - 1, len(other_stages)))
                    for idx, s in enumerate(other_stages):
                        s_locked, _ = check_stage_locked(s)
                        if s_locked and idx >= insert_idx:
                            return Response(
                                {'display_order': 'Cannot move a defense stage before a locked defense stage.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
            except (ValueError, TypeError):
                pass

        serializer = DefenseStageWriteSerializer(stage, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            old_order = stage.display_order
            stage = serializer.save()
            new_order = serializer.validated_data.get('display_order')

            if new_order is not None and new_order != old_order:
                other_stages = list(DefenseStage.objects.exclude(pk=stage.pk).order_by('display_order', 'id'))
                insert_idx = max(0, min(new_order - 1, len(other_stages)))
                other_stages.insert(insert_idx, stage)
                for index, s in enumerate(other_stages, start=1):
                    DefenseStage.objects.filter(pk=s.pk).update(display_order=index)
                stage.refresh_from_db()

                # If admin requested to reset endorsements for this moved stage
                if request.data.get('endorsed_teams_action') == 'reset':
                    from student_teams.models import TeamStageProgress, StudentTeam
                    from student_teams.services import mark_stage_locked
                    from academic_period_management.models import Semester

                    semester = Semester.objects.filter(is_active=True).first()
                    qs = TeamStageProgress.objects.filter(defense_stage=stage, status=TeamStageProgress.STATUS_READY)
                    if semester:
                        qs = qs.filter(semester=semester)
                    for p in qs:
                        mark_stage_locked(p.team, stage, user=request.user)
                    if semester:
                        StudentTeam.objects.filter(semester=semester, ready_for_stage=stage.label).update(ready_for_stage=None)
            else:
                normalize_stage_orders()
                stage.refresh_from_db()

        return Response({
            'stage': DefenseStageSerializer(
                stage,
                context={'ordered_stages': ordered_stages()},
            ).data,
            **stage_list_payload(),
        })

    def delete(self, request, stage_id):
        from django.db.models import ProtectedError
        from .serializers import check_stage_structure_locked as check_stage_locked
        from defense.configuration_locks import context_deletion_lock

        stage = self.get_object(stage_id)
        locked, reason = check_stage_locked(stage)
        if not locked:
            locked, reason = context_deletion_lock(stage)
        if locked:
            return Response(
                {
                    'warning': reason or 'This stage is locked and cannot be deleted.',
                },
                status=status.HTTP_409_CONFLICT,
            )
        try:
            with transaction.atomic():
                stage.delete()
                normalize_stage_orders()
        except ProtectedError:
            return Response(
                {
                    'warning': (
                        'This stage cannot be deleted because it has existing '
                        'schedules, grades, or team progress records linked to it.'
                    ),
                },
                status=status.HTTP_409_CONFLICT,
            )
        return Response(stage_list_payload(), status=status.HTTP_200_OK)


class DefenseStageReorderView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request):
        from .serializers import check_stage_structure_locked as check_stage_locked

        stage_ids = request.data.get('stage_ids')
        if not isinstance(stage_ids, list) or len(stage_ids) == 0:
            return Response(
                {'stage_ids': 'A non-empty list of stage IDs is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing_stages = {s.id: s for s in DefenseStage.objects.all()}
        # Check all IDs provided exist
        for sid in stage_ids:
            if sid not in existing_stages:
                return Response(
                    {'stage_ids': f'Stage with ID {sid} does not exist.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # Enforce that locked stages cannot be reordered or moved
        all_ordered = list(DefenseStage.objects.all().order_by('display_order', 'id'))
        completed_stages = [s for s in all_ordered if check_stage_locked(s)[0]]
        if completed_stages:
            for idx, c_stage in enumerate(completed_stages):
                if idx >= len(stage_ids) or stage_ids[idx] != c_stage.id:
                    return Response(
                        {
                            'stage_ids': (
                                f'Stage "{c_stage.label}" has a configuration lock and cannot be reordered '
                                'or preceded by draft/active stages.'
                            )
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )

        with transaction.atomic():
            # Update provided stages in given order
            assigned_order = 1
            for sid in stage_ids:
                DefenseStage.objects.filter(pk=sid).update(display_order=assigned_order)
                assigned_order += 1

            # If any stages were not included in stage_ids, put them at the end
            for sid in existing_stages:
                if sid not in stage_ids:
                    DefenseStage.objects.filter(pk=sid).update(display_order=assigned_order)
                    assigned_order += 1

            reset_stage_id = request.data.get('reset_stage_id') or (request.data.get('stage_id') if request.data.get('endorsed_teams_action') == 'reset' else None)
            if reset_stage_id:
                try:
                    r_stage = existing_stages.get(int(reset_stage_id))
                    if r_stage:
                        from student_teams.models import TeamStageProgress, StudentTeam
                        from student_teams.services import mark_stage_locked
                        from academic_period_management.models import Semester

                        semester = Semester.objects.filter(is_active=True).first()
                        qs = TeamStageProgress.objects.filter(defense_stage=r_stage, status=TeamStageProgress.STATUS_READY)
                        if semester:
                            qs = qs.filter(semester=semester)
                        for p in qs:
                            mark_stage_locked(p.team, r_stage, user=request.user)
                        if semester:
                            StudentTeam.objects.filter(semester=semester, ready_for_stage=r_stage.label).update(ready_for_stage=None)
                except (ValueError, TypeError):
                    pass

        return Response(stage_list_payload(), status=status.HTTP_200_OK)


class StageDeliverableListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request, stage_id):
        from .serializers import check_stage_locked

        stage = get_object_or_404(DefenseStage, pk=stage_id)
        locked, reason = check_stage_locked(stage)
        if locked:
            return Response(
                {'detail': reason or 'Deliverables cannot be added because this stage is locked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = StageDeliverableSerializer(data=request.data, context={'stage': stage})
        serializer.is_valid(raise_exception=True)
        deliverable = serializer.save(defense_stage=stage)
        return Response(
            StageDeliverableSerializer(deliverable).data,
            status=status.HTTP_201_CREATED,
        )


class StageDeliverableDetailView(APIView):
    permission_classes = [IsSystemAdmin]

    def patch(self, request, stage_id, deliverable_id):
        from .serializers import check_stage_locked

        deliverable = get_object_or_404(
            StageDeliverable,
            defense_stage_id=stage_id,
            id=deliverable_id,
        )
        locked, reason = check_stage_locked(deliverable.defense_stage)
        if locked:
            return Response(
                {'detail': reason or 'Deliverables cannot be updated because this stage is locked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = StageDeliverableSerializer(
            deliverable,
            data=request.data,
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        # Use the same reconciliation as the stage editor so linked shared
        # requirements and their open checklist snapshots stay synchronized.
        stage = deliverable.defense_stage
        rows = list(StageDeliverableSerializer(stage.deliverables.all(), many=True).data)
        for row in rows:
            if row['id'] == deliverable.pk:
                row.update(serializer.validated_data)
        writer = DefenseStageWriteSerializer(stage, data={'deliverables': rows}, partial=True)
        writer.is_valid(raise_exception=True)
        writer.save()
        deliverable.refresh_from_db()
        return Response(StageDeliverableSerializer(deliverable).data)

    def delete(self, request, stage_id, deliverable_id):
        from .serializers import check_stage_locked
        from defense.configuration_locks import DATA_REASON, requirement_has_data

        deliverable = get_object_or_404(
            StageDeliverable,
            defense_stage_id=stage_id,
            id=deliverable_id,
        )
        locked, reason = check_stage_locked(deliverable.defense_stage)
        if locked:
            return Response(
                {'detail': reason or 'Deliverables cannot be deleted because this stage is locked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if requirement_has_data(deliverable.defense_stage, deliverable.deliverable_id,
                                policy=deliverable.file_policy):
            return Response({'detail': DATA_REASON}, status=status.HTTP_409_CONFLICT)
        from defense.document_policy import is_approved_concept
        if deliverable.defense_stage.concept_config.get('enabled') and (
                (deliverable.file_policy or {}).get('mode') == 'concepts'
                or is_approved_concept({'file_policy': deliverable.file_policy})):
            return Response({'detail': 'Disable concept selection before removing its required papers.'}, status=status.HTTP_400_BAD_REQUEST)
        stage = deliverable.defense_stage
        rows = list(StageDeliverableSerializer(stage.deliverables.exclude(pk=deliverable.pk), many=True).data)
        from defense.shared_deliverables import shared_definitions
        shared = [row for row in shared_definitions(stage)
                  if row.get('team_deliverable_id') != deliverable.deliverable_id]
        writer = DefenseStageWriteSerializer(stage, data={
            'deliverables': rows, 'shared_deliverables': shared,
        }, partial=True)
        writer.is_valid(raise_exception=True)
        writer.save()
        return Response(status=status.HTTP_204_NO_CONTENT)


class StageGradingConfigView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, stage_id):
        stage = get_object_or_404(DefenseStage, pk=stage_id)
        semester = resolve_semester(request.query_params.get('semester_id'))
        if semester is None:
            return Response(
                {'semester_id': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        config = stage.grading_configs.filter(semester=semester).first()
        return Response({
            'grading_config': StageGradingConfigSerializer(config).data if config else grading_config_payload(None),
            'active_semester': SemesterSerializer(semester).data,
        })

    @transaction.atomic
    def patch(self, request, stage_id):
        stage = get_object_or_404(DefenseStage, pk=stage_id)
        semester = resolve_semester(request.query_params.get('semester_id'))
        if semester is None:
            return Response(
                {'semester_id': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        config = get_or_create_stage_grading_config(stage, semester)
        before = dict(StageGradingConfigSerializer(config).data)
        serializer = StageGradingConfigWriteSerializer(
            data=request.data,
            context={'config': config},
        )
        serializer.is_valid(raise_exception=True)
        config = serializer.save()
        after = dict(StageGradingConfigSerializer(config).data)
        comparable_before = {k: v for k, v in before.items() if k != 'updated_at'}
        comparable_after = {k: v for k, v in after.items() if k != 'updated_at'}
        if comparable_before != comparable_after:
            record_setup_event(stage, request, 'capstone.grading_configuration_changed',
                semester=semester, old_values=before, values={'configuration': after})
        return Response({
            'grading_config': StageGradingConfigSerializer(config).data,
            'active_semester': SemesterSerializer(semester).data,
        })
