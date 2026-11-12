import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:defensys/screens/app/student/contact_details_dialog.dart';
import 'package:defensys/screens/app/student/profile_edit_screen.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _student = <String, dynamic>{
  'id': 42,
  'username': '2023304652',
  'role': 'student',
  'first_name': 'Vince Rey',
  'last_name': 'Claveria',
  'email': null,
  'phone_number': '  ',
  'team_id': '111',
  'team_name': 'Team Atlas',
};
const _photoUrl = 'https://example.test/profile-photo.png';

class _Auth extends AuthNotifier {
  _Auth(this.user);
  final Map<String, dynamic> user;
  @override
  AuthState build() =>
      AuthState(isRestoring: false, token: testAccessToken, user: user);
}

class _PhotoPicker extends FilePicker {
  int calls = 0;
  FilePickerResult? result;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    return result;
  }
}

void main() {
  setUp(() {
    FilePicker.platform = _PhotoPicker();
    SharedPreferences.setMockInitialValues({});
    setApiHttpClientForTesting(
      MockClient(
        (_) async => http.Response('{"history":[],"results":[]}', 200),
      ),
    );
  });
  tearDown(resetApiHttpClientForTesting);

  Future<void> showProfile(
    WidgetTester tester, {
    Map<String, dynamic> user = _student,
    double width = 390,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
    await pumpDefensysWidget(
      tester,
      const RepaintBoundary(
        key: ValueKey('profile-preview'),
        child: ProfileScreen(showAppBar: false),
      ),
      overrides: [authProvider.overrideWith(() => _Auth(user))],
      theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    );
  }

  Future<void> showEditor(
    WidgetTester tester, {
    Map<String, dynamic> user = _student,
  }) async {
    await pumpDefensysWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showContactDetailsDialog(context, user),
          child: const Text('Edit contacts'),
        ),
      ),
      overrides: [authProvider.overrideWith(() => _Auth(user))],
    );
    await tester.tap(find.text('Edit contacts'));
    await tester.pumpAndSettle();
  }

  Finder field(String name) => find.descendant(
    of: find.byKey(ValueKey('contact_$name')),
    matching: find.byType(EditableText),
  );

  Future<void> cachePhoto(WidgetTester tester) async {
    await tester.runAsync(() async {
      final bytes = await rootBundle.load('assets/ustp_sidebar.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      PaintingBinding.instance.imageCache.putIfAbsent(
        const NetworkImage(_photoUrl),
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: frame.image)),
        ),
      );
      codec.dispose();
    });
  }

  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'student profile hides IDs and duplicate photo action $width $dark',
        (tester) async {
          await showProfile(tester, width: width, dark: dark);
          expect(find.text('Change Photo'), findsNothing);
          expect(find.byTooltip('Change photo'), findsOneWidget);
          expect(find.textContaining('2023304652'), findsNothing);
          expect(find.textContaining('Team #111'), findsNothing);
          expect(find.text('Username / ID'), findsNothing);
          expect(find.text('Team Atlas'), findsWidgets);
          expect(find.text('None'), findsWidgets);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('profile-preview')),
            'student-contact/profile-${width.toInt()}-${dark ? 'dark' : 'light'}-top',
            viewport: true,
          );
          await tester.tap(find.byTooltip('Change photo'));
          await tester.pumpAndSettle();
          expect(find.text('No profile photo'), findsOneWidget);
          expect(find.text('Upload photo'), findsOneWidget);
          expect(find.text('Change photo'), findsNothing);
          expect(find.text('Remove photo'), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(Dialog),
            'student-contact/photo-empty-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.byTooltip('Close photo'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Edit contact details'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('profile-preview')),
            'student-contact/profile-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
        },
      );
    }
  }

  testWidgets('unassigned and unnamed teams have useful labels', (
    tester,
  ) async {
    await showProfile(
      tester,
      user: {..._student, 'team_id': null, 'team_name': null},
    );
    expect(find.text('Not assigned'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await showProfile(tester, user: {..._student, 'team_name': '  '});
    expect(find.text('Name not set'), findsWidgets);
  });

  testWidgets('faculty keeps its identity and photo action', (tester) async {
    await showProfile(tester, user: {..._student, 'role': 'faculty'});
    expect(find.text('Change Photo'), findsOneWidget);
    expect(find.text('ID: 2023304652'), findsOneWidget);
    expect(find.text('Edit contact details'), findsNothing);
  });

  testWidgets(
    'camera supports keyboard, picker cancellation, and disabled uploads',
    (tester) async {
      final original = FilePicker.platform;
      final picker = _PhotoPicker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = original);
      final pending = Completer<http.Response>();
      var uploads = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            uploads++;
            expect(
              request.body,
              contains('name="avatar"; filename="avatar.png"'),
            );
            return pending.future;
          }
          return http.Response('{"history":[],"results":[]}', 200);
        }),
      );
      await showProfile(tester);
      await cachePhoto(tester);
      Focus.of(
        tester.element(find.byIcon(Icons.camera_alt_rounded)),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picker.calls, 0);
      expect(find.text('No profile photo'), findsOneWidget);
      await tester.tap(find.text('Upload photo'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(uploads, 0);
      picker.result = FilePickerResult([
        PlatformFile(
          name: 'avatar.png',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]);
      await tester.tap(find.text('Upload photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(uploads, 1);
      await tester.tap(find.text('Updating…'));
      await tester.pump();
      expect(picker.calls, 2);
      pending.complete(
        http.Response(jsonEncode({..._student, 'avatar': _photoUrl}), 200),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Change photo'), findsOneWidget);
      expect(find.text('Remove photo'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-photo-preview')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      expect(find.text('Remove'), findsNothing);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('existing photo actions stay inside popup $width $dark', (
        tester,
      ) async {
        await cachePhoto(tester);
        final pending = Completer<http.Response>();
        var removals = 0;
        setApiHttpClientForTesting(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              removals++;
              expect(jsonDecode(request.body), {'remove_avatar': 'true'});
              return pending.future;
            }
            return http.Response('{"history":[],"results":[]}', 200);
          }),
        );
        await showProfile(
          tester,
          width: width,
          dark: dark,
          user: {..._student, 'avatar': _photoUrl},
        );
        expect(find.text('Remove'), findsNothing);
        await tester.tap(find.byTooltip('Change photo'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('profile-photo-preview')),
          findsOneWidget,
        );
        expect(find.text('Upload photo'), findsNothing);
        expect(find.text('Change photo'), findsOneWidget);
        expect(find.text('Remove photo'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(Dialog),
          'student-contact/photo-existing-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        // Cancelling a replacement leaves the current photo in place.
        await tester.tap(find.text('Change photo'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('profile-photo-preview')),
          findsOneWidget,
        );
        await tester.tap(find.text('Remove photo'));
        await tester.pump();
        expect(find.text('Removing…'), findsOneWidget);
        await tester.tap(find.text('Removing…'));
        await tester.pump();
        expect(removals, 1);
        pending.complete(
          http.Response(jsonEncode({..._student, 'avatar': null}), 200),
        );
        await tester.pumpAndSettle();
        expect(find.text('No profile photo'), findsOneWidget);
        expect(find.text('Upload photo'), findsOneWidget);
        expect(find.text('Remove photo'), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close photo'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('failed photo changes keep the popup and current photo', (
    tester,
  ) async {
    await cachePhoto(tester);
    setApiHttpClientForTesting(
      MockClient(
        (request) async => request.method == 'PATCH'
            ? http.Response('{"detail":"Unable to remove photo."}', 400)
            : http.Response('{"history":[],"results":[]}', 200),
      ),
    );
    await showProfile(tester, user: {..._student, 'avatar': _photoUrl});
    await tester.tap(find.byTooltip('Change photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-photo-preview')), findsOneWidget);
    expect(find.text('Remove photo'), findsOneWidget);
    expect(find.text('No profile photo'), findsNothing);
    expect(find.text('Unable to remove photo.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
  });

  testWidgets('long contacts and team name fit the narrow dark profile', (
    tester,
  ) async {
    await showProfile(
      tester,
      width: 320,
      dark: true,
      user: {
        ..._student,
        'email': 'student.with.a.very.long.address@university.example.com',
        'phone_number': '+639171234567',
        'team_name': 'Team with a long descriptive research project name',
      },
    );
    await tester.ensureVisible(find.text('Edit contact details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Edit contact details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capturePreview(
      tester,
      find.byType(Dialog),
      'student-contact/contact-320-dark',
      viewport: true,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'contact dialog cancel makes no save and prefills saved contacts',
    (tester) async {
      var writes = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'PATCH') writes++;
          return http.Response('{}', 200);
        }),
      );
      await showEditor(
        tester,
        user: {
          ..._student,
          'email': 'saved@gmail.com',
          'phone_number': '09171234567',
        },
      );
      expect(
        tester.widget<EditableText>(field('email')).controller.text,
        'saved@gmail.com',
      );
      expect(
        tester.widget<EditableText>(field('phone_number')).controller.text,
        '09171234567',
      );
      await tester.enterText(field('email'), 'edited@gmail.com');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('Edit contact details'), findsNothing);
    },
  );

  testWidgets('save refreshes current user and blocks repeat submission', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final writes = <Map<String, dynamic>>[];
    setApiHttpClientForTesting(
      MockClient((request) async {
        writes.add(jsonDecode(request.body) as Map<String, dynamic>);
        return pending.future;
      }),
    );
    await showEditor(tester);
    await tester.enterText(field('email'), 'new@gmail.com');
    await tester.enterText(field('phone_number'), '09170000000');
    await tester.enterText(field('current_password'), 'CurrentTest!29');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    await tester.tap(find.text('Saving…'));
    await tester.pump();
    expect(writes, hasLength(1));
    expect(
      writes.single.keys,
      unorderedEquals(['email', 'phone_number', 'current_password']),
    );
    pending.complete(
      http.Response(
        jsonEncode({
          ..._student,
          'email': 'new@gmail.com',
          'phone_number': '09170000000',
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Edit contacts')),
    );
    expect(container.read(authProvider).user?['email'], 'new@gmail.com');
    expect(find.text('Edit contact details'), findsNothing);
  });

  testWidgets('clearing contacts sends empty values', (tester) async {
    Map<String, dynamic>? saved;
    setApiHttpClientForTesting(
      MockClient((request) async {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({..._student, 'email': '', 'phone_number': ''}),
          200,
        );
      }),
    );
    await showEditor(
      tester,
      user: {
        ..._student,
        'email': 'saved@gmail.com',
        'phone_number': '09171234567',
      },
    );
    await tester.enterText(field('email'), '');
    await tester.enterText(field('phone_number'), '');
    await tester.enterText(field('current_password'), 'CurrentTest!29');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?['email'], '');
    expect(saved?['phone_number'], '');
  });

  testWidgets('validation and connection errors retain entered contacts', (
    tester,
  ) async {
    var calls = 0;
    setApiHttpClientForTesting(
      MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            '{"email":["Enter a valid email address."]}',
            400,
          );
        }
        throw http.ClientException('offline');
      }),
    );
    await showEditor(tester);
    await tester.enterText(field('email'), 'invalid');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Enter your current password.'), findsOneWidget);
    await tester.enterText(field('current_password'), 'CurrentTest!29');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      tester.widget<EditableText>(field('email')).controller.text,
      'invalid',
    );
    await capturePreview(
      tester,
      find.byType(Dialog),
      'student-contact/contact-error',
      viewport: true,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to save contact details. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<EditableText>(field('email')).controller.text,
      'invalid',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
