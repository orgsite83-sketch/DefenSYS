from django.urls import path

from .views import (
    ChangePasswordView,
    CurrentUserView,
    CustomTokenObtainPairView,
    LogoutView,
    SystemAuditLogListView,
    ThrottledTokenRefreshView,
    UserHistoryView,
)

urlpatterns = [
    path('login/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', ThrottledTokenRefreshView.as_view(), name='token_refresh'),
    path('logout/', LogoutView.as_view(), name='token_blacklist'),
    path('me/', CurrentUserView.as_view(), name='current_user'),
    path('me/history/', UserHistoryView.as_view(), name='user_history'),
    path('change-password/', ChangePasswordView.as_view(), name='change_password'),
    path('audit-logs/', SystemAuditLogListView.as_view(), name='system_audit_logs'),
]
