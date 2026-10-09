import 'package:defensys/navigation/web_section_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'scheduler revisits refresh external changes without duplicating first load',
    () {
      final gate = WebSectionRefreshGate(now: () => DateTime(2026));
      expect(gate.activate('scheduler', alwaysRefresh: true), isFalse);
      gate.activate('rubrics');
      expect(gate.activate('scheduler', alwaysRefresh: true), isTrue);
    },
  );

  test('a saved dependency bypasses the cooldown exactly once on return', () {
    final gate = WebSectionRefreshGate(now: () => DateTime(2026));
    expect(gate.activate('scheduler', revision: 0), isFalse);
    expect(gate.activate('rubrics', revision: 0), isFalse);
    expect(gate.activate('scheduler', revision: 1), isTrue);
    expect(gate.activate('scheduler', revision: 1), isFalse);
    expect(gate.activate('scheduler', revision: 2), isTrue);
  });

  test('first visits and quick returns do not duplicate page loads', () {
    var now = DateTime(2026);
    final gate = WebSectionRefreshGate(now: () => now);
    expect(gate.activate('teams'), isFalse);
    expect(gate.activate('grades'), isFalse);
    now = now.add(const Duration(seconds: 10));
    expect(gate.activate('teams'), isFalse);
    now = now.add(const Duration(seconds: 35));
    expect(gate.activate('teams'), isTrue);
    expect(gate.activate('teams'), isFalse);
    expect(gate.activate('grades'), isTrue);
  });
}
