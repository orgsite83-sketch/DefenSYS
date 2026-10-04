import 'package:defensys/screens/guest/guest_evaluation_entry.dart';
import 'package:defensys/screens/web/admin/user_management/external_evaluators/external_evaluator_views.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/utils/guest_invitation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/table/defensys_data_table.dart';

const _approved = {
  'id': 11,
  'name': 'Dr. Lina Santos',
  'email': 'lina@example.edu',
  'institution': 'Partner University',
  'status': 'approved',
  'is_active': true,
};
const _pending = {
  'id': 12,
  'name': 'Alex Reyes',
  'email': '',
  'institution': '',
  'status': 'pending',
  'is_active': true,
};
const _invitation = {
  'id': 21,
  'guest_name': 'Dr. Lina Santos',
  'email': 'lina@example.edu',
  'status': 'Active',
  'is_active': true,
  'code': 'DEF-123456789ABC',
  'expires_at': '2026-10-20T23:59:00+08:00',
  'last_access_at': null,
  'used_at': null,
  'submitted_count': 1,
  'schedule_ids': [1, 2],
  'schedules': [
    {
      'id': 1,
      'team_name': 'Team SkyLedger',
      'scope': 'pit',
      'stage_label': 'PIT Demo',
      'date': '2026-10-20',
    },
    {
      'id': 2,
      'team_name': 'Team Aero',
      'scope': 'pit',
      'stage_label': 'PIT Demo',
      'date': '2026-10-20',
    },
  ],
};

class _Directory extends ExternalEvaluatorNotifier {
  _Directory({this.admin = true});
  final bool admin;
  Map<String, dynamic>? saved;
  int reviews = 0;
  @override
  ExternalEvaluatorState build() => ExternalEvaluatorState(
    canApprove: admin,
    evaluators: const [_approved, _pending],
    invitations: const [_invitation],
  );
  @override
  Future<bool> fetch() async => true;
  @override
  Future<bool> register(Map<String, dynamic> data) async {
    saved = data;
    return true;
  }

  @override
  Future<bool> review(int id, Map<String, dynamic> data) async {
    reviews++;
    return true;
  }
}

class _Auth extends AuthNotifier {
  _Auth({this.admin = true});
  final bool admin;
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    user: {'role': admin ? 'admin' : 'faculty'},
  );
}

class _GuestAuth extends AuthNotifier {
  String? entered;
  @override
  AuthState build() => const AuthState(isRestoring: false);
  @override
  Future<bool> loginGuest(String code) async {
    entered = code;
    state = state.copyWith(
      error: 'This invitation has expired. Contact your defense coordinator.',
    );
    return false;
  }
}

