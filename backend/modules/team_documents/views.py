from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated

from student_teams.models import StudentTeam
from .models import TeamDocument
from .serializers import TeamDocumentSerializer, TeamDocumentUploadSerializer


def team_document_queryset_for_user(user, team_id=None):
    qs = TeamDocument.objects.select_related('team', 'uploaded_by').order_by('-uploaded_at')
    if not user or not user.is_authenticated:
        return qs.none()

    if user.is_superuser or getattr(user, 'role', None) == 'admin':
        if team_id is not None:
            return qs.filter(team_id=team_id)
        return qs

    if getattr(user, 'is_pit_lead', False) or getattr(user, 'is_uploader', False):
        if team_id is not None:
            return qs.filter(team_id=team_id)
        return qs

    accessible = StudentTeam.objects.filter(
        Q(leader=user) | Q(memberships__student=user) | Q(adviser=user)
    ).distinct()
    if team_id is not None:
        if not accessible.filter(pk=team_id).exists():
            return qs.none()
        return qs.filter(team_id=team_id)
    return qs.filter(team_id__in=accessible.values_list('id', flat=True))


def user_can_access_team_document(user, document):
    if not user or not user.is_authenticated:
        return False
    if user.is_superuser or getattr(user, 'role', None) == 'admin':
        return True
    if getattr(user, 'is_pit_lead', False) or getattr(user, 'is_uploader', False):
        return True
    team = document.team
    if team.leader_id == user.id:
        return True
    if team.adviser_id == user.id:
        return True
    return team.memberships.filter(student_id=user.id).exists()


class TeamDocumentListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """List documents visible to the user (optionally filter by team_id)."""
        raw_team_id = request.query_params.get('team_id')
        team_id = None
        if raw_team_id is not None and str(raw_team_id).strip() != '':
            try:
                team_id = int(raw_team_id)
            except (TypeError, ValueError):
                return Response(
                    {'detail': 'Invalid team_id.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        documents = team_document_queryset_for_user(request.user, team_id=team_id)

        return Response({
            'documents': TeamDocumentSerializer(documents, many=True).data,
            'count': documents.count(),
        })


class TeamDocumentUploadView(APIView):
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        """Upload a new document"""
        serializer = TeamDocumentUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        team_id = serializer.validated_data['team_id']
        document_type = serializer.validated_data['document_type']
        description = serializer.validated_data.get('description', '')
        uploaded_file = serializer.validated_data['file']
        
        # Verify team exists
        team = get_object_or_404(StudentTeam, pk=team_id)
        
        # Read file data for backward compatibility (optional)
        file_data = uploaded_file.read()
        uploaded_file.seek(0)  # Reset file pointer for FileField
        
        # Create document record with both file and file_data
        document = TeamDocument.objects.create(
            team=team,
            uploaded_by=request.user,
            document_type=document_type,
            file=uploaded_file,  # Save actual file
            file_name=uploaded_file.name,
            file_data=file_data,  # Keep for backward compatibility
            file_size=uploaded_file.size,
            mime_type=uploaded_file.content_type or 'application/octet-stream',
            description=description,
        )
        
        return Response({
            'message': 'Document uploaded successfully',
            'document': TeamDocumentSerializer(document).data,
        }, status=status.HTTP_201_CREATED)


class TeamDocumentDetailView(APIView):
    permission_classes = [IsAuthenticated]
    
    def get(self, request, document_id):
        """Get document details"""
        document = get_object_or_404(TeamDocument, pk=document_id)
        if not user_can_access_team_document(request.user, document):
            return Response(
                {'detail': 'You do not have permission to view this document.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response(TeamDocumentSerializer(document).data)
    
    def delete(self, request, document_id):
        """Delete a document"""
        document = get_object_or_404(TeamDocument, pk=document_id)
        if not user_can_access_team_document(request.user, document):
            return Response(
                {'detail': 'You do not have permission to delete this document.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        is_admin = getattr(request.user, 'role', None) == 'admin' or request.user.is_superuser
        if request.user.id != document.uploaded_by_id and not is_admin:
            return Response(
                {'detail': 'You do not have permission to delete this document.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        document.delete()
        return Response({'message': 'Document deleted successfully'})


class TeamDocumentDownloadView(APIView):
    permission_classes = [IsAuthenticated]
    
    def get(self, request, document_id):
        """Download a document"""
        document = get_object_or_404(TeamDocument, pk=document_id)
        if not user_can_access_team_document(request.user, document):
            return Response(
                {'detail': 'You do not have permission to download this document.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        
        # Use file field if available, otherwise fall back to file_data
        if document.file:
            response = HttpResponse(document.file.read(), content_type=document.mime_type)
        else:
            response = HttpResponse(document.file_data, content_type=document.mime_type)
        
        response['Content-Disposition'] = f'attachment; filename="{document.file_name}"'
        response['Content-Length'] = document.file_size
        
        return response
