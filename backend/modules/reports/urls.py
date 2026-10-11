from django.urls import path
from . import views
from .catalog_reports import BUILDERS, CatalogReportView, CatalogOptionsView

urlpatterns = [
    path('catalog-options/', CatalogOptionsView.as_view(), name='report_catalog_options'),
    *[path(f'{kind}/', CatalogReportView.as_view(), {'report_kind': kind}, name=f'report_{kind.replace("-", "_")}') for kind in BUILDERS],
    path('rubrics/<int:rubric_id>/', CatalogReportView.as_view(), {'report_kind': 'rubrics'}, name='report_rubric_details'),
    path('assessment-candidates/', views.AssessmentCandidatesView.as_view(), name='report_assessment_candidates'),
    path('team-grade/<int:team_id>/', views.TeamGradeReportView.as_view(), name='report_team_grade'),
    path('individual-grade/<int:student_id>/', views.IndividualGradeReportView.as_view(), name='report_individual_grade'),
    path('semester-grades/', views.SemesterGradesReportView.as_view(), name='report_semester_grades'),
    path('defense-schedules/', views.DefenseScheduleReportView.as_view(), name='report_defense_schedules'),
    path('team-roster/', views.TeamRosterReportView.as_view(), name='report_team_roster'),
    path('user-directory/', views.UserDirectoryReportView.as_view(), name='report_user_directory'),
    path('audit-trail/', views.AuditTrailReportView.as_view(), name='report_audit_trail'),
]
