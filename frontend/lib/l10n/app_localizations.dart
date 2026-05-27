import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DefenSYS'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @saveAndLeave.
  ///
  /// In en, this message translates to:
  /// **'Save & leave'**
  String get saveAndLeave;

  /// No description provided for @stay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get stay;

  /// No description provided for @logoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutTitle;

  /// No description provided for @logoutMessage.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to continue.'**
  String get logoutMessage;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutConfirm;

  /// No description provided for @discardUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get discardUnsavedTitle;

  /// No description provided for @discardUnsavedMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Leaving now will discard them.'**
  String get discardUnsavedMessage;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Some actions may be unavailable until you reconnect.'**
  String get offlineBannerMessage;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to DefenSYS'**
  String get loginTitle;

  /// No description provided for @loginStudentIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Student ID'**
  String get loginStudentIdLabel;

  /// No description provided for @loginUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username or email'**
  String get loginUsernameLabel;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginSignIn;

  /// No description provided for @loginGuestPanelist.
  ///
  /// In en, this message translates to:
  /// **'Guest panelist'**
  String get loginGuestPanelist;

  /// No description provided for @loginRequiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get loginRequiredField;

  /// No description provided for @loginInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials. Please try again.'**
  String get loginInvalidCredentials;

  /// No description provided for @loginConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Check your network and try again.'**
  String get loginConnectionError;

  /// No description provided for @loginSessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Your session ended. Please sign in again.'**
  String get loginSessionEnded;

  /// No description provided for @errorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this action.'**
  String get errorForbidden;

  /// No description provided for @errorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get errorUnauthorized;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @fileRemoved.
  ///
  /// In en, this message translates to:
  /// **'File removed'**
  String get fileRemoved;

  /// No description provided for @fileRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove file'**
  String get fileRemoveFailed;

  /// No description provided for @navOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navOverview;

  /// No description provided for @navAcademicPeriods.
  ///
  /// In en, this message translates to:
  /// **'Academic Periods'**
  String get navAcademicPeriods;

  /// No description provided for @navUserManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get navUserManagement;

  /// No description provided for @navStudentTeams.
  ///
  /// In en, this message translates to:
  /// **'Student Teams'**
  String get navStudentTeams;

  /// No description provided for @navStudentRecords.
  ///
  /// In en, this message translates to:
  /// **'Student Records'**
  String get navStudentRecords;

  /// No description provided for @navGradeCenter.
  ///
  /// In en, this message translates to:
  /// **'Grade Center'**
  String get navGradeCenter;

  /// No description provided for @navRubricEngine.
  ///
  /// In en, this message translates to:
  /// **'Rubric Engine'**
  String get navRubricEngine;

  /// No description provided for @navRepositoryAudit.
  ///
  /// In en, this message translates to:
  /// **'Repository Vault'**
  String get navRepositoryAudit;

  /// No description provided for @navCurriculumAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Curriculum Analytics'**
  String get navCurriculumAnalytics;

  /// No description provided for @navDefenseScheduler.
  ///
  /// In en, this message translates to:
  /// **'Defense Scheduler'**
  String get navDefenseScheduler;

  /// No description provided for @navDefenseBoard.
  ///
  /// In en, this message translates to:
  /// **'Defense Board'**
  String get navDefenseBoard;

  /// No description provided for @navDefenseStages.
  ///
  /// In en, this message translates to:
  /// **'Defense Stages'**
  String get navDefenseStages;

  /// No description provided for @navScheduling.
  ///
  /// In en, this message translates to:
  /// **'Scheduling'**
  String get navScheduling;

  /// No description provided for @navTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get navTeam;

  /// No description provided for @navDigitalVault.
  ///
  /// In en, this message translates to:
  /// **'Digital Vault'**
  String get navDigitalVault;

  /// No description provided for @navWeeklyReport.
  ///
  /// In en, this message translates to:
  /// **'Weekly Report'**
  String get navWeeklyReport;

  /// No description provided for @navPeerEval.
  ///
  /// In en, this message translates to:
  /// **'Peer Eval'**
  String get navPeerEval;

  /// No description provided for @navMyGrades.
  ///
  /// In en, this message translates to:
  /// **'My Grades'**
  String get navMyGrades;

  /// No description provided for @navAssignments.
  ///
  /// In en, this message translates to:
  /// **'Assignments'**
  String get navAssignments;

  /// No description provided for @navGradeSheet.
  ///
  /// In en, this message translates to:
  /// **'Grade Sheet'**
  String get navGradeSheet;

  /// No description provided for @navResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get navResults;

  /// No description provided for @studentDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Student Dashboard'**
  String get studentDashboardTitle;

  /// No description provided for @panelistDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Panelist Dashboard'**
  String get panelistDashboardTitle;

  /// No description provided for @loadingDashboard.
  ///
  /// In en, this message translates to:
  /// **'Loading dashboard…'**
  String get loadingDashboard;

  /// No description provided for @errorLoadingDashboard.
  ///
  /// In en, this message translates to:
  /// **'Error loading dashboard'**
  String get errorLoadingDashboard;

  /// No description provided for @loadingAssignments.
  ///
  /// In en, this message translates to:
  /// **'Loading assignments…'**
  String get loadingAssignments;

  /// No description provided for @profileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTooltip;

  /// No description provided for @clearSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearchTooltip;

  /// No description provided for @digitalVaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Digital Vault'**
  String get digitalVaultTitle;

  /// No description provided for @failedToLoadVault.
  ///
  /// In en, this message translates to:
  /// **'Failed to load vault'**
  String get failedToLoadVault;

  /// No description provided for @leaveBulkImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave bulk import?'**
  String get leaveBulkImportTitle;

  /// No description provided for @leaveBulkImportMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved row edits. Save draft and leave, or stay to continue editing.'**
  String get leaveBulkImportMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fil':
      return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
