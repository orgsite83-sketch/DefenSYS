from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone
from django.db import transaction
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.contrib.auth import get_user_model

from user_management.permissions import IsFacultyRole
from defense.scheduler.serializers import schedule_queryset
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from notifications.models import Notification
from .models import DefenseMinutes, MinutesPanelistComment
from .serializers import DocumenterAssignmentSerializer, DefenseMinutesSerializer
from .pdf_generator import generate_minutes_pdf

User = get_user_model()

class MyDocumenterAssignmentsView(APIView):
    permission_classes = [IsAuthenticated, IsFacultyRole]

    def get(self, request):
        schedules = (
            schedule_queryset()
            .filter(documenter=request.user)
            .select_related('minutes')
        )
        serializer = DocumenterAssignmentSerializer(schedules, many=True)
        return Response(serializer.data)


def has_minutes_view_permission(user, schedule):
    if not user or not user.is_authenticated:
        return False
    if getattr(user, 'role', None) == 'admin' or user.is_superuser:
        return True
    if schedule.documenter == user:
        return True
    if schedule.team and schedule.team.adviser == user:
        return True
    if SchedulePanelist.objects.filter(schedule=schedule, panelist=user).exists():
        return True
    return False


class MinutesDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, schedule_id):
        schedule = get_object_or_404(DefenseSchedule, pk=schedule_id)
        
        if schedule.scope != DefenseSchedule.SCOPE_CAPSTONE:
            return Response(
                {"detail": "Minutes are only available for Capstone defense schedules."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        if not has_minutes_view_permission(request.user, schedule):
            return Response(
                {"detail": "You do not have permission to view the minutes for this defense schedule."},
                status=status.HTTP_403_FORBIDDEN
            )
            
        # Get or create the defense minutes
        minutes = DefenseMinutes.objects.filter(schedule=schedule).first()
        if not minutes:
            if schedule.status == DefenseSchedule.STATUS_CANCELLED:
                return Response(
                    {"detail": "No minutes exist for this cancelled defense schedule."},
                    status=status.HTTP_404_NOT_FOUND
                )
            with transaction.atomic():
                # Re-check inside transaction to avoid race condition
                minutes = DefenseMinutes.objects.filter(schedule=schedule).first()
                if not minutes:
                    team_name = schedule.team.name if schedule.team else ''
                    project_title = schedule.team.project_title if schedule.team else ''
                    adviser_name = schedule.team.adviser.get_full_name() if (schedule.team and schedule.team.adviser) else ''
                    defense_stage_label = schedule.defense_stage.label if schedule.defense_stage else ''
                    documenter_name = schedule.documenter.get_full_name() if schedule.documenter else ''
                    
                    minutes = DefenseMinutes.objects.create(
                        schedule=schedule,
                        team_name=team_name,
                        project_title=project_title,
                        adviser_name=adviser_name,
                        defense_stage_label=defense_stage_label,
                        defense_date=schedule.scheduled_date,
                        defense_time=schedule.start_time,
                        room=schedule.room,
                        documenter_name=documenter_name,
                        status=DefenseMinutes.STATUS_DRAFT,
                    )
                    
                    # Create comments for panelists
                    panelists = list(schedule.panel_assignments.select_related('panelist').all())
                    panelists.sort(key=lambda p: (not p.is_chair, p.order, p.panelist.username))
                    
                    comments_to_create = []
                    member_count = 1
                    for idx, sp in enumerate(panelists):
                        if sp.is_chair:
                            role_label = 'Chair'
                        else:
                            role_label = f'Panel Member {member_count}'
                            member_count += 1
                            
                        comments_to_create.append(MinutesPanelistComment(
                            minutes=minutes,
                            panelist=sp.panelist,
                            panelist_name_snapshot=sp.panelist.get_full_name(),
                            panelist_role_snapshot=role_label,
                            comments='',
                            display_order=idx
                        ))
                    
                    MinutesPanelistComment.objects.bulk_create(comments_to_create)
                    
        # Refresh and serialize
        minutes = DefenseMinutes.objects.prefetch_related('panelist_comments').get(pk=minutes.pk)
        serializer = DefenseMinutesSerializer(minutes)
        return Response(serializer.data)

    def patch(self, request, schedule_id):
        schedule = get_object_or_404(DefenseSchedule, pk=schedule_id)
        
        if schedule.scope != DefenseSchedule.SCOPE_CAPSTONE:
            return Response(
                {"detail": "Minutes are only available for Capstone defense schedules."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        if schedule.status == DefenseSchedule.STATUS_CANCELLED:
            return Response(
                {"detail": "Cannot modify comments for a cancelled defense schedule."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Only the assigned documenter can edit the draft comments
        if schedule.documenter != request.user:
            return Response(
                {"detail": "Only the assigned documenter can edit draft comments."},
                status=status.HTTP_403_FORBIDDEN
            )
            
        minutes = get_object_or_404(DefenseMinutes, schedule=schedule)
        
        if minutes.status != DefenseMinutes.STATUS_DRAFT:
            return Response(
                {"detail": "Cannot modify comments for minutes that are not in Draft status."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        comments_data = request.data
        if isinstance(comments_data, dict):
            comments_data = comments_data.get('comments', [])
            
        if not isinstance(comments_data, list):
            return Response(
                {"detail": "Expected a list of comment updates."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        with transaction.atomic():
            for c_data in comments_data:
                comment_id = c_data.get('id')
                text = c_data.get('comments', '')
                if comment_id is not None:
                    # Update comment that belongs to this minutes
                    MinutesPanelistComment.objects.filter(id=comment_id, minutes=minutes).update(
                        comments=text,
                        updated_at=timezone.now()
                    )
                    
        # Return serialized updated minutes
        minutes = DefenseMinutes.objects.prefetch_related('panelist_comments').get(pk=minutes.pk)
        serializer = DefenseMinutesSerializer(minutes)
        return Response(serializer.data)


class MinutesSubmitView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, schedule_id):
        schedule = get_object_or_404(DefenseSchedule, pk=schedule_id)
        
        if schedule.scope != DefenseSchedule.SCOPE_CAPSTONE:
            return Response(
                {"detail": "Minutes are only available for Capstone defense schedules."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        if schedule.status == DefenseSchedule.STATUS_CANCELLED:
            return Response(
                {"detail": "Cannot submit minutes for a cancelled defense schedule."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Only the assigned documenter can submit
        if schedule.documenter != request.user:
            return Response(
                {"detail": "Only the assigned documenter can submit the minutes."},
                status=status.HTTP_403_FORBIDDEN
            )
            
        minutes = get_object_or_404(DefenseMinutes, schedule=schedule)
        
        if minutes.status != DefenseMinutes.STATUS_DRAFT:
            return Response(
                {"detail": "Only draft minutes can be submitted."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Check e-signature
        if not request.user.e_signature:
            return Response(
                {"error": "Please upload your e-signature first."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Check all comments are non-empty
        comments = minutes.panelist_comments.all()
        for comment in comments:
            if not comment.comments or not comment.comments.strip():
                return Response(
                    {"error": "All panelist comments must be filled before submitting."},
                    status=status.HTTP_400_BAD_REQUEST
                )
                
        with transaction.atomic():
            minutes.status = DefenseMinutes.STATUS_SUBMITTED
            minutes.documenter_signed_at = timezone.now()
            minutes.documenter_signed_by = request.user
            minutes.save()
            
            # Send notification to Adviser
            adviser = schedule.team.adviser if (schedule.team and schedule.team.adviser) else None
            if adviser:
                stage_label = minutes.defense_stage_label or 'defense'
                Notification.objects.create(
                    recipient=adviser,
                    sender=request.user,
                    title="Minutes Ready for Review",
                    message=f"The minutes for {minutes.team_name}'s {stage_label} defense are ready for your review and signature"
                )
                
        serializer = DefenseMinutesSerializer(minutes)
        return Response(serializer.data)


class MinutesSignAdviserView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, schedule_id):
        schedule = get_object_or_404(DefenseSchedule, pk=schedule_id)
        
        if schedule.scope != DefenseSchedule.SCOPE_CAPSTONE:
            return Response(
                {"detail": "Minutes are only available for Capstone defense schedules."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        if schedule.status == DefenseSchedule.STATUS_CANCELLED:
            return Response(
                {"detail": "Cannot sign minutes for a cancelled defense schedule."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Only the team's adviser can sign
        if not schedule.team or schedule.team.adviser != request.user:
            return Response(
                {"detail": "Only the team's adviser can sign these minutes."},
                status=status.HTTP_403_FORBIDDEN
            )
            
        minutes = get_object_or_404(DefenseMinutes, schedule=schedule)
        
        if minutes.status != DefenseMinutes.STATUS_SUBMITTED:
            return Response(
                {"detail": "Minutes are not ready for adviser signature."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Check e-signature
        if not request.user.e_signature:
            return Response(
                {"error": "Please upload your e-signature first."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        with transaction.atomic():
            minutes.status = DefenseMinutes.STATUS_ADVISER_SIGNED
            minutes.adviser_signed_at = timezone.now()
            minutes.adviser_signed_by = request.user
            minutes.save()
            
            # Send notification to Chairman (Admin who created it, or fallback)
            recipient = schedule.created_by
            if not (recipient and getattr(recipient, 'role', None) == 'admin' and recipient.is_active):
                recipient = User.objects.filter(role='admin', is_active=True).first()
                
            if recipient:
                stage_label = minutes.defense_stage_label or 'defense'
                Notification.objects.create(
                    recipient=recipient,
                    sender=request.user,
                    title="Minutes Awaiting Final Signature",
                    message=f"The minutes for {minutes.team_name}'s {stage_label} defense have been reviewed by the adviser and await your signature"
                )
                
        serializer = DefenseMinutesSerializer(minutes)
        return Response(serializer.data)


class MinutesSignChairmanView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, schedule_id):
        # Only administrators can sign as Chairman
        if getattr(request.user, 'role', None) != 'admin' and not request.user.is_superuser:
            return Response(
                {"detail": "Only administrators can sign as Chairman."},
                status=status.HTTP_403_FORBIDDEN
            )
            
        schedule = get_object_or_404(DefenseSchedule, pk=schedule_id)
        
        if schedule.scope != DefenseSchedule.SCOPE_CAPSTONE:
            return Response(
                {"detail": "Minutes are only available for Capstone defense schedules."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        if schedule.status == DefenseSchedule.STATUS_CANCELLED:
            return Response(
                {"detail": "Cannot sign minutes for a cancelled defense schedule."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        minutes = get_object_or_404(DefenseMinutes, schedule=schedule)
        
        if minutes.status != DefenseMinutes.STATUS_ADVISER_SIGNED:
            return Response(
                {"detail": "Minutes are not ready for chairman signature."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Check e-signature
        if not request.user.e_signature:
            return Response(
                {"error": "Please upload your e-signature first."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        with transaction.atomic():
            minutes.status = DefenseMinutes.STATUS_COMPLETED
            minutes.chairman_signed_at = timezone.now()
            minutes.chairman_signed_by = request.user
            
            # Generate the PDF
            from django.core.files.base import ContentFile
            pdf_bytes = generate_minutes_pdf(minutes)
            minutes.pdf_file.save(f"minutes_{minutes.id}.pdf", ContentFile(pdf_bytes), save=False)
            
            minutes.save()
            
            # Send notification to Documenter
            documenter = schedule.documenter
            if documenter:
                stage_label = minutes.defense_stage_label or 'defense'
                Notification.objects.create(
                    recipient=documenter,
                    sender=request.user,
                    title="Minutes Finalized",
                    message=f"The minutes for {minutes.team_name}'s {stage_label} defense have been finalized with all signatures"
                )
                
        serializer = DefenseMinutesSerializer(minutes)
        return Response(serializer.data)


class MinutesPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, schedule_id):
        schedule = get_object_or_404(DefenseSchedule, pk=schedule_id)
        
        if schedule.scope != DefenseSchedule.SCOPE_CAPSTONE:
            return Response(
                {"detail": "Minutes are only available for Capstone defense schedules."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        if not has_minutes_view_permission(request.user, schedule):
            return Response(
                {"detail": "You do not have permission to download the minutes for this defense schedule."},
                status=status.HTTP_403_FORBIDDEN
            )
            
        minutes = get_object_or_404(DefenseMinutes, schedule=schedule)
        
        if minutes.status != DefenseMinutes.STATUS_COMPLETED or not minutes.pdf_file:
            return Response(
                {"detail": "Minutes PDF has not been generated yet."},
                status=status.HTTP_400_BAD_REQUEST
            )
            
        # Return response with file data
        try:
            pdf_data = minutes.pdf_file.read()
            response = HttpResponse(pdf_data, content_type='application/pdf')
            # Format filename safely
            safe_team = (minutes.team_name or 'team').replace(' ', '_')
            safe_stage = (minutes.defense_stage_label or 'defense').replace(' ', '_')
            response['Content-Disposition'] = f'attachment; filename="minutes_{safe_team}_{safe_stage}.pdf"'
            return response
        except Exception as e:
            return Response(
                {"detail": f"Failed to retrieve PDF file: {str(e)}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
