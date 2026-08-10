import logging
import os
from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.pagination import PageNumberPagination
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.views import TokenBlacklistView

from .serializers import (
    ChangePasswordSerializer,
    CustomTokenObtainPairSerializer,
    CustomTokenRefreshSerializer,
    SystemAuditLogSerializer,
    UserSerializer,
)
from .models import SystemAuditLog
from .scopes import audit_logs_for, can_review_audit_logs


logger = logging.getLogger(__name__)
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


class LogoutRateThrottle(AnonRateThrottle):
    scope = 'logout'


class LogoutView(TokenBlacklistView):
    permission_classes = [AllowAny]
    throttle_classes = [LogoutRateThrottle]


class CurrentUserView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user, context={'request': request}).data)

    def patch(self, request):
        user = request.user
        
        # Check if we are removing the avatar
        remove_avatar = (
            request.data.get('remove_avatar') == 'true' or
            request.data.get('avatar') == '' or
            (request.data.get('avatar') is None and 'remove_avatar' in request.data)
        )
        
        if 'avatar' in request.data or 'avatar' in request.FILES or remove_avatar:
            if remove_avatar:
                if user.avatar:
                    user.avatar.delete(save=False)
                user.avatar = None
            else:
                avatar_file = request.FILES.get('avatar')
                if avatar_file:
                    # Validate size (10MB limit)
                    if avatar_file.size > 10 * 1024 * 1024:
                        return Response(
                            {'detail': 'Avatar file size must not exceed 10MB.'},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                    
                    # Validate extension and content type
                    ext = os.path.splitext(avatar_file.name)[1].lower().replace('.', '')
                    allowed_exts = ['png', 'jpg', 'jpeg', 'webp']
                    allowed_types = ['image/jpeg', 'image/png', 'image/webp', 'application/octet-stream']
                    ct = (avatar_file.content_type or '').lower()
                    if ext not in allowed_exts or (ct and ct not in allowed_types and not ct.startswith('image/')):
                        return Response(
                            {'detail': 'Unsupported file format. Please upload JPEG, PNG, or WEBP.'},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                    
                    # Delete old avatar file if it exists
                    if user.avatar:
                        user.avatar.delete(save=False)
                    
                    user.avatar = avatar_file

        # Check if we are removing the e_signature
        remove_e_sig = (
            request.data.get('remove_e_signature') == 'true' or
            request.data.get('e_signature') == '' or
            (request.data.get('e_signature') is None and 'remove_e_signature' in request.data)
        )

        if 'e_signature' in request.data or 'e_signature' in request.FILES or remove_e_sig:
            if remove_e_sig:
                if user.e_signature:
                    user.e_signature.delete(save=False)
                user.e_signature = None
            else:
                sig_file = request.FILES.get('e_signature')
                if sig_file:
                    if sig_file.size > 10 * 1024 * 1024:
                        return Response(
                            {'detail': 'Signature file size must not exceed 10MB.'},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                    ext = os.path.splitext(sig_file.name)[1].lower().replace('.', '')
                    allowed_exts = ['png', 'jpg', 'jpeg', 'webp']
                    allowed_types = ['image/jpeg', 'image/png', 'image/webp', 'application/octet-stream']
                    ct = (sig_file.content_type or '').lower()
                    if ext not in allowed_exts or (ct and ct not in allowed_types and not ct.startswith('image/')):
                        return Response(
                            {'detail': 'Unsupported file format. Please upload JPEG, PNG, or WEBP.'},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                    if user.e_signature:
                        user.e_signature.delete(save=False)
                    user.e_signature = sig_file

        serializer = UserSerializer(user, data=request.data, partial=True, context={'request': request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(
            data=request.data, context={'request': request}
        )
        serializer.is_valid(raise_exception=True)

        user = request.user
        user.set_password(serializer.validated_data['new_password'])
        user.save(update_fields=['password'])

        # Send confirmation email (best-effort).
        try:
            from notifications.email_service import send_password_changed_email
            email_sent = send_password_changed_email(user)
            if not email_sent:
                logger.warning('change_password: password changed but confirmation email failed for user_id=%s', user.pk)
        except Exception as e:
            logger.warning('change_password: error sending confirmation email for user_id=%s: %s', user.pk, e)

        # Create in-app system notification.
        try:
            from notifications.services import create_notification
            from notifications.models import NotificationCategory, NotificationPriority
            create_notification(
                recipient=user,
                title='Password Changed Successfully',
                message='Your account password was updated successfully.',
                category=NotificationCategory.SECURITY,
                priority=NotificationPriority.HIGH,
                action_route='/me/profile',
            )
        except Exception as e:
            logger.warning('change_password: error creating system notification for user_id=%s: %s', user.pk, e)

        return Response({'detail': 'Password changed successfully.'})


class UserHistoryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = SystemAuditLog.objects.filter(actor=request.user)
        limit = 50
        try:
            limit = min(max(int(request.query_params.get('limit', 50)), 1), 200)
        except (TypeError, ValueError):
            pass
        logs = list(queryset[:limit])
        return Response({
            'history': SystemAuditLogSerializer(logs, many=True).data,
            'limit': limit,
        })



class SystemAuditLogPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 200

    def get_page_size(self, request):
        if 'limit' in request.query_params and 'page_size' not in request.query_params:
            try:
                limit_val = int(request.query_params['limit'])
                if limit_val > 0:
                    return min(limit_val, self.max_page_size)
            except (TypeError, ValueError):
                pass
        return super().get_page_size(request)


class SystemAuditLogListView(APIView):
    permission_classes = [IsAuthenticated]
    pagination_class = SystemAuditLogPagination

    def get(self, request):
        if not can_review_audit_logs(request.user):
            raise PermissionDenied('Audit Trail is available to admins and assigned PIT leaders.')
        base_queryset = audit_logs_for(request.user)
        queryset = self._filter_queryset(request, base_queryset)

        paginator = self.pagination_class()
        page = paginator.paginate_queryset(queryset, request, view=self)

        if page is not None:
            serializer = SystemAuditLogSerializer(page, many=True)
            return Response({
                'count': paginator.page.paginator.count,
                'total_pages': paginator.page.paginator.num_pages,
                'current_page': paginator.page.number,
                'next': paginator.get_next_link(),
                'previous': paginator.get_previous_link(),
                'page_size': paginator.get_page_size(request),
                'limit': paginator.get_page_size(request),
                'audit_logs': serializer.data,
                'counts': self._counts(queryset),
                'options': self._options(base_queryset),
            })

        serializer = SystemAuditLogSerializer(queryset, many=True)
        return Response({
            'count': queryset.count(),
            'total_pages': 1,
            'current_page': 1,
            'next': None,
            'previous': None,
            'page_size': len(serializer.data),
            'limit': len(serializer.data),
            'audit_logs': serializer.data,
            'counts': self._counts(queryset),
            'options': self._options(base_queryset),
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


class SystemAuditLogReviewView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        if not can_review_audit_logs(request.user):
            raise PermissionDenied('Audit Trail is available to admins and assigned PIT leaders.')
        base_queryset = audit_logs_for(request.user)
        try:
            log = base_queryset.get(pk=pk)
        except SystemAuditLog.DoesNotExist:
            return Response({'detail': 'Audit log record not found.'}, status=status.HTTP_404_NOT_FOUND)

        new_status = request.data.get('review_status', SystemAuditLog.REVIEW_REVIEWED).strip()
        if new_status not in [choice[0] for choice in SystemAuditLog.REVIEW_STATUS_CHOICES]:
            return Response({'detail': 'Invalid review status.'}, status=status.HTTP_400_BAD_REQUEST)

        log.review_status = new_status
        note = request.data.get('reason', '').strip()
        if note:
            existing = f"{log.reason}\n" if log.reason else ""
            log.reason = f"{existing}[Reviewed by {request.user.username}]: {note}".strip()
        log.save(update_fields=['review_status', 'reason'])

        serializer = SystemAuditLogSerializer(log)
        return Response({
            'detail': 'Audit record review status updated successfully.',
            'audit_log': serializer.data,
        })

