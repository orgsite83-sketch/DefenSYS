from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import analytics_payload, classify_payload, proposal_payload


class CurriculumAnalyticsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(
            analytics_payload(
                request.user,
                academic_year=request.query_params.get('academic_year') or None,
            )
        )


class CurriculumClassifierView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        text = (request.data.get('text') or '').strip()
        if not text:
            raise ValidationError({'text': 'Paste an abstract or project description to classify.'})
        return Response(classify_payload(request.user, text))


class CurriculumProposalView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        return Response(proposal_payload(request.user))
