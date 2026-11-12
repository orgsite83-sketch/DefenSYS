from django.contrib.auth import get_user_model
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from defensys_backend.read_projection import ReadAPIView
from user_management.permissions import IsSystemAdmin
from academic_period_management.services import active_semester
from academic_period_management.serializers import SemesterSerializer
from .models import AdviserCapacityException
from .adviser_capacity import capacity_projections, exception_values, save_exception


class AdviserCapacityView(ReadAPIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def get(self, request):
        term = active_semester()
        advisers = list(get_user_model().objects.filter(is_active=True,
            role__in=['faculty', 'admin']).order_by('first_name', 'last_name', 'username'))
        capacities = capacity_projections([user.pk for user in advisers])
        return Response({'active_semester': SemesterSerializer(term).data if term else None,
            'advisers': [{'id': user.pk, 'name': user.get_full_name() or user.username,
                          'capacity': capacities[user.pk]} for user in advisers],
            'exceptions': [{'id': row.pk, **exception_values(row)} for row in
                AdviserCapacityException.objects.select_related('intake_semester__school_year').order_by('-updated_at')]})

    def post(self, request):
        row = save_exception(request.user, request.data)
        return Response({'exception': {'id': row.pk, **exception_values(row)}})


class AdviserCapacityRevokeView(ReadAPIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def post(self, request):
        row = save_exception(request.user, request.data, revoke=True)
        return Response({'exception': {'id': row.pk, **exception_values(row)}})
