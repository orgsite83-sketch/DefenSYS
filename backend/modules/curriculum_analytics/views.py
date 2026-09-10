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


from reports.views import _parse_signature_params
from reports.export_formatters import handle_export_or_preview


class CurriculumProposalPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        academic_year = request.query_params.get('academic_year') or None
        rubric_id = request.query_params.get('rubric_id') or None
        scope = request.query_params.get('scope') or None
        export_format = request.query_params.get('export_format') or request.query_params.get('format') or 'pdf'
        
        include_signatures, signatories = _parse_signature_params(request)
        
        analytics = analytics_payload(request.user, academic_year=academic_year, rubric_id=rubric_id, scope=scope)
        proposal = proposal_payload(request.user, academic_year=academic_year, rubric_id=rubric_id, scope=scope)
        
        user_name = getattr(request.user, 'get_full_name', lambda: '')() or request.user.username
        selected_year = analytics.get('selected_academic_year') or academic_year or 'All Academic Years'
        kpis = analytics.get('kpi_summary') or {}
        total_projects = analytics.get('entries_count', 0)
        competency_index = kpis.get('competency_index', 85)
        pass_rate = kpis.get('first_pass_rate', 80)
        top_domain = kpis.get('top_domain', 'Enterprise & Cloud SaaS')

        summary_kpis = [
            {'label': 'Proficiency Index', 'value': f"{competency_index}%", 'badge': 'MEETS TARGET' if competency_index >= 75 else 'ACTION NEEDED'},
            {'label': 'Pass Rate', 'value': f"{pass_rate}%"},
            {'label': 'Analyzed Projects', 'value': str(total_projects)},
            {'label': 'Leading Domain', 'value': top_domain},
        ]

        metadata = [
            {'label': 'Target Academic Year', 'value': selected_year},
            {'label': 'Total Analyzed Projects', 'value': f"{total_projects} Capstone & PIT Projects"},
            {'label': 'Competency Proficiency Index', 'value': f"{competency_index}% Meeting Benchmark"},
            {'label': 'First-Time Defense Pass Rate', 'value': f"{pass_rate}%"},
            {'label': 'Leading Domain Specialization', 'value': top_domain},
            {'label': 'Report Classification', 'value': 'Official Institutional Decision Support Report'},
        ]

        columns = [
            {'key': 'competency', 'label': 'Competency Dimension', 'align': 'left'},
            {'key': 'avg_score', 'label': 'Avg Score', 'align': 'center'},
            {'key': 'benchmark', 'label': 'Benchmark (75%)', 'align': 'center'},
            {'key': 'prerequisite', 'label': 'Prerequisite Alignment', 'align': 'left'},
            {'key': 'status', 'label': 'Status', 'align': 'center'},
        ]

        rows = []
        for comp in analytics.get('competency_matrix') or []:
            avg_score = comp.get('score', 0)
            rows.append({
                'competency': comp.get('name', 'N/A'),
                'avg_score': f"{avg_score:.1f}%",
                'benchmark': 'Met' if avg_score >= 75 else 'Below Target',
                'prerequisite': comp.get('aligned_course', 'Major Courses'),
                'status': 'PASSED' if avg_score >= 75 else 'REVISION',
            })

        summary_text = proposal.get('summary') or (
            f"This decision support analysis synthesizes {total_projects} capstone and PIT project deliverables, "
            f"multi-criteria defense rubrics, and longitudinal trends across Academic Year {selected_year}. "
            "The objective is to guide evidence-based curriculum adjustments, identify prerequisite course skill gaps, "
            "and optimize defense workflow efficiency."
        )

        competency_rows = []
        for comp in analytics.get('competency_matrix') or []:
            avg_score = comp.get('score', 0)
            competency_rows.append([
                comp.get('name', 'N/A'),
                f"{avg_score:.1f}%",
                'Met' if avg_score >= 75 else 'Below Target',
                comp.get('aligned_course', 'Major Courses'),
                'Proficient' if avg_score >= 75 else 'Action Needed',
            ])

        domain_rows = []
        for dom in (analytics.get('domain_distribution') or [])[:6]:
            domain_rows.append([
                dom.get('domain', 'N/A'),
                f"{dom.get('percentage', 0)}%",
                str(dom.get('count', 0)),
                dom.get('top_stacks', 'General'),
                dom.get('trend_status', 'Stable'),
            ])

        rec_items = []
        for idx, rec in enumerate(proposal.get('recommendations') or [], 1):
            title_text = rec.get('title', f"Recommendation #{idx}") if isinstance(rec, dict) else f"Action Item #{idx}"
            body_text = rec.get('body', str(rec)) if isinstance(rec, dict) else str(rec)
            category_text = rec.get('type_label', 'Curriculum Intervention') if isinstance(rec, dict) else "Curriculum"
            rec_items.append({
                'number': idx,
                'category': category_text,
                'title': title_text,
                'body': body_text,
            })

        sections = [
            {
                'type': 'summary',
                'title': '1. Executive Summary & Problem Context',
                'text': summary_text,
            },
            {
                'type': 'table',
                'title': '2. Core Competency & Rubric Skill Gap Matrix',
                'headers': ['Competency Dimension', 'Avg Score', 'Benchmark (75%)', 'Prerequisite Alignment', 'Status'],
                'rows': competency_rows,
            },
            {
                'type': 'table',
                'title': '3. Project Domain & Technology Distribution',
                'headers': ['Specialization Domain', 'Project Share', 'Count', 'Dominant Stacks / Keywords', 'Trend'],
                'rows': domain_rows,
            },
            {
                'type': 'recommendations',
                'title': '4. Evidence-Based Strategic Recommendations',
                'items': rec_items,
            },
        ]

        track_label = f"_{scope.upper()}" if scope else ""
        filename = f"Curriculum_Proposal_AY_{selected_year}{track_label}"

        def generate_pdf():
            return generate_curriculum_proposal_pdf(
                analytics_data=analytics,
                proposal_data=proposal,
                generated_by_user=user_name,
                signatories=signatories,
                include_signatures=include_signatures,
            )

        return handle_export_or_preview(
            export_format=export_format,
            title='Curriculum Analytics & Decision Support Proposal',
            subtitle=f'Evidence-Based Academic Improvement Report · AY {selected_year}',
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename,
            pdf_generator_func=generate_pdf,
            sections=sections,
            generated_by=user_name,
        )

