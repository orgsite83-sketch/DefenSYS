from django.urls import include, path

from .views import (
    BulkImportUsersView,
    GuestCodeExchangeView,
    GuestCodeValidateView,
    GuestPanelistCodeDetailView,
    GuestPanelistCodeListCreateView,
    UserAdviserAssignmentHistoryView,
    UserDetailView,
    UserListCreateView,
    UserRoleAssignmentHistoryView,
)


urlpatterns = [
    path('academic-records/', include('user_management.academic_records.urls')),
    path('', UserListCreateView.as_view(), name='users'),
    path('bulk-import/', BulkImportUsersView.as_view(), name='users_bulk_import'),
    path('guest-codes/', GuestPanelistCodeListCreateView.as_view(), name='guest_codes'),
    path('guest-codes/<int:code_id>/', GuestPanelistCodeDetailView.as_view(), name='guest_code_detail'),
    path('guest-codes/exchange/', GuestCodeExchangeView.as_view(), name='guest_code_exchange'),
    path('guest-codes/validate/<str:code>/', GuestCodeValidateView.as_view(), name='guest_code_validate'),
    path(
        '<int:user_id>/adviser-assignments/',
        UserAdviserAssignmentHistoryView.as_view(),
        name='user_adviser_assignments',
    ),
    path(
        '<int:user_id>/role-assignments/',
        UserRoleAssignmentHistoryView.as_view(),
        name='user_role_assignments',
    ),
    path('<int:user_id>/', UserDetailView.as_view(), name='user_detail'),
]
