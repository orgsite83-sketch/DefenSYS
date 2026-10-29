from django.db import transaction
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers as drf_serializers
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView as APIView

from academic_period_management.serializers import SemesterSerializer
from defense.stages.models import DefenseStage
from grading.constants import PASS_GRADE_THRESHOLD
from defense.stages.serializers import DefenseStageSerializer
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.scopes import grade_records_for, manageable_grades_for
from authentication_access_control.workspaces import workspace_grades_for
from user_management.permissions import IsSystemAdmin, CanManageModule
from .models import TeamGrade
from academic_period_management.models import Semester
from .serializers import TeamGradeSerializer, TeamGradeUpdateSerializer
from django.core.exceptions import PermissionDenied, ValidationError as DjangoValidationError

from .services import (
    _apply_team_result_from_grade,
    active_semester,
    build_group_settings_map,
    group_settings_key,
    group_completion_readiness,
    grade_review_queryset,
    publish_grade_record,
    require_grade_editable,
    sync_missing_grade_rows,
    IncompleteGradingTeamsError,
    update_group_settings,
    without_stale_unscheduled_placeholders,
)





def _is_grade_center_admin(user):
    return bool(
        user
        and (
            getattr(user, 'role', None) == 'admin'
            or getattr(user, 'is_superuser', False)
        )
    )


def filter_grade_queryset(request, queryset):
    semester = selected_grade_semester(request)
    queryset = queryset.filter(semester=semester) if semester else queryset.none()
    search = request.query_params.get('search', '').strip()
    year_level = request.query_params.get('year_level', '').strip()
    status_filter = request.query_params.get('status', '').strip()

    if search:
        queryset = queryset.filter(
            Q(team__name__icontains=search)
            | Q(team__project_title__icontains=search)
            | Q(stage_label__icontains=search)
            | Q(team__adviser__first_name__icontains=search)
            | Q(team__adviser__last_name__icontains=search)
            | Q(team__adviser__username__icontains=search)
            | Q(schedule__panel_assignments__panelist__first_name__icontains=search)
            | Q(schedule__panel_assignments__panelist__last_name__icontains=search)
            | Q(schedule__panel_assignments__panelist__username__icontains=search)
        ).distinct()
    if year_level:
        queryset = queryset.filter(team__year_level=year_level)
    if status_filter:
        queryset = queryset.filter(status=status_filter)

    team_id = request.query_params.get('team_id', '').strip()
    if team_id:
        queryset = queryset.filter(team_id=team_id)

    if 'scope' not in request.query_params:
        if _is_grade_center_admin(request.user):
            queryset = queryset.filter(scope=TeamGrade.SCOPE_CAPSTONE)
    else:
        scope = request.query_params.get('scope', '').strip()
        if scope and scope != 'all':
            queryset = queryset.filter(scope=scope)

    return queryset


def selected_grade_semester(request):
    if request.query_params.get('semester_id'):
        from academic_period_management.models import Semester
        from rest_framework.serializers import IntegerField
        return get_object_or_404(Semester, pk=IntegerField(min_value=1).run_validation(
            request.query_params['semester_id']))
    return active_semester()


