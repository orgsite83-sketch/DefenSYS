import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UnsavedChangesNotifier extends Notifier<bool> {
  int _revision = 0;
  bool get isMounted => ref.mounted;
  @override
  bool build() => false;

  void setDirty(bool value) {
    _revision++;
    state = value;
  }
}

final unsavedChangesProvider = NotifierProvider<UnsavedChangesNotifier, bool>(
  UnsavedChangesNotifier.new,
);

class UnsavedChangesSaveDraftNotifier
    extends Notifier<Future<bool> Function()?> {
  int _revision = 0;
  bool get isMounted => ref.mounted;
  @override
  Future<bool> Function()? build() => null;

  void setCallback(Future<bool> Function()? callback) {
    _revision++;
    state = callback;
  }
}

/// Dispose runs while the tree is locked. Release the old form's guard after
/// the frame, and only if the next screen has not registered its own guard.
void releaseUnsavedChangesAfterFrame(
  UnsavedChangesNotifier? dirty,
  UnsavedChangesSaveDraftNotifier? draft,
) {
  if (dirty == null || draft == null) return;
  final dirtyRevision = dirty._revision;
  final draftRevision = draft._revision;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!dirty.isMounted ||
        !draft.isMounted ||
        dirty._revision != dirtyRevision ||
        draft._revision != draftRevision) {
      return;
    }
    dirty.setDirty(false);
    draft.setCallback(null);
  });
}

final unsavedChangesSaveDraftProvider =
    NotifierProvider<UnsavedChangesSaveDraftNotifier, Future<bool> Function()?>(
      UnsavedChangesSaveDraftNotifier.new,
    );
