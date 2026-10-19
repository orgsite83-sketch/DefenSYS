from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.authentication import SessionAuthentication
from rest_framework_simplejwt.authentication import JWTAuthentication
from authentication_access_control.guest_authentication import GuestJWTAuthentication
from defensys_backend.read_projection import ReadAPIView

from .models import SectionConceptProject, SectionConceptPaper
from . import services


class SetupSerializer(serializers.Serializer):
    team_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), min_length=1, max_length=100)
    stage_label = serializers.CharField(max_length=120)
    project_manager_id = serializers.IntegerField(min_value=1)
    reviewer_id = serializers.IntegerField(min_value=1, required=False)
    title_mode = serializers.ChoiceField(choices=['student_proposed', 'faculty_provided'], default='student_proposed')


class ActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['save_titles', 'review', 'endorse', 'confirm_modules',
        'schedule_hearing', 'decide', 'module_verdict', 'reassign', 'clear_revisions', 'acknowledge'])
    round_id = serializers.IntegerField(min_value=1)
    review_token = serializers.CharField(required=False, max_length=64)
    concepts = serializers.ListField(child=serializers.DictField(), required=False, max_length=3)
    paper_id = serializers.IntegerField(min_value=1, required=False)
    team_id = serializers.IntegerField(min_value=1, required=False)
    status = serializers.ChoiceField(choices=['accepted', 'rejected'], required=False)
    remarks = serializers.CharField(max_length=5000, allow_blank=True, default='')
    verdict = serializers.ChoiceField(choices=['approved', 'approved_with_revisions', 'for_redefense',
        'failed', 'project_rejected'], required=False)
    schedule_ids = serializers.ListField(child=serializers.IntegerField(min_value=1), required=False, max_length=100)
    project_manager_id = serializers.IntegerField(min_value=1, required=False)
    reviewer_id = serializers.IntegerField(min_value=1, required=False)
    revision_deadline = serializers.DateField(required=False, allow_null=True)


class SectionAPIView(ReadAPIView):
    permission_classes = [IsAuthenticated]
    authentication_classes = [GuestJWTAuthentication, JWTAuthentication, SessionAuthentication]

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if getattr(request.user, 'is_guest_panelist', False) and request.method not in ('GET', 'HEAD', 'OPTIONS'):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Guest panelists may read shared concepts; the faculty chair records official decisions.')

    def handle_exception(self, exc):
        if isinstance(exc, (DjangoValidationError, ValueError)):
            exc = serializers.ValidationError(getattr(exc, 'messages', str(exc)))
        if isinstance(exc, PermissionError):
            from rest_framework.exceptions import PermissionDenied
            exc = PermissionDenied(str(exc))
        return super().handle_exception(exc)

    def project(self, request, project_id, *, lock=False):
        query = SectionConceptProject.objects.select_related('section__semester', 'project_manager',
            'reviewer', 'pit_event_config', 'defense_stage')
        if lock:
            query = query.select_for_update(of=('self',))
        project = get_object_or_404(query, pk=project_id)
        if not services.can_read(request.user, project):
            raise Http404()
        return project


class SectionProjectListView(SectionAPIView):
    def get(self, request):
        if request.query_params.get('tasks_only') == '1':
            return Response({'tasks': services.task_payload(request.user)})
        team_id = None
        if request.query_params.get('team_id'):
            team_id = serializers.IntegerField(min_value=1).run_validation(request.query_params['team_id'])
        projects = services.visible_projects(request.user, team_id=team_id)
        return Response({'projects': [services.payload(p, request.user) for p in projects],
                         'tasks': services.task_payload(request.user)})

    @transaction.atomic
    def post(self, request):
        serializer = SetupSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        from authentication_access_control.scopes import visible_teams_for
        from repository.deliverables.concepts import stage_for
        teams = list(visible_teams_for(request.user).filter(pk__in=data['team_ids']).order_by('pk'))
        if len(teams) != len(data['team_ids']) or not teams:
            raise serializers.ValidationError('Select each authorized team once.')
        project = services.configure(request.user, teams, stage_for(teams[0], data['stage_label']), data)
        return Response(services.payload(project, request.user), status=status.HTTP_201_CREATED)


