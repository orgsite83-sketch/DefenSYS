from django.urls import path

from .views import (
    CurrentUserView,
    CustomTokenObtainPairView,
    LogoutView,
    SystemAuditLogListView,
    ThrottledTokenRefreshView,
)

urlpatterns = [
    path('login/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', ThrottledTokenRefreshView.as_view(), name='token_refresh'),
    path('logout/', LogoutView.as_view(), name='token_blacklist'),
    path('me/', CurrentUserView.as_view(), name='current_user'),
    path('audit-logs/', SystemAuditLogListView.as_view(), name='system_audit_logs'),
]
