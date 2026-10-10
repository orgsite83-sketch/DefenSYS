from collections import OrderedDict
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from .models import Notification, NotificationWorkspace
from .serializers import NotificationSerializer
from .actions import resolve_actions


class NotificationPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 100

    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ('count', self.page.paginator.count),
            ('next', self.get_next_link()),
            ('previous', self.get_previous_link()),
            ('unread_count', data.get('unread_count', 0)),
            ('total_count', data.get('total_count', 0)),
            ('notifications', data.get('notifications', [])),
        ]))


def workspace_notifications(request):
    """List and read operations share the same recipient + inbox boundary."""
    workspace = request.query_params.get('workspace', request.user.role)
    if workspace not in NotificationWorkspace.values:
        raise ValidationError({'workspace': 'Select a valid notification workspace.'})
    return Notification.objects.filter(recipient=request.user, workspace=workspace)


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = workspace_notifications(request).select_related('sender')
        unread_count = qs.filter(is_read=False).count()
        total_count = qs.count()

        category = request.query_params.get('category')
        if category:
            qs = qs.filter(category=category.upper())

        unread_only = request.query_params.get('unread')
        if unread_only and unread_only.lower() in ('true', '1'):
            qs = qs.filter(is_read=False)

        paginator = NotificationPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        if page is not None:
            serializer = NotificationSerializer(page, many=True, context={'actions': resolve_actions(page, request.user)})
            return paginator.get_paginated_response({
                'notifications': serializer.data,
                'unread_count': unread_count,
                'total_count': total_count,
            })

        serializer = NotificationSerializer(qs, many=True, context={'actions': resolve_actions(qs, request.user)})
        return Response({
            'notifications': serializer.data,
            'unread_count': unread_count,
            'total_count': total_count,
        })


class NotificationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        notification = get_object_or_404(workspace_notifications(request).select_related('sender'), pk=pk)
        return Response({'notification': NotificationSerializer(notification, context={'actor': request.user}).data})

    def post(self, request, pk):
        notification = get_object_or_404(workspace_notifications(request), pk=pk)
        if not notification.is_read:
            notification.is_read = True
            notification.save(update_fields=['is_read'])
        return Response({
            'status': 'success',
            'notification': NotificationSerializer(notification, context={'actor': request.user}).data,
            'unread_count': workspace_notifications(request).filter(is_read=False).count(),
        })


class NotificationReadAllView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        updated_count = workspace_notifications(request).filter(is_read=False).update(is_read=True)
        return Response({
            'status': 'success',
            'message': 'Workspace notifications marked as read.',
            'updated_count': updated_count,
        })