class SectionProjectDetailView(SectionAPIView):
    def get(self, request, project_id):
        return Response(services.payload(self.project(request, project_id), request.user))

    @transaction.atomic
    def post(self, request, project_id):
        project = self.project(request, project_id, lock=True)
        serializer = ActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        round = services.latest(project)
        if d['round_id'] != round.pk:
            return Response({'detail': 'The section proposal round changed. Refresh before submitting.'}, status=409)
        if d['action'] in ('review', 'endorse', 'decide', 'save_titles', 'clear_revisions', 'acknowledge') and d.get('review_token') != services.review_token(round):
            return Response({'detail': 'The section names or papers changed. Refresh and review the current versions.'}, status=409)
        action, actor = d['action'], request.user
        if action == 'save_titles':
            services.save_system_titles(project, actor, d.get('concepts'))
        elif action == 'review':
            services.review(project, actor, d.get('paper_id'), d.get('status'), d['remarks'])
        elif action == 'endorse':
            services.endorse(project, actor)
        elif action == 'acknowledge':
            from .acknowledgments import acknowledge
            acknowledge(project, actor)
        elif action == 'confirm_modules':
            services.confirm_modules(project, actor, d.get('team_id'), d.get('concepts'))
        elif action == 'schedule_hearing':
            services.schedule_hearing(project, actor, d.get('schedule_ids'))
        elif action == 'decide':
            services.decide(project, actor, d.get('concepts'), d.get('verdict'), d['remarks'])
        elif action == 'reassign':
            services.reassign(project, actor, d.get('project_manager_id'), d.get('reviewer_id'))
        elif action == 'clear_revisions':
            services.clear_revisions(project, actor, d['remarks'])
        elif action == 'module_verdict':
            services.require_active(project)
            if not round.selected_key:
                raise serializers.ValidationError('Select the shared system before recording module outcomes.')
            link = services.active_links(project).filter(team_id=d.get('team_id')).first()
            if not link:
                raise serializers.ValidationError('Choose a participating team from this section.')
            from repository.deliverables.concepts import latest_round
            from grading.grades.defense_workflow import record_verdict
            current = latest_round(link.team, project.context)
            if not current or current.section_round_id != round.pk or not current.schedule_id:
                raise serializers.ValidationError('Schedule this team’s current module set first.')
            verdict = d.get('verdict')
            decision = verdict if verdict in ('approved', 'approved_with_revisions') else 'revise'
            grade = current.schedule.grade_records.first()
            if not grade:
                from grading.grades.services import GradeContextService
                grade, _, _ = GradeContextService.get_or_create_for_schedule(current.schedule)
            record_verdict(grade, actor=actor, verdict=verdict, remarks=d['remarks'],
                deadline=d.get('revision_deadline'), verification_required=verdict == 'for_redefense',
                concept_decisions=[{'key': k, 'decision': decision if k == round.selected_key else 'not_selected',
                                   'remarks': d['remarks'] if k == round.selected_key else ''} for k in services.KEYS])
        return Response(services.payload(project, actor))


class SectionPaperUploadView(SectionAPIView):
    @transaction.atomic
    def post(self, request, project_id):
        project = self.project(request, project_id, lock=True)
        round_id = serializers.IntegerField(min_value=1).run_validation(request.data.get('round_id'))
        if services.latest(project).pk != round_id:
            return Response({'detail': 'The section round changed. Refresh before uploading.'}, status=409)
        services.upload(project, request.user, request.data.get('key'), request.FILES.get('file'))
        return Response(services.payload(project, request.user), status=status.HTTP_201_CREATED)


class SectionPaperFileView(SectionAPIView):
    def get(self, request, project_id, paper_id):
        project = self.project(request, project_id)
        row = get_object_or_404(SectionConceptPaper, pk=paper_id, concept__round__project=project)
        if not row.file or not row.file.storage.exists(row.file.name):
            raise Http404()
        response = FileResponse(row.file.open('rb'), content_type='application/pdf', filename=row.file_name)
        response['Cache-Control'] = 'private, no-store'
        response['Vary'] = 'Authorization'
        response['X-Content-Type-Options'] = 'nosniff'
        return response
