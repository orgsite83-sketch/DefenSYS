from django.http import HttpResponse
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import analytics_payload, proposal_payload
from reports.generators.curriculum_proposal_report import generate_curriculum_proposal_pdf


class CurriculumAnalyticsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        academic_year = request.query_params.get('academic_year') or None
        program = request.query_params.get('program') or None
        scope = request.query_params.get('scope') or None
        rubric_id = request.query_params.get('rubric_id') or None
        stage_id = request.query_params.get('stage_id') or None
        return Response(
            analytics_payload(
                request.user,
                academic_year=academic_year,
                program=program,
                scope=scope,
                rubric_id=rubric_id,
                stage_id=stage_id,
            )
        )


class CurriculumProposalView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        academic_year = request.query_params.get('academic_year') or None
        rubric_id = request.query_params.get('rubric_id') or None
        scope = request.query_params.get('scope') or None
        return Response(proposal_payload(request.user, academic_year=academic_year, rubric_id=rubric_id, scope=scope))

    def post(self, request):
        academic_year = request.data.get('academic_year') or request.query_params.get('academic_year') or None
        rubric_id = request.data.get('rubric_id') or request.query_params.get('rubric_id') or None
        scope = request.data.get('scope') or request.query_params.get('scope') or None
        return Response(proposal_payload(request.user, academic_year=academic_year, rubric_id=rubric_id, scope=scope))


class CurriculumProposalPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        academic_year = request.query_params.get('academic_year') or None
        rubric_id = request.query_params.get('rubric_id') or None
        scope = request.query_params.get('scope') or None
        analytics = analytics_payload(request.user, academic_year=academic_year, rubric_id=rubric_id, scope=scope)
        proposal = proposal_payload(request.user, academic_year=academic_year, rubric_id=rubric_id, scope=scope)
        
        user_name = getattr(request.user, 'get_full_name', lambda: '')() or request.user.username
        pdf_bytes = generate_curriculum_proposal_pdf(
            analytics_data=analytics,
            proposal_data=proposal,
            generated_by_user=user_name,
        )

        track_label = f"_{scope.upper()}" if scope else ""
        filename = f"Curriculum_Proposal_AY_{analytics.get('selected_academic_year', 'Report')}{track_label}.pdf"
        response = HttpResponse(pdf_bytes, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response

