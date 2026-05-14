from django.urls import path

from .views import (
    RolloverConfirmView,
    RolloverPreviewView,
    StudentAcademicRecordDetailView,
    StudentAcademicRecordListCreateView,
)


urlpatterns = [
    path('', StudentAcademicRecordListCreateView.as_view(), name='student_academic_records'),
    path('rollover-preview/', RolloverPreviewView.as_view(), name='student_academic_records_rollover_preview'),
    path('rollover/', RolloverConfirmView.as_view(), name='student_academic_records_rollover'),
    path('<int:record_id>/', StudentAcademicRecordDetailView.as_view(), name='student_academic_record_detail'),
]
