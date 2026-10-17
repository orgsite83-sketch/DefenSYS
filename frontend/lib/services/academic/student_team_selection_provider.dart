import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

final studentTeamSelectionProvider =
    NotifierProvider<StudentTeamSelection, int?>(StudentTeamSelection.new);

class StudentTeamSelection extends Notifier<int?> {
  @override
  int? build() {
    ref.watch(authProvider.select((auth) => auth.user?['id']));
    return null;
  }

  void select(int? id) => state = id;
}