def counts_payload(base_queryset, current_queryset=None):
    current = current_queryset if current_queryset is not None else base_queryset
    # Mirror TeamGrade.result: configured defenses use the recorded outcome;
    # only PIT and historical defenses without an outcome use academic totals.
    legacy_policy = (Q(schedule__isnull=True)
                     | Q(schedule__assessment_policy__version__isnull=True)
                     | ~Q(schedule__assessment_policy__version=1))
    numeric_result = (Q(scope=TeamGrade.SCOPE_PIT)
                      | (Q(scope=TeamGrade.SCOPE_CAPSTONE, verdict='') & legacy_policy))
    approved_result = Q(scope=TeamGrade.SCOPE_CAPSTONE) & (
        Q(verdict='approved')
        | Q(verdict='approved_with_revisions', revisions_cleared_at__isnull=False))
    failed_result = Q(scope=TeamGrade.SCOPE_CAPSTONE) & (
        Q(verdict__in=('failed', 'project_rejected')) | Q(outcome_metadata__closure__failed=True))
    base_agg = base_queryset.aggregate(
        all=Count('pk'),
        total_capstone=Count('pk', filter=Q(scope=TeamGrade.SCOPE_CAPSTONE)),
        total_pit=Count('pk', filter=Q(scope=TeamGrade.SCOPE_PIT)),
    )
    current_agg = current.aggregate(
        filtered=Count('pk'),
        published=Count('pk', filter=Q(status=TeamGrade.STATUS_PUBLISHED)),
        pending=Count('pk', filter=Q(status=TeamGrade.STATUS_PENDING)),
        awaiting_peers=Count('pk', filter=Q(status=TeamGrade.STATUS_AWAITING_PEERS)),
        passed=Count('pk', filter=approved_result | (numeric_result & Q(final_grade__gte=PASS_GRADE_THRESHOLD))),
        failed=Count('pk', filter=failed_result | (numeric_result & Q(final_grade__lt=PASS_GRADE_THRESHOLD))),
        capstone=Count('pk', filter=Q(scope=TeamGrade.SCOPE_CAPSTONE)),
        pit=Count('pk', filter=Q(scope=TeamGrade.SCOPE_PIT)),
    )
    return {
        'all': base_agg['all'] or 0,
        'filtered': current_agg['filtered'] or 0,
        'published': current_agg['published'] or 0,
        'pending': current_agg['pending'] or 0,
        'awaiting_peers': current_agg['awaiting_peers'] or 0,
        'passed': current_agg['passed'] or 0,
        'failed': current_agg['failed'] or 0,
        'total_capstone': base_agg['total_capstone'] or 0,
        'total_pit': base_agg['total_pit'] or 0,
        'capstone': current_agg['capstone'] or 0,
        'pit': current_agg['pit'] or 0,
    }


def options_payload(queryset):
    year_levels = [
        value
        for value in queryset.values_list('team__year_level', flat=True).distinct()
        if value
    ]
    return {
        'statuses': [choice[0] for choice in TeamGrade.STATUS_CHOICES],
        'year_levels': sorted(set(year_levels)),
        'scopes': [
            {'value': key, 'label': label}
            for key, label in TeamGrade.SCOPE_CHOICES
        ],
    }


