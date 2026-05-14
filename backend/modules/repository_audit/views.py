from django.http import HttpResponse
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from defensys_backend.prototype_tools import require_prototype_tools
from .services import (
    classify_pit_entry,
    demo_fill_capstone,
    demo_fill_pit,
    filter_entries,
    repository_audit_payload,
    repository_csv,
    scoped_entries,
    upload_pit_files,
    override_pit_status,
)


class RepositoryAuditListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(repository_audit_payload(request))


class RepositoryAuditUploadPitView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        file_names = request.data.get('file_names') or []
        if isinstance(file_names, str):
            file_names = [line.strip() for line in file_names.splitlines() if line.strip()]
        if not isinstance(file_names, list) or not file_names:
            raise ValidationError({'file_names': 'Provide at least one PIT PDF filename.'})

        entries, skipped = upload_pit_files(
            request.user,
            file_names,
            year_level=request.data.get('year_level') or None,
            academic_year=request.data.get('academic_year') or None,
        )
        payload = repository_audit_payload(request)
        payload['created_count'] = len(entries)
        payload['skipped'] = skipped
        return Response(payload)


class RepositoryAuditClassifyView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        entry_id = request.data.get('entry_id')
        if not entry_id:
            raise ValidationError({'entry_id': 'PIT entry id is required.'})
        classify_pit_entry(request.user, entry_id)
        return Response(repository_audit_payload(request))


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


class RepositoryAuditDemoFillView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        require_prototype_tools()
        fill_type = request.data.get('type', 'pit')
        if fill_type == 'pit':
            entries, skipped = demo_fill_pit(
                request.user,
                request.data.get('year_level') or '3rd Year',
                academic_year=request.data.get('academic_year') or None,
            )
            payload = repository_audit_payload(request)
            payload['created_count'] = len(entries)
            payload['skipped'] = skipped
            return Response(payload)
        if fill_type == 'capstone':
            created = demo_fill_capstone(
                request.user,
                request.data.get('stage_label') or 'Concept Proposal',
                fill_pre=request.data.get('fill_pre', True) is not False,
                fill_vault=request.data.get('fill_vault', False) is True,
                endorse=request.data.get('endorse', False) is True,
            )
            payload = repository_audit_payload(request)
            payload['created_count'] = created
            return Response(payload)
        raise ValidationError({'type': 'Use pit or capstone.'})


class RepositoryAuditExportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        entries, _scope = scoped_entries(request.user)
        filtered = filter_entries(entries, request.query_params)
        response = HttpResponse(repository_csv(filtered), content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="repository_audit.csv"'
        return response
