from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import digital_vault_payload, search_vault_payload


class DigitalVaultListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(digital_vault_payload(request))


class DigitalVaultSearchView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(search_vault_payload(request))
