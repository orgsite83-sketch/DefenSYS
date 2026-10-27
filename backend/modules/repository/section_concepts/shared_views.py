import mimetypes

from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from rest_framework import serializers, status
from rest_framework.response import Response

from .views import SectionAPIView
from .models import SharedDeliverableFile
from . import shared_deliverables as shared


class SharedDeliverablesView(SectionAPIView):
    def target(self, request, values):
        from repository.deliverables.views import get_allowed_team
        from repository.deliverables.concepts import stage_for
        team_id = serializers.IntegerField(min_value=1).run_validation(values.get('team_id'))
        team = get_allowed_team(request, team_id)
        label = serializers.CharField(max_length=120).run_validation(values.get('stage_label'))
        context = stage_for(team, label)
        if not context:
            raise serializers.ValidationError('Choose an available stage or event for this team.')
        return team, context

    def get(self, request):
        from repository.deliverables.views import get_allowed_team
        team_id = serializers.IntegerField(min_value=1).run_validation(request.query_params.get('team_id'))
        team = get_allowed_team(request, team_id)
        if request.query_params.get('stage_label'):
            team, context = self.target(request, request.query_params)
            profile = shared.resolve(team, context)
            return Response({'shared_deliverables': shared.payload(profile, request.user) if profile else None})
        return Response({'groups': shared.groups_for_team(team, request.user)})

    def post(self, request):
        team, context = self.target(request, request.data)
        token = serializers.CharField(max_length=64).run_validation(request.data.get('review_token'))
        number = serializers.CharField(max_length=40).run_validation(request.data.get('deliverable_id'))
        slot = serializers.CharField(max_length=90, allow_blank=True).run_validation(request.data.get('slot_key', ''))
        action = serializers.ChoiceField(choices=['upload', 'review']).run_validation(request.data.get('action', 'upload'))
        if action == 'review':
            file_id = serializers.IntegerField(min_value=1).run_validation(request.data.get('file_id'))
            legacy = serializers.BooleanField().run_validation(request.data.get('legacy', False))
            state = shared.review(team, context, request.user, number, slot, file_id, legacy,
                request.data.get('status'), request.data.get('feedback', ''), token,
                revision_scope=serializers.ChoiceField(choices=['paper', 'title_and_paper']).run_validation(request.data.get('revision_scope', 'paper')))
        else:
            state = shared.upload(team, context, request.user, number, slot, request.FILES.get('file'), token)
        return Response({'shared_deliverables': state}, status=status.HTTP_200_OK)


class SharedDeliverableFileView(SectionAPIView):
    def get(self, request, file_id):
        row = get_object_or_404(SharedDeliverableFile.objects.select_related(
            'submission_set__section__semester', 'submission_set__defense_stage',
            'submission_set__pit_event_config'), pk=file_id)
        if not shared.can_read_file(request.user, row) or not row.file or not row.file.storage.exists(row.file.name):
            raise Http404()
        response = FileResponse(row.file.open('rb'), filename=row.file_name,
            content_type=mimetypes.guess_type(row.file_name)[0] or 'application/octet-stream', as_attachment=True)
        response['Cache-Control'] = 'private, no-store'
        response['Vary'] = 'Authorization'
        response['X-Content-Type-Options'] = 'nosniff'
        return response
