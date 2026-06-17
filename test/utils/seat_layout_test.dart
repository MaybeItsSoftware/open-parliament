import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/seat_layout.dart';

void main() {
  test('buildHemicycleLayout returns empty for zero seats', () {
    expect(buildHemicycleLayout(0), isEmpty);
  });

  test('buildHemicycleLayout returns positions in bounds', () {
    final positions = buildHemicycleLayout(120);
    expect(positions, hasLength(120));
    for (final p in positions) {
      expect(p.dx, inInclusiveRange(0.0, 1.0));
      expect(p.dy, inInclusiveRange(0.0, 1.0));
    }
  });

  test('buildHemicycleLayout handles small counts', () {
    final positions = buildHemicycleLayout(5);
    expect(positions, hasLength(5));
  });
}
