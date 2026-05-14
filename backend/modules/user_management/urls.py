from django.urls import path

from .views import (
    BulkImportUsersView,
    GuestCodeValidateView,
    GuestPanelistCodeDetailView,
    GuestPanelistCodeListCreateView,
    UserDetailView,
    UserListCreateView,
)


urlpatterns = [
    path('', UserListCreateView.as_view(), name='users'),
    path('bulk-import/', BulkImportUsersView.as_view(), name='users_bulk_import'),
    path('guest-codes/', GuestPanelistCodeListCreateView.as_view(), name='guest_codes'),
    path('guest-codes/<int:code_id>/', GuestPanelistCodeDetailView.as_view(), name='guest_code_detail'),
    path('guest-codes/validate/<str:code>/', GuestCodeValidateView.as_view(), name='guest_code_validate'),
    path('<int:user_id>/', UserDetailView.as_view(), name='user_detail'),
]
