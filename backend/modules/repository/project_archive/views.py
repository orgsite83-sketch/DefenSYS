from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import HttpResponse
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from repository.archive.models import ArchiveEntry
from .folders import entries_in_folder
from .services import (
    augment_deliverable_missing_rows,
    cancel_archive_file_replacement,
    filter_entries,
    override_pit_status,
    replace_archive_file,
    request_archive_resubmission,
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


class ProjectArchiveListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(repository_audit_payload(request))


class ProjectArchiveUploadPitView(APIView):
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


class ProjectArchiveUploadCapstoneView(APIView):
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


class ProjectArchiveRequestResubmissionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        entry_id = request.data.get('entry_id')
        status = request.data.get('status') or 'Needs Revision'
        feedback = request.data.get('feedback', '')
        if not entry_id:
            raise ValidationError({'entry_id': 'Archive entry id is required.'})
        try:
            request_archive_resubmission(request.user, entry_id, status, feedback=feedback, request=request)
        except DjangoValidationError as exc:
            _raise_drf_validation_error(exc)
        return Response(repository_audit_payload(request))


class ProjectArchiveCancelReplacementView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        entry_id = request.data.get('entry_id')
        if not entry_id:
            raise ValidationError({'entry_id': 'Archive entry id is required.'})
        try:
            cancel_archive_file_replacement(request.user, entry_id, request.data.get('reason', ''), request=request)
        except DjangoValidationError as exc:
            _raise_drf_validation_error(exc)
        return Response(repository_audit_payload(request))


class ProjectArchiveOverrideStatusView(ProjectArchiveRequestResubmissionView):
    pass


class ProjectArchiveReplaceFileView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser, JSONParser)

    def post(self, request):
        entry_id = request.data.get('entry_id')
        uploaded_file = request.FILES.get('file')
        if not entry_id:
            raise ValidationError({'entry_id': 'Archive entry id is required.'})
        if not uploaded_file:
            raise ValidationError({'file': 'Replacement PDF file is required.'})

        try:
            replace_archive_file(request.user, entry_id, uploaded_file)
        except DjangoValidationError as exc:
            _raise_drf_validation_error(exc)

        return Response(repository_audit_payload(request))


class ProjectArchiveTrailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({'audit_trail': audit_trail_for_request(request)})


class ProjectArchiveExportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        entries, scope = scoped_entries(request.user, request=request)
        query_params = request.query_params.copy()
        if scope.get('scope') != 'admin':
            query_params['type'] = ArchiveEntry.TYPE_PIT
        deliverable_id = (query_params.get('deliverable_id') or '').strip()
        stage_filter = (query_params.get('stage') or '').strip()
        group_by = query_params.get('group_by') or 'team'
        if (deliverable_id or group_by == 'deliverable') and scope.get('scope') in ('admin', 'pit_lead'):
            entries = augment_deliverable_missing_rows(
                entries, deliverable_id, stage_filter, scope=scope,
            )
        filtered = filter_entries(entries, query_params)
        filtered = entries_in_folder(filtered, group_by, query_params.get('folder_key') or '')
        response = HttpResponse(repository_csv(filtered), content_type='text/csv; charset=utf-8')
        response['Content-Disposition'] = 'attachment; filename="project_archive_records.csv"'
        return response
