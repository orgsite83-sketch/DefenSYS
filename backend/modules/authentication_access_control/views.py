from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.views import TokenBlacklistView

from .serializers import (
    CustomTokenObtainPairSerializer,
    CustomTokenRefreshSerializer,
    SystemAuditLogSerializer,
    UserSerializer,
)
from .models import SystemAuditLog
from .scopes import audit_logs_for, can_review_audit_logs


User = get_user_model()


class LoginRateThrottle(AnonRateThrottle):
    scope = 'login'


class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]
    throttle_classes = [LoginRateThrottle]


class RefreshRateThrottle(AnonRateThrottle):
    scope = 'token_refresh'


class ThrottledTokenRefreshView(TokenRefreshView):
    serializer_class = CustomTokenRefreshSerializer
    throttle_classes = [RefreshRateThrottle]
    permission_classes = [AllowAny]


class LogoutView(TokenBlacklistView):
    permission_classes = [AllowAny]


class CurrentUserView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)


class SystemAuditLogListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not can_review_audit_logs(request.user):
            raise PermissionDenied('Audit Trail is available to admins and assigned PIT leaders.')
        base_queryset = audit_logs_for(request.user)
        queryset = base_queryset
        queryset = self._filter_queryset(request, queryset)
        limit = self._limit(request)
        logs = list(queryset[:limit])
        return Response({
            'audit_logs': SystemAuditLogSerializer(logs, many=True).data,
            'counts': self._counts(queryset),
            'options': self._options(base_queryset),
            'limit': limit,
        })

    def _filter_queryset(self, request, queryset):
        category = request.query_params.get('category', '').strip()
        action = request.query_params.get('action', '').strip()
        review_status = request.query_params.get('review_status', '').strip()
        actor_id = request.query_params.get('actor', '').strip()
        search = request.query_params.get('search', '').strip()
        start_date = parse_date(request.query_params.get('start_date', '').strip())
        end_date = parse_date(request.query_params.get('end_date', '').strip())
        track = request.query_params.get('track', '').strip().lower()
        year_level = request.query_params.get('year_level', '').strip()

        if category:
            queryset = queryset.filter(category=category)
        if action:
            queryset = queryset.filter(action=action)
        if review_status:
            queryset = queryset.filter(review_status=review_status)
        if actor_id:
            queryset = queryset.filter(actor_id=actor_id)
        if start_date:
            queryset = queryset.filter(created_at__date__gte=start_date)
        if end_date:
            queryset = queryset.filter(created_at__date__lte=end_date)
        if track:
            pit_marker = (
                Q(old_values__entry_type='pit')
                | Q(new_values__entry_type='pit')
                | Q(old_values__scope='pit')
                | Q(new_values__scope='pit')
                | Q(old_values__track='pit')
                | Q(new_values__track='pit')
            )
            if track == 'pit':
                queryset = queryset.filter(pit_marker)
            elif track == 'capstone':
                pit_ids = queryset.filter(pit_marker).values_list('id', flat=True)
                queryset = queryset.exclude(id__in=pit_ids)
        if year_level:
            year_marker = (
                Q(old_values__year_level=year_level)
                | Q(new_values__year_level=year_level)
                | Q(old_values__team_year_level=year_level)
                | Q(new_values__team_year_level=year_level)
                | Q(old_values__pit_year_level=year_level)
                | Q(new_values__pit_year_level=year_level)
            )
            queryset = queryset.filter(year_marker)
        if search:
            queryset = queryset.filter(
                Q(action__icontains=search)
                | Q(target_type__icontains=search)
                | Q(target_id__icontains=search)
                | Q(reason__icontains=search)
                | Q(actor__username__icontains=search)
                | Q(actor__first_name__icontains=search)
                | Q(actor__last_name__icontains=search)
            )
        return queryset


    def _limit(self, request):
        try:
            return min(max(int(request.query_params.get('limit', 50)), 1), 200)
        except (TypeError, ValueError):
            return 50

    def _counts(self, queryset):
        return {
            'filtered': queryset.count(),
            'captured': queryset.filter(
                review_status=SystemAuditLog.REVIEW_CAPTURED,
            ).count(),
            'needs_review': queryset.filter(
                review_status__in=[
                    SystemAuditLog.REVIEW_NEEDS_REVIEW,
                    SystemAuditLog.REVIEW_REQUIRES_REASON,
                ],
            ).count(),
            'requires_reason': queryset.filter(
                review_status=SystemAuditLog.REVIEW_REQUIRES_REASON,
            ).count(),
            'reviewed': queryset.filter(review_status=SystemAuditLog.REVIEW_REVIEWED).count(),
        }

    def _options(self, queryset):
        actor_ids = queryset.exclude(actor__isnull=True).values_list(
            'actor_id',
            flat=True,
        )
        return {
            'categories': [
                {'value': value, 'label': label}
                for value, label in SystemAuditLog.CATEGORY_CHOICES
            ],
            'review_statuses': [
                {'value': value, 'label': label}
                for value, label in SystemAuditLog.REVIEW_STATUS_CHOICES
            ],
            'actions': list(
                queryset.order_by('action')
                .values_list('action', flat=True)
                .distinct()
            ),
            'actors': [
                {
                    'id': user.id,
                    'name': f'{user.first_name} {user.last_name}'.strip() or user.username,
                }
                for user in User.objects.filter(id__in=actor_ids)
                .distinct()
                .order_by('username')
            ],
        }