void main() {
  setUpAll(loadPreviewFonts);
  Future<void> directory(
    WidgetTester tester,
    _Directory state, {
    double width = 1200,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalEvaluatorProvider.overrideWith(() => state),
          authProvider.overrideWith(() => _Auth(admin: state.admin)),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          builder: (_, child) => RepaintBoundary(
            key: const ValueKey('evaluator-root-preview'),
            child: child!,
          ),
          home: const Scaffold(
            body: RepaintBoundary(
              key: ValueKey('evaluator-preview'),
              child: SingleChildScrollView(child: ExternalEvaluatorDirectory()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openActions(WidgetTester tester, String kind, int id) async {
    final trigger = find.byKey(ValueKey('$kind-actions-$id'));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  }

  testWidgets('Directory has named columns and admin can review nominations', (
    tester,
  ) async {
    final state = _Directory();
    await directory(tester, state);
    expect(find.text('Evaluator'), findsOneWidget);
    expect(find.text('Institution'), findsOneWidget);
    expect(find.text('Approval'), findsOneWidget);
    expect(find.text('Assign evaluators'), findsOneWidget);
    expect(find.text('Assign'), findsNothing);
    await openActions(tester, 'evaluator', 12);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(state.reviews, 1);
    expect(find.text('Approve'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT leads see pool and nominations without approval controls', (
    tester,
  ) async {
    await directory(tester, _Directory(admin: false));
    expect(find.text('Dr. Lina Santos'), findsOneWidget);
    await openActions(tester, 'evaluator', 11);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Deactivate'), findsNothing);
    expect(find.text('Assign'), findsOneWidget);
  });

  testWidgets('PIT leads can assign an approved evaluator on a narrow screen', (
    tester,
  ) async {
    await directory(tester, _Directory(admin: false), width: 390);
    await openActions(tester, 'evaluator', 11);
    expect(find.text('Assign'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  Future<void> invitation(
    WidgetTester tester, {
    double width = 1280,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        builder: (_, child) => RepaintBoundary(
          key: const ValueKey('invitation-access-preview'),
          child: child!,
        ),
        home: const Scaffold(),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        child: const GuestInvitationDialog(
          invitations: [_invitation],
          portal: 'http://192.168.1.3:57583/#/guest/evaluate',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Code and login link actions copy the exact invitation values', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await invitation(tester);
    await tester.tap(find.text('Copy login link'));
    await tester.pumpAndSettle();
    const expectedLink =
        'http://192.168.1.3:57583/#/guest/evaluate?code=DEF-123456789ABC';
    expect(copied.single, expectedLink);
    expect(find.text('Login link copied.'), findsOneWidget);
    expect(find.text(expectedLink), findsOneWidget);
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(copied.last, _invitation['code']);
    expect(find.text('Access code copied.'), findsOneWidget);
    expect(copied, [expectedLink, _invitation['code']]);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('guest-invitation-content')))
          .height,
      lessThan(620),
    );
  });

  testWidgets(
    'Blocked clipboard leaves selectable code and link with inline recovery',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard-denied');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await invitation(tester);
      await tester.tap(find.text('Copy code'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Select the link or code and use Copy'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNWidgets(2));
      expect(find.text('DEF-123456789ABC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Open login link launches the guest URL with its invitation code',
    (tester) async {
      String? opened;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          opened = (call.arguments as Map)['url'] as String;
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await invitation(tester);
      await tester.tap(find.byTooltip('Open login link'));
      await tester.pumpAndSettle();
      expect(
        opened,
        'http://192.168.1.3:57583/#/guest/evaluate?code=DEF-123456789ABC',
      );
    },
  );

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'invitation access fits $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          await invitation(tester, width: width, dark: dark);
          expect(find.text('Copy code'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('invitation-access-preview')),
            'invitation-access-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
        },
      );
    }
  }

  testWidgets(
    'Invitations show progress, expiry and access actions on a narrow screen',
    (tester) async {
      await directory(tester, _Directory(), width: 390);
      await tester.tap(find.text('Invitations (1)'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2 defenses submitted'), findsOneWidget);
      expect(find.text('Last access —'), findsOneWidget);
      expect(find.text('Renew'), findsNothing);
      await openActions(tester, 'invitation', 21);
      expect(find.text('Renew'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'evaluator directory fills $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          await directory(tester, _Directory(), width: width, dark: dark);
          if (width > 760) {
            final table = find.byType(DefensysDataTable<Map<String, dynamic>>);
            expect(tester.getSize(table).width, greaterThan(width - 60));
          }
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('evaluator-preview')),
            'external-evaluators-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
          await openActions(tester, 'evaluator', 11);
          expect(find.text('Assign'), findsOneWidget);
          expect(find.text('Edit'), findsOneWidget);
          expect(find.text('Deactivate'), findsOneWidget);
          final trigger = tester.getRect(
            find.byKey(const ValueKey('evaluator-actions-11')),
          );
          final firstAction = tester.getRect(find.text('Assign'));
          expect(firstAction.top, greaterThan(trigger.bottom));
          expect(firstAction.right, lessThanOrEqualTo(trigger.right));
          await capturePreview(
            tester,
            find.byKey(const ValueKey('evaluator-root-preview')),
            'external-evaluator-menu-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Assign'), findsNothing);
          await tester.tap(find.text('Invitations (1)'));
          await tester.pumpAndSettle();
          expect(find.text('Renew'), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('evaluator-preview')),
            'external-invitations-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
          await openActions(tester, 'invitation', 21);
          expect(find.text('View access'), findsOneWidget);
          expect(find.text('Renew'), findsOneWidget);
          expect(find.text('Revoke'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('evaluator-root-preview')),
            'external-invitation-menu-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
        },
      );
    }
  }

  testWidgets(
    'More menus close on selection and open the selected invitation',
    (tester) async {
      await directory(tester, _Directory());
      await openActions(tester, 'evaluator', 11);
      expect(find.text('Assign'), findsOneWidget);
      await tester.tap(find.text('External evaluators'));
      await tester.pumpAndSettle();
      expect(find.text('Assign'), findsNothing);
      await openActions(tester, 'evaluator', 12);
      expect(find.text('Approve'), findsOneWidget);
      await openActions(tester, 'evaluator', 11);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Assign'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invitations (1)'));
      await tester.pumpAndSettle();
      await openActions(tester, 'invitation', 21);
      await tester.tap(find.text('View access'));
      await tester.pumpAndSettle();
      expect(find.text('Evaluator invitations'), findsOneWidget);
      expect(find.text('DEF-123456789ABC'), findsOneWidget);
      expect(find.text('Renew'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Creation collects reusable identity and admin approves directly',
    (tester) async {
      final state = _Directory();
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => ExternalEvaluatorCreateDialog.show(context),
            child: const Text('Add'),
          ),
        ),
        overrides: [
          externalEvaluatorProvider.overrideWith(() => state),
          authProvider.overrideWith(() => _Auth()),
        ],
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Dr. Guest Expert',
      );
      await tester.tap(find.text('Save & approve'));
      await tester.pumpAndSettle();
      expect(state.saved?['name'], 'Dr. Guest Expert');
      expect(state.saved?['email'], '');
      expect(find.textContaining('Password'), findsNothing);
    },
  );

  testWidgets(
    'Selector includes only approved evaluators and preserves faculty-independent selection',
    (tester) async {
      Set<int> selected = {};
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ExternalEvaluatorSelector(
              selected: selected,
              onChanged: (ids) => setState(() => selected = ids),
              onExpiryChanged: (_) {},
            ),
          ),
        ),
        overrides: [externalEvaluatorProvider.overrideWith(() => _Directory())],
      );
      expect(find.text('Alex Reyes'), findsNothing);
      await tester.tap(find.text('Dr. Lina Santos'));
      await tester.pumpAndSettle();
      expect(selected, {11});
      expect(find.textContaining('faculty panel chair'), findsOneWidget);
      expect(find.textContaining('end of defense day'), findsOneWidget);
    },
  );

  testWidgets(
    'Guest portal supports manual code entry and an actionable expired invitation message',
    (tester) async {
      final guest = _GuestAuth();
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        const GuestEvaluationEntry(initialCode: 'DEF-123456789ABC'),
        overrides: [authProvider.overrideWith(() => guest)],
      );
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.textContaining('app download'), findsOneWidget);
      await tester.ensureVisible(find.text('Open my assigned defenses'));
      await tester.tap(find.text('Open my assigned defenses'));
      await tester.pumpAndSettle();
      expect(guest.entered, 'DEF-123456789ABC');
      expect(find.textContaining('invitation has expired'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Login link retains web base path and includes code in the guest route',
    () {
      final portal = guestPortalUrl(
        base: Uri.parse('https://defensys.example/portal/#/admin/users'),
      );
      expect(portal, 'https://defensys.example/portal/#/guest/evaluate');
      expect(
        guestInvitationUrl('DEF-ABC', portal: portal),
        'https://defensys.example/portal/#/guest/evaluate?code=DEF-ABC',
      );
      expect(
        guestInvitationUrl(
          'DEF-ABC',
          portal: 'https://defensys.example/guest/evaluate',
        ),
        'https://defensys.example/guest/evaluate?code=DEF-ABC',
      );
    },
  );
}
