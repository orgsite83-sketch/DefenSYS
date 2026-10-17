import 'package:flutter_riverpod/flutter_riverpod.dart';

final studentTeamSelectionProvider =
    NotifierProvider<StudentTeamSelection, int?>(StudentTeamSelection.new);

class StudentTeamSelection extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}
