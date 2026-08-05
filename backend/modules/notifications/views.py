from collections import OrderedDict
from rest_framework import status
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from .models import Notification
from .serializers import NotificationSerializer


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
            ('notifications', data.get('notifications', [])),
        ]))


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = Notification.objects.filter(recipient=request.user)
        unread_count = qs.filter(is_read=False).count()

        category = request.query_params.get('category')
        if category:
            qs = qs.filter(category=category.upper())

        unread_only = request.query_params.get('unread')
        if unread_only and unread_only.lower() in ('true', '1'):
            qs = qs.filter(is_read=False)

        paginator = NotificationPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        if page is not None:
            serializer = NotificationSerializer(page, many=True)
            return paginator.get_paginated_response({
                'notifications': serializer.data,
                'unread_count': unread_count
            })

        serializer = NotificationSerializer(qs, many=True)
        return Response({
            'notifications': serializer.data,
            'unread_count': unread_count,
        })


class NotificationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        notification = get_object_or_404(Notification, pk=pk, recipient=request.user)
        if not notification.is_read:
            notification.is_read = True
            notification.save(update_fields=['is_read'])
        return Response({
            'status': 'success',
            'notification': NotificationSerializer(notification).data
        })


class NotificationReadAllView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        Notification.objects.filter(recipient=request.user, is_read=False).update(is_read=True)
        return Response({
            'status': 'success',
            'message': 'All notifications marked as read.'
        })
