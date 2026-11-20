from django.urls import path
from .views import ReDemoListView, ReDemoDetailView, ReDemoVerifyView, ReDemoOperationView

urlpatterns = [
    path('', ReDemoListView.as_view()),
    path('<int:appointment_id>/', ReDemoDetailView.as_view()),
    path('<int:appointment_id>/verify/', ReDemoVerifyView.as_view()),
    path('<int:appointment_id>/operate/', ReDemoOperationView.as_view()),
]
