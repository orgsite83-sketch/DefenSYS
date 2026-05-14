from django.urls import path
from .views import AdminDashboardView, FacultyDashboardView, StudentDashboardView, PanelistDashboardView

urlpatterns = [
    path('admin/', AdminDashboardView.as_view(), name='dashboard_admin'),
    path('faculty/', FacultyDashboardView.as_view(), name='dashboard_faculty'),
    path('student/', StudentDashboardView.as_view(), name='dashboard_student'),
    path('panelist/', PanelistDashboardView.as_view(), name='dashboard_panelist'),
]
