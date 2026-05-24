from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import HttpResponse
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .services import (
    filter_entries,
    override_pit_status,
    repository_audit_payload,
    repository_csv,
    scoped_entries,
    upload_capstone_files,
    upload_pit_files,
)
from .trail import audit_trail_for_request


def _raise_drf_validation_error(exc: DjangoValidationError) -> None:
    if getattr(exc, 'message_dict', None):
        raise ValidationError(detail=exc.message_dict) from exc
    if getattr(exc, 'messages', None):
        raise ValidationError(detail=list(exc.messages)) from exc
    raise ValidationError(detail=str(exc)) from exc


class RepositoryAuditListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(repository_audit_payload(request))


class RepositoryAuditUploadPitView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser, JSONParser)

    def post(self, request):
        uploaded_files = request.FILES.getlist('files')
        if not uploaded_files and request.FILES.get('file'):
            uploaded_files = [request.FILES['file']]

        file_names = request.data.get('file_names') or []
        if isinstance(file_names, str):
            file_names = [line.strip() for line in file_names.splitlines() if line.strip()]
        elif not isinstance(file_names, list):
            file_names = []

        if not uploaded_files and not file_names:
            raise ValidationError(
                {'files': 'Upload at least one PIT PDF file or provide file_names.'}
            )

        try:
            entries, skipped = upload_pit_files(
                request.user,
                file_names=file_names if file_names else None,
                uploaded_files=uploaded_files if uploaded_files else None,
                year_level=request.data.get('year_level') or None,
                academic_year=request.data.get('academic_year') or None,
            )
        except DjangoValidationError as exc:
            _raise_drf_validation_error(exc)
        payload = repository_audit_payload(request)
        payload['created_count'] = len(entries)
        payload['skipped'] = skipped
        return Response(payload)


class RepositoryAuditUploadCapstoneView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser, JSONParser)

    def post(self, request):
        uploaded_files = request.FILES.getlist('files')
        if not uploaded_files and request.FILES.get('file'):
            uploaded_files = [request.FILES['file']]

        file_names = request.data.get('file_names') or []
        if isinstance(file_names, str):
            file_names = [line.strip() for line in file_names.splitlines() if line.strip()]
        elif not isinstance(file_names, list):
            file_names = []

        if not uploaded_files and not file_names:
            raise ValidationError(
                {'files': 'Upload at least one Capstone PDF file or provide file_names.'}
            )

        try:
            entries, skipped = upload_capstone_files(
                request.user,
                file_names=file_names if file_names else None,
                uploaded_files=uploaded_files if uploaded_files else None,
                academic_year=request.data.get('academic_year') or None,
            )
        except DjangoValidationError as exc:
            _raise_drf_validation_error(exc)
        payload = repository_audit_payload(request)
        payload['created_count'] = len(entries)
        payload['skipped'] = skipped
        return Response(payload)


class RepositoryAuditOverrideStatusView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        entry_id = request.data.get('entry_id')
        status = request.data.get('status')
        if not entry_id:
            raise ValidationError({'entry_id': 'PIT entry id is required.'})
        if not status:
            raise ValidationError({'status': 'Status is required.'})
        override_pit_status(request.user, entry_id, status)
        return Response(repository_audit_payload(request))


class RepositoryAuditTrailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({'audit_trail': audit_trail_for_request(request)})


class RepositoryAuditExportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        entries, _scope = scoped_entries(request.user, request=request)
        filtered = filter_entries(entries, request.query_params)
        response = HttpResponse(repository_csv(filtered), content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="repository_audit.csv"'
        return response