def grade_center_payload(request, queryset=None, sync_info=None):
    raw_base = workspace_grades_for(request.user, request.query_params.get('workspace'))
    semester = selected_grade_semester(request)
    available_terms = set(raw_base.values_list('semester_id', flat=True))
    from defense.scheduler.event_scope import pit_events_for_user
    available_terms.update(pit_events_for_user(request.user).values_list('semester_id', flat=True))
    active = active_semester()
    if active:
        available_terms.add(active.pk)
    raw_base = raw_base.filter(semester=semester) if semester else raw_base.none()
    base = without_stale_unscheduled_placeholders(grade_review_queryset(raw_base))
    current = without_stale_unscheduled_placeholders(
        grade_review_queryset(queryset if queryset is not None else raw_base)
    )
    payload = {
        'grades': TeamGradeSerializer(current, many=True).data,
        'counts': counts_payload(base, current),
        'active_semester': SemesterSerializer(semester).data if semester else None,
        'selected_semester_id': semester.pk if semester else None,
        'history_semesters': [{'id': t.pk, 'label': t.display_name} for t in
            Semester.objects
                .filter(pk__in=available_terms).select_related('school_year')
                .exclude(pk=active.pk if active else None)
                .order_by('-school_year__label', 'label')],
        'group_settings': build_group_settings_map(current, semester, user=request.user),
        **options_payload(base),
    }
    if CanManageModule().has_permission(request, None):
        from authentication_access_control.scopes import is_admin_user
        active_stages = list(DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label')) if is_admin_user(request.user) else []
        if active_stages and semester:
            from authentication_access_control.workspaces import workspace_teams_for
            from student_teams.capstone_lifecycle import teams_in_recorded_term, recorded_team
            from student_teams.capstone_context import phase_requirements
            teams = teams_in_recorded_term(workspace_teams_for(request.user,
                request.query_params.get('workspace')).filter(level__icontains='Capstone'), semester)
            applicable = {r['id'] for team in teams for r in phase_requirements(recorded_team(team, semester))}
            active_stages = [s for s in active_stages if s.pk in applicable]
        payload['capstone_stages'] = DefenseStageSerializer(
            active_stages,
            many=True,
            context={'ordered_stages': active_stages, 'semester': semester},
        ).data
        if semester:
            from defense.scheduler.models import PitEventGradingConfig
            from defense.scheduler.pit_config import pit_event_config_payload
            from authentication_access_control.scopes import is_pit_lead_only, _pit_year

            pit_lead = is_pit_lead_only(request.user)
            pit_year = _pit_year(request.user) if pit_lead else None

            from defense.scheduler.event_scope import pit_events_for_user
            configs = pit_events_for_user(request.user, semester=semester).prefetch_related('deliverables').order_by('event_name')
            payload['pit_events'] = [pit_event_config_payload(c) for c in configs]
        else:
            payload['pit_events'] = []
    if sync_info is not None:
        payload['sync'] = sync_info
    return payload


def grade_audit_values(grade):
    return {
        'grade_id': grade.pk,
        'team_id': grade.team_id,
        'team_name': getattr(grade.team, 'name', '') or getattr(grade, 'team_name', ''),
        'stage_label': getattr(grade, 'stage_label', ''),
        'panel_score': str(grade.panel_score) if grade.panel_score is not None else None,
        'panel_score_is_override': grade.panel_score_is_override,
        'adviser_score': str(grade.adviser_score) if grade.adviser_score is not None else None,
        'adviser_score_is_override': grade.adviser_score_is_override,
        'peer_score': str(grade.peer_score) if grade.peer_score is not None else None,
        'peer_score_is_override': grade.peer_score_is_override,
        'final_grade': str(grade.final_grade) if grade.final_grade is not None else None,
        'status': grade.status,
    }


class GradeCenterListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = filter_grade_queryset(request, workspace_grades_for(request.user, request.query_params.get('workspace')))
        return Response(grade_center_payload(request, queryset))


class GradeMasterlistView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from .masterlist import build_masterlist
        return Response(build_masterlist(request))


class GradeCenterSyncView(APIView):
    permission_classes = [CanManageModule]

    def post(self, request):
        sync_info = sync_missing_grade_rows(user=request.user)
        queryset = filter_grade_queryset(request, workspace_grades_for(request.user, request.query_params.get('workspace')))
        return Response(grade_center_payload(request, queryset, sync_info=sync_info))


class GradeCenterDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get_object(self, request, grade_id):
        return get_object_or_404(workspace_grades_for(request.user, request.query_params.get('workspace')), pk=grade_id)

    def get(self, request, grade_id):
        grade = get_object_or_404(workspace_grades_for(request.user,
            request.query_params.get('workspace'), include_previous_projects=True), pk=grade_id)
        return Response({'grade': TeamGradeSerializer(grade, context={'request': request}).data})

    def patch(self, request, grade_id):
        if not IsSystemAdmin().has_permission(request, self):
            raise PermissionDenied('Only administrators can correct recorded grades.')
        grade = self.get_object(request, grade_id)
        from .corrections import request_correction
        changes = {key: value for key, value in request.data.items() if key in ('panel_score', 'adviser_score', 'peer_score')}
        result = request_correction(grade.pk, request.user, {
            'changes': {'aggregate': changes}, 'reason': request.data.get('reason'),
            'expected_updated_at': request.data.get('expected_updated_at'),
        }, request=request)
        grade.refresh_from_db()
        return Response({'grade': TeamGradeSerializer(grade).data, 'correction': result})


class GradeCorrectionsView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, grade_id):
        from .corrections import correction_details
        grade = get_object_or_404(grade_records_for(request.user), pk=grade_id)
        return Response(correction_details(grade))

    def post(self, request, grade_id):
        from .corrections import request_correction, review_correction
        get_object_or_404(grade_records_for(request.user), pk=grade_id)
        serializer = CorrectionActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if data['action'] in ('approve', 'reject'):
            result = review_correction(grade_id, data.get('correction_id'), request.user, data, request=request)
        else:
            result = request_correction(grade_id, request.user, data, request=request)
        return Response(result)


