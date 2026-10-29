"""Read-only admin participation history. Intake placement belongs to team imports."""
from django.shortcuts import get_object_or_404
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView
from user_management.permissions import IsSystemAdmin
from .participation import student_history


class StudentParticipationHistoryView(ReadAPIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, student_id):
        from django.contrib.auth import get_user_model
        student = get_object_or_404(get_user_model(), pk=student_id, role='student')
        return Response({'student_id': student.pk, 'student_name': student.get_full_name() or student.username,
            'participations': student_history(student.pk)})
