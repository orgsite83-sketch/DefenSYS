import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminOverviewScopeProvider = NotifierProvider<AdminOverviewScope, String>(
  AdminOverviewScope.new,
);

class AdminOverviewScope extends Notifier<String> {
  @override
  String build() {
    return 'capstone';
  }

  void select(String scope) {
    if (scope == 'all') scope = 'capstone';
    if (const ['capstone', 'pit'].contains(scope)) state = scope;
  }
}
