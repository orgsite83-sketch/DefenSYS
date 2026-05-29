from django.urls import path
from . import views

urlpatterns = [
    path('team-grade/<int:team_id>/', views.TeamGradeReportView.as_view(), name='report_team_grade'),
    path('semester-grades/', views.SemesterGradesReportView.as_view(), name='report_semester_grades'),
    path('defense-schedules/', views.DefenseScheduleReportView.as_view(), name='report_defense_schedules'),
    path('team-roster/', views.TeamRosterReportView.as_view(), name='report_team_roster'),
    path('user-directory/', views.UserDirectoryReportView.as_view(), name='report_user_directory'),
    path('audit-trail/', views.AuditTrailReportView.as_view(), name='report_audit_trail'),
]
