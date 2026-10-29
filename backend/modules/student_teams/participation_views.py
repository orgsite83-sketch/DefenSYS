"""Admin history and explicit regular-intake roster reuse; no recovery actions."""
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from defensys_backend.read_projection import ReadAPIView
from user_management.permissions import IsSystemAdmin
from user_management.academic_records.models import StudentAcademicRecord
from academic_period_management.services import active_semester
from academic_period_management.models import Semester
from .models import StudentTeam
from .serializers import StudentTeamWriteSerializer, StudentTeamSerializer
from .participation import student_history, closed_failure, roster_ids


class StudentParticipationHistoryView(ReadAPIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, student_id):
        from django.contrib.auth import get_user_model
        student = get_object_or_404(get_user_model(), pk=student_id, role='student')
        return Response({'student_id': student.pk, 'student_name': student.get_full_name() or student.username,
            'participations': student_history(student.pk)})


class ReuseCapstoneRosterView(ReadAPIView):
    permission_classes = [IsSystemAdmin]

    @transaction.atomic
    def post(self, request, team_id):
        list(Semester.objects.select_for_update().order_by('pk'))
        source = get_object_or_404(StudentTeam.objects.select_for_update(), pk=team_id, level__icontains='Capstone')
        term = active_semester()
        if not term or term.label != Semester.SECOND or source.semester_id == term.pk or not closed_failure(source):
            raise ValidationError('A finalized Failed roster can be reused only in a later regular Capstone 1 intake.')
        existing = StudentTeam.objects.filter(previous_team=source, semester=term).first()
        if existing:
            return Response({'team': StudentTeamSerializer(existing, context={'user': request.user}).data})
        members = roster_ids(source)
        year = StudentAcademicRecord.objects.filter(student_id=source.leader_id, semester=term).values_list('year_level', flat=True).first() or source.year_level
        level = StudentTeam.LEVEL_4_CAPSTONE if year == '4th Year' else StudentTeam.LEVEL_3_CAPSTONE
        data = {'name': source.name, 'project_title': source.project_title, 'leader_id': source.leader_id,
            'member_ids': sorted(members), 'year_level': year, 'level': level, 'section': source.section,
            'setup_pending': True, 'project_pending': True, 'adviser_id': source.adviser_id}
        serializer = StudentTeamWriteSerializer(data=data, context={'user': request.user, 'assigned_by': request.user})
        serializer.is_valid(raise_exception=True)
        team = serializer.save(setup_pending=True, project_pending=True)
        team.previous_team = source
        team.save(update_fields=['previous_team', 'updated_at'])
        return Response({'team': StudentTeamSerializer(team, context={'user': request.user}).data}, status=201)
