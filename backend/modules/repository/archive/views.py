from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import project_archive_payload, search_archive_payload


class ProjectArchiveListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(project_archive_payload(request))


class ProjectArchiveSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(search_archive_payload(request))
