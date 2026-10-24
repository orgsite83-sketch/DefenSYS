from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from defensys_backend.read_projection import ReadAPIView
from .formation_access import CanFormTeams
from . import roster_workspace as service


class RosterWorkspaceView(ReadAPIView):
    permission_classes = [CanFormTeams]

    def get(self, request):
        return Response(service.context(request.user, request.query_params))


class RosterPreviewView(APIView):
    permission_classes = [CanFormTeams]

    def post(self, request):
        return Response(service.prepare(request.user, request.data))


class RosterApplyView(APIView):
    permission_classes = [CanFormTeams]

    def post(self, request):
        return Response(service.apply(request, request.data.get('preview_token')), status=201)


class RosterProjectSetupView(APIView):
    permission_classes = [CanFormTeams]

    def post(self, request):
        return Response(service.open_setup(request, request.data))

    def patch(self, request):
        return Response(service.correct_details(request, request.data))


class EventTeamSetupView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, team_id, event_id):
        return Response(service.confirm_setup(request, team_id, event_id, request.data))


class RosterExportView(ReadAPIView):
    permission_classes = [CanFormTeams]

    def get(self, request):
        return Response(service.export_roster(request.user, request.query_params))
