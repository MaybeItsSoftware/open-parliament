import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:open_hansard/viewmodels/date_selector_viewmodel.dart';
import 'package:open_hansard/widgets/sitting_day_calendar.dart';
import 'package:table_calendar/table_calendar.dart';

/// A service stand-in: the calendar only ever calls `sittingDaysInMonth` on the
/// view-model (overridden below), so the service is never touched.
class _NoopService implements ParliamentaryDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A view-model whose `sittingDaysInMonth` / `recessDaysInMonth` return fixed
/// values, so the widget renders deterministically without any network or
/// async walk.
class _StubViewModel extends DateSelectorViewModel {
  final Set<DateTime> days;
  final Map<DateTime, String> recessDays;

  _StubViewModel(this.days, {this.recessDays = const {}})
      : super(_NoopService());

  @override
  Future<Set<DateTime>> sittingDaysInMonth(DateTime month) async => days;

  @override
  Future<Map<DateTime, String>> recessDaysInMonth(DateTime month) async =>
      recessDays;
}

void main() {
  Future<DateTime?> openCalendar(
    WidgetTester tester,
    _StubViewModel vm,
  ) async {
    DateTime? result;
    var captured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<DateTime>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SittingDayCalendar(
                    viewModel: vm,
                    initialMonth: DateTime(2024, 11),
                    selectedDay: DateTime(2024, 11, 4),
                    lastDay: DateTime(2025, 1, 1),
                  ),
                );
                captured = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return captured ? result : null;
  }

  testWidgets('renders the initial month after loading', (tester) async {
    final vm = _StubViewModel({DateTime(2024, 11, 4), DateTime(2024, 11, 5)});
    await openCalendar(tester, vm);

    expect(find.byType(TableCalendar<void>), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('November 2024'), findsOneWidget);
  });

  testWidgets('tapping an enabled sitting day returns it', (tester) async {
    final vm = _StubViewModel({DateTime(2024, 11, 4), DateTime(2024, 11, 5)});
    DateTime? result;
    var captured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<DateTime>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SittingDayCalendar(
                    viewModel: vm,
                    initialMonth: DateTime(2024, 11),
                    selectedDay: DateTime(2024, 11, 4),
                    lastDay: DateTime(2025, 1, 1),
                  ),
                );
                captured = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(captured, isTrue);
    expect(result, DateTime(2024, 11, 5));
  });

  testWidgets('sitting and non-sitting days are visibly distinct',
      (tester) async {
    // Only the 6th sits; the 4th (selected) and others do not.
    final vm = _StubViewModel({DateTime(2024, 11, 6)});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SittingDayCalendar(
            viewModel: vm,
            initialMonth: DateTime(2024, 11),
            selectedDay: null,
            lastDay: DateTime(2025, 1, 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sitting = tester.widget<Text>(find.text('6')); // enabled
    final nonSitting = tester.widget<Text>(find.text('7')); // disabled

    // Sitting day is full-weight; non-sitting is faded well below full opacity.
    expect(sitting.style?.fontWeight, FontWeight.w600);
    expect(sitting.style?.color, isNot(nonSitting.style?.color));
    expect(nonSitting.style?.color?.a, lessThan(0.5));
    expect(sitting.style?.color?.a, 1.0);
  });

  testWidgets('tapping a non-sitting day does nothing', (tester) async {
    final vm = _StubViewModel({DateTime(2024, 11, 4)});
    DateTime? result;
    var captured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<DateTime>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SittingDayCalendar(
                    viewModel: vm,
                    initialMonth: DateTime(2024, 11),
                    selectedDay: DateTime(2024, 11, 4),
                    lastDay: DateTime(2025, 1, 1),
                  ),
                );
                captured = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The 6th is not a sitting day, so the sheet stays open.
    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();

    expect(captured, isFalse);
    expect(result, isNull);
    expect(find.byType(TableCalendar<void>), findsOneWidget);
  });

  testWidgets('recess days are marked distinctly and named in a legend',
      (tester) async {
    // The 4th sits; the 11th–15th are a recess; the 7th is plain non-sitting.
    final vm = _StubViewModel(
      {DateTime(2024, 11, 4)},
      recessDays: {
        for (var d = 11; d <= 15; d++)
          DateTime(2024, 11, d): 'November recess',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SittingDayCalendar(
            viewModel: vm,
            initialMonth: DateTime(2024, 11),
            selectedDay: null,
            lastDay: DateTime(2025, 1, 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The legend names the recess visible in this month.
    expect(find.text('November recess'), findsOneWidget);

    // A recess day is styled unlike both a sitting day and a plain
    // non-sitting day.
    final sitting = tester.widget<Text>(find.text('4'));
    final nonSitting = tester.widget<Text>(find.text('7'));
    final recess = tester.widget<Text>(find.text('12'));
    expect(recess.style?.color, isNot(sitting.style?.color));
    expect(recess.style?.color, isNot(nonSitting.style?.color));
  });

  testWidgets('tapping a recess day does nothing', (tester) async {
    final vm = _StubViewModel(
      {DateTime(2024, 11, 4)},
      recessDays: {DateTime(2024, 11, 12): 'November recess'},
    );
    DateTime? result;
    var captured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<DateTime>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SittingDayCalendar(
                    viewModel: vm,
                    initialMonth: DateTime(2024, 11),
                    selectedDay: DateTime(2024, 11, 4),
                    lastDay: DateTime(2025, 1, 1),
                  ),
                );
                captured = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();

    expect(captured, isFalse);
    expect(result, isNull);
    expect(find.byType(TableCalendar<void>), findsOneWidget);
  });
}
