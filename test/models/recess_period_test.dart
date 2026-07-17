import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/recess_period.dart';

void main() {
  group('RecessPeriod.fromApiJson', () {
    test('parses a PascalCase What\'s On event', () {
      final period = RecessPeriod.fromApiJson({
        'Description': 'Summer recess',
        'StartDate': '2024-07-30T00:00:00',
        'EndDate': '2024-09-02T00:00:00',
        'House': 'Commons',
      });

      expect(period, isNotNull);
      expect(period!.description, 'Summer recess');
      expect(period.startDate, DateTime(2024, 7, 30));
      expect(period.endDate, DateTime(2024, 9, 2));
      expect(period.house, 'Commons');
    });

    test('accepts camelCase keys', () {
      final period = RecessPeriod.fromApiJson({
        'description': 'Whitsun recess',
        'startDate': '2024-05-23',
        'endDate': '2024-06-03',
        'house': 'Lords',
      });

      expect(period, isNotNull);
      expect(period!.description, 'Whitsun recess');
      expect(period.startDate, DateTime(2024, 5, 23));
      expect(period.endDate, DateTime(2024, 6, 3));
      expect(period.house, 'Lords');
    });

    test('normalises time components to midnight', () {
      final period = RecessPeriod.fromApiJson({
        'StartDate': '2024-07-30T09:30:00',
        'EndDate': '2024-09-02T17:00:00',
      });

      expect(period!.startDate, DateTime(2024, 7, 30));
      expect(period.endDate, DateTime(2024, 9, 2));
    });

    test('falls back to "Recess" and the queried house when omitted', () {
      final period = RecessPeriod.fromApiJson(
        {'StartDate': '2024-07-30T00:00:00'},
        fallbackHouse: 'Commons',
      );

      expect(period!.description, 'Recess');
      expect(period.house, 'Commons');
      // Missing end date yields a single-day period.
      expect(period.endDate, period.startDate);
    });

    test('returns null without a parsable start date', () {
      expect(RecessPeriod.fromApiJson({'Description': 'X'}), isNull);
      expect(
        RecessPeriod.fromApiJson({'StartDate': 'not-a-date'}),
        isNull,
      );
    });

    test('clamps an inverted range to a single-day period', () {
      final period = RecessPeriod.fromApiJson({
        'StartDate': '2024-09-02T00:00:00',
        'EndDate': '2024-07-30T00:00:00',
      });

      expect(period!.startDate, DateTime(2024, 9, 2));
      expect(period.endDate, DateTime(2024, 9, 2));
    });
  });

  group('RecessPeriod.contains', () {
    final period = RecessPeriod(
      description: 'Summer recess',
      startDate: DateTime(2024, 7, 30),
      endDate: DateTime(2024, 9, 2),
    );

    test('is inclusive of both endpoints', () {
      expect(period.contains(DateTime(2024, 7, 29)), isFalse);
      expect(period.contains(DateTime(2024, 7, 30)), isTrue);
      expect(period.contains(DateTime(2024, 8, 15)), isTrue);
      expect(period.contains(DateTime(2024, 9, 2)), isTrue);
      expect(period.contains(DateTime(2024, 9, 3)), isFalse);
    });

    test('ignores any time component on the queried day', () {
      expect(period.contains(DateTime(2024, 9, 2, 23, 59)), isTrue);
    });
  });
}