class CorrectionActionSerializer(drf_serializers.Serializer):
    action = drf_serializers.ChoiceField(choices=['request', 'approve', 'reject'], default='request')
    reason = drf_serializers.CharField(min_length=5, max_length=2000)
    changes = drf_serializers.DictField(required=False)
    expected_updated_at = drf_serializers.CharField(required=False)
    preview = drf_serializers.BooleanField(default=False)
    correction_id = drf_serializers.IntegerField(min_value=1, required=False)
    acknowledge_published_change = drf_serializers.BooleanField(default=False)


class GradeCenterPublishView(APIView):
    permission_classes = [CanManageModule]

    @transaction.atomic
    def post(self, request, grade_id):
        grade = get_object_or_404(manageable_grades_for(request.user), pk=grade_id)
        old_values = grade_audit_values(grade)
        try:
            require_grade_editable(grade)
        except DjangoValidationError as exc:
            return Response(
                {'detail': exc.messages[0] if getattr(exc, 'messages', None) else str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            grade = publish_grade_record(grade, user=request.user)
        except DjangoValidationError as exc:
            return Response({'detail': ' '.join(exc.messages)}, status=status.HTTP_400_BAD_REQUEST)
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='grade.publish',
            target=grade,
            old_values=old_values,
            new_values=grade_audit_values(grade),
            reason=request.data.get('reason', ''),
            request=request,
            strict=True,
        )
        grade = grade_records_for(request.user).get(pk=grade.pk)
        return Response({
            'grade': TeamGradeSerializer(grade).data,
            **grade_center_payload(request),
        })


class CapstoneEvaluationSettingsSerializer(drf_serializers.Serializer):
    capstone_peer_evaluation_enabled = drf_serializers.BooleanField(required=False)
    capstone_adviser_grading_enabled = drf_serializers.BooleanField(required=False)


class CapstoneEvaluationSettingsView(APIView):
    permission_classes = [IsSystemAdmin]

    def patch(self, request):
        semester = active_semester()
        if semester is None:
            return Response(
                {'detail': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = CapstoneEvaluationSettingsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        update_fields = []
        if 'capstone_peer_evaluation_enabled' in data:
            semester.capstone_peer_evaluation_enabled = data['capstone_peer_evaluation_enabled']
            update_fields.append('capstone_peer_evaluation_enabled')
        if 'capstone_adviser_grading_enabled' in data:
            semester.capstone_adviser_grading_enabled = data['capstone_adviser_grading_enabled']
            update_fields.append('capstone_adviser_grading_enabled')
        if update_fields:
            semester.save(update_fields=update_fields)
            from realtime.broadcast import notify_capstone_evaluation_flags

            notify_capstone_evaluation_flags(
                semester,
                peer_eval_enabled=semester.capstone_peer_evaluation_enabled
                if 'capstone_peer_evaluation_enabled' in update_fields
                else None,
                adviser_grading_enabled=semester.capstone_adviser_grading_enabled
                if 'capstone_adviser_grading_enabled' in update_fields
                else None,
            )
        return Response({'active_semester': SemesterSerializer(semester).data})


class GradeCenterGroupSettingsSerializer(drf_serializers.Serializer):
    scope = drf_serializers.ChoiceField(choices=[TeamGrade.SCOPE_CAPSTONE, TeamGrade.SCOPE_PIT])
    stage_label = drf_serializers.CharField(max_length=120, required=False, allow_blank=True)
    defense_stage_id = drf_serializers.IntegerField(required=False, allow_null=True)
    pit_event_config_id = drf_serializers.IntegerField(required=False, allow_null=True)
    is_officially_complete = drf_serializers.BooleanField(required=False)
    peer_grading_enabled = drf_serializers.BooleanField(required=False)
    failure_grade_ids = drf_serializers.ListField(child=drf_serializers.IntegerField(), required=False)
    closure_reason = drf_serializers.CharField(max_length=5000, required=False, allow_blank=True)
    completion_token = drf_serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        if 'is_officially_complete' not in attrs and 'peer_grading_enabled' not in attrs:
            raise drf_serializers.ValidationError('At least one setting field is required.')
        if not (attrs.get('stage_label') or attrs.get('defense_stage_id') or attrs.get('pit_event_config_id')):
            raise drf_serializers.ValidationError('stage_label, defense_stage_id, or pit_event_config_id is required.')
        return attrs


class GradeCenterGroupReadinessSerializer(drf_serializers.Serializer):
    scope = drf_serializers.ChoiceField(choices=[TeamGrade.SCOPE_CAPSTONE, TeamGrade.SCOPE_PIT])
    stage_label = drf_serializers.CharField(max_length=120)


class GradeCenterGroupSettingsView(APIView):
    permission_classes = [CanManageModule]

    def get(self, request):
        semester = active_semester()
        if semester is None:
            return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)
        serializer = GradeCenterGroupReadinessSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        try:
            payload = group_completion_readiness(
                semester=semester, user=request.user, **serializer.validated_data,
            )
        except PermissionDenied as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except DjangoValidationError as exc:
            payload = exc.message_dict if hasattr(exc, 'message_dict') else {'detail': exc.messages}
            return Response(payload, status=status.HTTP_400_BAD_REQUEST)
        return Response(payload)

    def patch(self, request):
        semester = active_semester()
        if semester is None:
            return Response(
                {'detail': 'No active semester is configured.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = GradeCenterGroupSettingsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        stage_label = data.get('stage_label', '')
        if data['scope'] == TeamGrade.SCOPE_CAPSTONE and data.get('defense_stage_id'):
            from defense.stages.models import DefenseStage

            stage = get_object_or_404(DefenseStage, pk=data['defense_stage_id'])
            stage_label = stage.label
        elif data['scope'] == TeamGrade.SCOPE_PIT and data.get('pit_event_config_id'):
            from defense.scheduler.models import PitEventGradingConfig

            config = get_object_or_404(
                PitEventGradingConfig,
                pk=data['pit_event_config_id'],
                semester=semester,
            )
            stage_label = config.event_name
        try:
            settings = update_group_settings(
                semester=semester,
                scope=data['scope'],
                stage_label=stage_label,
                is_officially_complete=data.get('is_officially_complete'),
                peer_grading_enabled=data.get('peer_grading_enabled'),
                user=request.user,
                failure_grade_ids=data.get('failure_grade_ids'),
                closure_reason=data.get('closure_reason', ''),
                completion_token=data.get('completion_token'),
            )
        except IncompleteGradingTeamsError as exc:
            return Response(
                {
                    'detail': (
                        'Cannot mark officially complete until every team has '
                        'panel grading, peer evaluation (when required), and '
                        'adviser grading (when required).'
                    ),
                    'incomplete_teams': exc.teams,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        except PermissionDenied as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except DjangoValidationError as exc:
            payload = exc.message_dict if hasattr(exc, 'message_dict') else {'detail': exc.messages}
            return Response(payload, status=status.HTTP_400_BAD_REQUEST)

        key = group_settings_key(data['scope'], stage_label)
        response_payload = {'group_settings': {key: settings}}
        auto_publish = settings.get('auto_publish')
        if auto_publish:
            response_payload['auto_publish'] = auto_publish
        auto_finalize = settings.get('auto_finalize')
        if auto_finalize:
            response_payload['auto_finalize'] = auto_finalize
        return Response(response_payload)


class TeamGradeVerdictView(APIView):
    """
    API endpoint to record or update defense verdict for a specific TeamGrade.
    Accessible to administrators and the assigned panel chair.
    """
    permission_classes = [IsAuthenticated]

    def patch(self, request, grade_id):
        workspace = request.query_params.get('workspace')
        queryset = workspace_grades_for(request.user, workspace) if workspace else TeamGrade.objects.with_relations()
        grade = get_object_or_404(queryset, pk=grade_id)

        is_admin = (
            request.user.is_staff
            or request.user.is_superuser
            or getattr(request.user, 'role', None) == 'admin'
        )
        is_chair = False
        if grade.schedule:
            is_chair = grade.schedule.panel_assignments.filter(
                panelist=request.user,
                is_chair=True,
            ).exists()

        if not (is_admin or is_chair):
            return Response(
                {'detail': 'Only the panel chair or an administrator can issue defense verdicts.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        verdict = request.data.get('verdict')
        valid_verdicts = [v[0] for v in TeamGrade.VERDICT_CHOICES]
        if not verdict or verdict not in valid_verdicts:
            return Response(
                {
                    'detail': f'Invalid verdict "{verdict}". Must be one of: {", ".join(valid_verdicts)}.',
                    'valid_verdicts': valid_verdicts,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        verdict_remarks = (request.data.get('verdict_remarks') or '').strip()
        revision_deadline = request.data.get('revision_deadline')
        parsed_deadline = None
        if revision_deadline:
            from django.utils.dateparse import parse_date
            parsed_deadline = parse_date(str(revision_deadline).strip())
            if not parsed_deadline:
                return Response(
                    {'detail': 'Invalid revision_deadline format (YYYY-MM-DD expected).'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        from .defense_workflow import record_verdict
        try:
            grade = record_verdict(grade, actor=request.user, verdict=verdict,
                remarks=verdict_remarks, deadline=parsed_deadline,
                verification_required=drf_serializers.BooleanField().run_validation(request.data.get('redefense_verification_required', False)),
                concept_decisions=request.data.get('concept_decisions'),
                replacement_concepts_required=drf_serializers.BooleanField().run_validation(request.data.get('replacement_concepts_required', False)))
        except DjangoValidationError as exc:
            return Response({'detail': ' '.join(exc.messages)}, status=status.HTTP_400_BAD_REQUEST)



        grade = grade_records_for(request.user).get(pk=grade.pk)
        return Response({
            'success': True,
            'message': f'Defense verdict "{verdict}" recorded successfully.',
            'grade': TeamGradeSerializer(grade).data,
            **grade_center_payload(request),
        })


class TeamGradeAssessmentView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, grade_id):
        grade = get_object_or_404(grade_records_for(request.user), pk=grade_id)
        from .automatic_outcomes import resolve_outcome, save_recommendations
        from .outcome_rules import automatic_outcomes
        if not automatic_outcomes(grade.schedule):
            return Response({'detail': 'This hearing uses its captured manual assessment policy.'}, status=400)
        try:
            if request.data.get('action') == 'select_concept':
                key = drf_serializers.CharField(max_length=32).run_validation(request.data.get('concept_key'))
                token = drf_serializers.CharField().run_validation(request.data.get('review_token'))
                grade = resolve_outcome(grade, actor=request.user, selected_key=key, review_token=token)
            elif request.data.get('action') == 'recommendations':
                token = drf_serializers.CharField().run_validation(request.data.get('review_token'))
                grade = save_recommendations(grade, actor=request.user, notes=request.data.get('recommendations', ''), review_token=token)
            else:
                return Response({'detail': 'Choose concept selection or recommendations.'}, status=400)
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=403)
        except DjangoValidationError as exc:
            return Response({'detail': ' '.join(exc.messages)}, status=400)
        return Response({'grade': TeamGradeSerializer(grade, context={'request': request}).data})


class TeamGradeWorkflowView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, grade_id):
        grade = get_object_or_404(workspace_grades_for(request.user, request.query_params.get('workspace')), pk=grade_id)
        from .defense_workflow import workflow_payload
        return Response({'workflow': workflow_payload(grade)})

    def post(self, request, grade_id):
        grade = get_object_or_404(workspace_grades_for(request.user, request.query_params.get('workspace')), pk=grade_id)
        from .defense_workflow import apply_workflow_action
        unknown = set(request.data) - {'action', 'reason', 'review_date'}
        if unknown:
            raise drf_serializers.ValidationError({key: 'Unsupported workflow field.' for key in sorted(unknown)})
        review_date = drf_serializers.DateField(allow_null=True).run_validation(request.data.get('review_date'))
        action = request.data.get('action', '')
        reason = drf_serializers.CharField(allow_blank=True).run_validation(request.data.get('reason', ''))
        try:
            team = apply_workflow_action(grade, actor=request.user, action=action,
                reason=reason, review_date=review_date)
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except DjangoValidationError as exc:
            return Response({'detail': ' '.join(exc.messages)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'success': True, 'team_id': team.pk,
            'project_version': team.project_version, 'message': 'Defense workflow updated.',
            **grade_center_payload(request)})

