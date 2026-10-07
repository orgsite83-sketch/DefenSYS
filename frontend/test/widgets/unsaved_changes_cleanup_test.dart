import 'package:defensys/services/app/unsaved_changes_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('closing a form releases its dirty flag and draft callback', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dirty = container.read(unsavedChangesProvider.notifier);
    final draft = container.read(unsavedChangesSaveDraftProvider.notifier);
    dirty.setDirty(true);
    draft.setCallback(() async => true);
    releaseUnsavedChangesAfterFrame(dirty, draft);
    await tester.pumpWidget(const SizedBox());
    expect(container.read(unsavedChangesProvider), isFalse);
    expect(container.read(unsavedChangesSaveDraftProvider), isNull);
  });

  testWidgets(
    'an old form cannot clear the next page dirty flag or draft callback',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dirty = container.read(unsavedChangesProvider.notifier);
      final draft = container.read(unsavedChangesSaveDraftProvider.notifier);
      dirty.setDirty(true);
      draft.setCallback(() async => false);
      releaseUnsavedChangesAfterFrame(dirty, draft);
      Future<bool> saveNextPage() async => true;
      dirty.setDirty(true);
      draft.setCallback(saveNextPage);
      await tester.pumpWidget(const SizedBox());
      expect(container.read(unsavedChangesProvider), isTrue);
      expect(
        container.read(unsavedChangesSaveDraftProvider),
        same(saveNextPage),
      );
    },
  );
}
