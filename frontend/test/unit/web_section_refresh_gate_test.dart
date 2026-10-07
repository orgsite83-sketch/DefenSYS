import 'package:defensys/navigation/web_section_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
