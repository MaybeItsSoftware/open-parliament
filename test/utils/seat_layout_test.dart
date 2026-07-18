import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/member.dart';
import 'package:open_hansard/utils/seat_layout.dart';
import 'package:open_hansard/viewmodels/house_seating_viewmodel.dart' show HouseType;

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

  test('buildChamberLayout returns empty for empty members', () {
    expect(buildChamberLayout(house: HouseType.commons, members: []), isEmpty);
  });

  test('buildChamberLayout returns positions in bounds for Commons', () {
    final members = [
      const Member(id: 1, name: 'Speaker', party: 'Speaker', partyAbbreviation: 'Spk'),
      const Member(id: 2, name: 'Labour MP', party: 'Labour', partyAbbreviation: 'Lab'),
      const Member(id: 3, name: 'Conservative MP', party: 'Conservative', partyAbbreviation: 'Con'),
    ];
    final positions = buildChamberLayout(house: HouseType.commons, members: members);
    expect(positions, hasLength(3));
    for (final p in positions) {
      expect(p.dx, inInclusiveRange(0.0, 1.0));
      expect(p.dy, inInclusiveRange(0.0, 1.0));
    }
  });

  test('buildChamberLayout returns positions in bounds for Lords', () {
    final members = [
      const Member(id: 1, name: 'Speaker', party: 'Speaker', partyAbbreviation: 'Spk'),
      const Member(id: 2, name: 'Labour Lord', party: 'Labour', partyAbbreviation: 'Lab'),
      const Member(id: 3, name: 'Conservative Lord', party: 'Conservative', partyAbbreviation: 'Con'),
      const Member(id: 4, name: 'Crossbench Lord', party: 'Crossbench', partyAbbreviation: 'CB'),
    ];
    final positions = buildChamberLayout(house: HouseType.lords, members: members);
    expect(positions, hasLength(4));
    for (final p in positions) {
      expect(p.dx, inInclusiveRange(0.0, 1.0));
      expect(p.dy, inInclusiveRange(0.0, 1.0));
    }
  });
}
