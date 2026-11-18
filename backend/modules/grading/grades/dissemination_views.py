from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView

from . import dissemination
from .dissemination_models import OutcomeReleaseBatch


class OutcomeAPIView(ReadAPIView):
    permission_classes = [IsAuthenticated]

    def handle_exception(self, exc):
        from django.core.exceptions import ValidationError as DjangoValidationError
        from rest_framework.exceptions import ValidationError
        if isinstance(exc, DjangoValidationError):
            exc = ValidationError(exc.messages)
        return super().handle_exception(exc)


class OutcomePreviewView(OutcomeAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        return Response(dissemination.preview(request, request.data))


class OutcomeConfirmView(OutcomeAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        return Response(dissemination.confirm(request, request.data))


class OutcomeHoldView(OutcomeAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, grade_id):
        return Response(dissemination.hold(request, grade_id, request.data))


class OutcomeHistoryView(OutcomeAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        dissemination.require_admin(request.user)
        listing = dissemination.scope_data(request, dict(request.query_params.items()))
        context = listing['context']
        batches = OutcomeReleaseBatch.objects.filter(context__semester_id=context['semester_id'],
            context__scope=context['scope'], context__assessment_id=context['assessment_id']).prefetch_related('releases')[:50]
        return Response({'batches': [dissemination.batch_payload(batch) for batch in batches]})
