from django.urls import path

from .views import DefenseBoardDetailView, DefenseBoardListView


urlpatterns = [
    path('', DefenseBoardListView.as_view(), name='defense_board'),
    path('<int:schedule_id>/', DefenseBoardDetailView.as_view(), name='defense_board_detail'),
]
