// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DefenSYS';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get discard => 'Discard';

  @override
  String get saveAndLeave => 'Save & leave';

  @override
  String get stay => 'Stay';

  @override
  String get logoutTitle => 'Log out?';

  @override
  String get logoutMessage => 'You will need to sign in again to continue.';

  @override
  String get logoutConfirm => 'Log out';

  @override
  String get discardUnsavedTitle => 'Discard unsaved changes?';

  @override
  String get discardUnsavedMessage =>
      'You have unsaved changes. Leaving now will discard them.';

  @override
  String get offlineBannerMessage =>
      'You are offline. Some actions may be unavailable until you reconnect.';

  @override
  String get loginTitle => 'Sign in to DefenSYS';

  @override
  String get loginStudentIdLabel => 'Student ID';

  @override
  String get loginUsernameLabel => 'Username or email';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginSignIn => 'Sign in';

  @override
  String get loginGuestPanelist => 'Guest panelist';

  @override
  String get loginRequiredField => 'This field is required';

  @override
  String get loginInvalidCredentials =>
      'Invalid credentials. Please try again.';

  @override
  String get loginConnectionError =>
      'Connection error. Check your network and try again.';

  @override
  String get loginSessionEnded => 'Your session ended. Please sign in again.';

  @override
  String get errorForbidden =>
      'You do not have permission to perform this action.';

  @override
  String get errorUnauthorized => 'Your session expired. Please sign in again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get undo => 'Undo';

  @override
  String get fileRemoved => 'File removed';

  @override
  String get fileRemoveFailed => 'Failed to remove file';

  @override
  String get navOverview => 'Overview';

  @override
  String get navAcademicPeriods => 'Academic Periods';

  @override
  String get navUserManagement => 'User Management';

  @override
  String get navStudentTeams => 'Student Teams';

  @override
  String get navStudentRecords => 'Student Records';

  @override
  String get navGradeCenter => 'Grade Center';

  @override
  String get navRubricEngine => 'Rubric Engine';

  @override
  String get navRepositoryAudit => 'Repository Vault';

  @override
  String get navCurriculumAnalytics => 'Curriculum Analytics';

  @override
  String get navDefenseScheduler => 'Defense Scheduler';

  @override
  String get navDefenseBoard => 'Defense Board';

  @override
  String get navDefenseStages => 'Defense Stages';

  @override
  String get navScheduling => 'Scheduling';

  @override
  String get navTeam => 'Team';

  @override
  String get navDigitalVault => 'Digital Vault';

  @override
  String get navWeeklyReport => 'Weekly Report';

  @override
  String get navPeerEval => 'Peer Eval';

  @override
  String get navMyGrades => 'My Grades';

  @override
  String get navAssignments => 'Assignments';

  @override
  String get navGradeSheet => 'Grade Sheet';

  @override
  String get navResults => 'Results';

  @override
  String get studentDashboardTitle => 'Student Dashboard';

  @override
  String get panelistDashboardTitle => 'Panelist Dashboard';

  @override
  String get loadingDashboard => 'Loading dashboard…';

  @override
  String get errorLoadingDashboard => 'Error loading dashboard';

  @override
  String get loadingAssignments => 'Loading assignments…';

  @override
  String get profileTooltip => 'Profile';

  @override
  String get clearSearchTooltip => 'Clear search';

  @override
  String get digitalVaultTitle => 'Digital Vault';

  @override
  String get failedToLoadVault => 'Failed to load vault';

  @override
  String get leaveBulkImportTitle => 'Leave bulk import?';

  @override
  String get leaveBulkImportMessage =>
      'You have unsaved row edits. Save draft and leave, or stay to continue editing.';
}
