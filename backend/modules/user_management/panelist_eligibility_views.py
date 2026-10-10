from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.pagination import PageNumberPagination
from django.db.models import Q
from authentication_access_control.scopes import is_admin_user

from .models import PanelistEligibilityRequest
from .permissions import IsPitLeadOrAdmin, IsSystemAdmin
from .panelist_eligibility import (
    nominate_panelist, request_payload, review_nomination, visible_requests,
)


class NominationSerializer(serializers.Serializer):
    faculty_id = serializers.IntegerField(min_value=1)
    reason = serializers.CharField(
        max_length=1000, allow_blank=True, required=False, default='',
    )


class ReviewSerializer(serializers.Serializer):
    decision = serializers.ChoiceField(choices=['approved', 'declined'])
    review_note = serializers.CharField(
        max_length=1000, allow_blank=True, required=False, default='',
    )


class PanelistEligibilityRequestsView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def get(self, request):
        selection = request.query_params.get('status', 'pending' if is_admin_user(request.user) else 'all')
        if selection not in ('pending', 'reviewed', 'all'):
            raise ValidationError({'status': 'Choose pending, reviewed, or all requests.'})
        items = visible_requests(request.user, include_reviewed=True)
        faculty_id = request.query_params.get('faculty_id')
        if faculty_id is not None:
            try:
                faculty_id = int(faculty_id)
                if faculty_id < 1:
                    raise ValueError
            except (ValueError, TypeError):
                raise ValidationError({'faculty_id': 'Choose a valid faculty member.'})
            items = items.filter(faculty_id=faculty_id)
        pending_count = items.filter(status='pending').count()
        reviewed_count = items.exclude(status='pending').count()
        if selection == 'pending':
            items = items.filter(status='pending')
        elif selection == 'reviewed':
            items = items.exclude(status='pending')
        search = request.query_params.get('search', '').strip()
        for term in search.split():
            items = items.filter(
                Q(faculty__first_name__icontains=term) |
                Q(faculty__last_name__icontains=term) |
                Q(faculty__username__icontains=term) |
                Q(requested_by__first_name__icontains=term) |
                Q(requested_by__last_name__icontains=term) |
                Q(requested_by__username__icontains=term)
            )
        paginator = PageNumberPagination()
        paginator.page_size = 20
        page = paginator.paginate_queryset(items, request, view=self)
        return Response({
            'panelist_requests': [request_payload(r) for r in page],
            'count': paginator.page.paginator.count,
            'next': paginator.get_next_link(),
            'pending_count': pending_count,
            'reviewed_count': reviewed_count,
        })

    def post(self, request):
        data = NominationSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        item, created = nominate_panelist(
            request.user, data.validated_data['faculty_id'], data.validated_data['reason'],
        )
        return Response(
            {
                'request': request_payload(item) if item else None,
                'already_eligible': item is None,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class PanelistEligibilityRequestReviewView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def get(self, request, request_id):
        items = PanelistEligibilityRequest.objects.select_related('faculty', 'requested_by', 'reviewed_by')
        if not is_admin_user(request.user):
            items = items.filter(requested_by=request.user)
        item = get_object_or_404(items, pk=request_id)
        return Response({'request': request_payload(item), 'can_review': is_admin_user(request.user)})

    def patch(self, request, request_id):
        if not is_admin_user(request.user):
            raise PermissionDenied('Only admins can review panelist eligibility.')
        data = ReviewSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        item = get_object_or_404(PanelistEligibilityRequest, pk=request_id)
        item = review_nomination(
            request.user, item,
            data.validated_data['decision'], data.validated_data['review_note'],
        )
        return Response({'request': request_payload(item)})
