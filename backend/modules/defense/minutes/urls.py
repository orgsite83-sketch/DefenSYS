from django.urls import path
from .views import (
    MyDocumenterAssignmentsView,
    MinutesDetailView,
    MinutesSubmitView,
    MinutesSignAdviserView,
    MinutesSignChairmanView,
    MinutesPdfView,
)

urlpatterns = [
    path('my-assignments/', MyDocumenterAssignmentsView.as_view(), name='my_documenter_assignments'),
    path('<int:schedule_id>/', MinutesDetailView.as_view(), name='minutes_detail'),
    path('<int:schedule_id>/submit/', MinutesSubmitView.as_view(), name='minutes_submit'),
    path('<int:schedule_id>/sign-adviser/', MinutesSignAdviserView.as_view(), name='minutes_sign_adviser'),
    path('<int:schedule_id>/sign-chairman/', MinutesSignChairmanView.as_view(), name='minutes_sign_chairman'),
    path('<int:schedule_id>/pdf/', MinutesPdfView.as_view(), name='minutes_pdf'),
]
