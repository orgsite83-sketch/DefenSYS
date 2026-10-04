from django.urls import path

from .views import DefenseBoardDetailView, DefenseBoardListView, DefenseBoardOperationsView


urlpatterns = [
    path('', DefenseBoardListView.as_view(), name='defense_board'),
    path('operations/', DefenseBoardOperationsView.as_view(), name='defense_board_operations'),
    path('<int:schedule_id>/', DefenseBoardDetailView.as_view(), name='defense_board_detail'),
]
