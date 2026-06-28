from django.urls import include, path

from .views import (
    BulkImportUsersView,
    GuestCodeExchangeView,
    GuestCodeValidateView,
    GuestPanelistCodeDetailView,
    GuestPanelistCodeListCreateView,
    PitInstructorAssignmentDetailView,
    PitInstructorAssignmentView,
    PitLeadOfficialClassListImportView,
    PitLeadStudentImportView,
    UserAdviserAssignmentHistoryView,
    UserDetailView,
    UserESignatureView,
    UserListCreateView,
    UserRoleAssignmentHistoryView,
)


urlpatterns = [
    path('academic-records/', include('user_management.academic_records.urls')),
    path('', UserListCreateView.as_view(), name='users'),
    path('bulk-import/', BulkImportUsersView.as_view(), name='users_bulk_import'),
    path('pit-lead/student-import/', PitLeadStudentImportView.as_view(), name='pit_lead_student_import'),
    path(
        'pit-lead/official-class-list-import/',
        PitLeadOfficialClassListImportView.as_view(),
        name='pit_lead_official_class_list_import',
    ),
    path('pit-instructors/', PitInstructorAssignmentView.as_view(), name='pit_instructor_assignments'),
    path(
        'pit-instructors/<int:assignment_id>/',
        PitInstructorAssignmentDetailView.as_view(),
        name='pit_instructor_assignment_detail',
    ),
    path('guest-codes/', GuestPanelistCodeListCreateView.as_view(), name='guest_codes'),
    path('guest-codes/<int:code_id>/', GuestPanelistCodeDetailView.as_view(), name='guest_code_detail'),
    path('guest-codes/exchange/', GuestCodeExchangeView.as_view(), name='guest_code_exchange'),
    path('guest-codes/validate/<str:code>/', GuestCodeValidateView.as_view(), name='guest_code_validate'),
    path('e-signature/', UserESignatureView.as_view(), name='user_e_signature'),
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
