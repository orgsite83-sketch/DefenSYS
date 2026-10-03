from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

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
        return Response({
            'panelist_requests': [
                request_payload(r) for r in visible_requests(request.user)[:100]
            ],
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
    permission_classes = [IsSystemAdmin]

    def patch(self, request, request_id):
        data = ReviewSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        item = get_object_or_404(PanelistEligibilityRequest, pk=request_id)
        item = review_nomination(
            request.user, item,
            data.validated_data['decision'], data.validated_data['review_note'],
        )
        return Response({'request': request_payload(item)})
