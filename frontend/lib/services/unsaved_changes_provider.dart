import 'package:flutter_riverpod/flutter_riverpod.dart';

class UnsavedChangesNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setDirty(bool value) {
    state = value;
  }
}

final unsavedChangesProvider = NotifierProvider<UnsavedChangesNotifier, bool>(
  UnsavedChangesNotifier.new,
);

class UnsavedChangesSaveDraftNotifier extends Notifier<Future<bool> Function()?> {
  @override
  Future<bool> Function()? build() => null;

  void setCallback(Future<bool> Function()? callback) {
    state = callback;
  }
}

final unsavedChangesSaveDraftProvider = NotifierProvider<UnsavedChangesSaveDraftNotifier, Future<bool> Function()?>(
  UnsavedChangesSaveDraftNotifier.new,
);
