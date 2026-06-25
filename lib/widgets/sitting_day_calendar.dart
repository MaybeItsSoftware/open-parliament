import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../viewmodels/date_selector_viewmodel.dart';

/// A month-view calendar, shown as a modal bottom sheet, in which only days
/// that actually have debates (sitting days) are selectable. Non-sitting days,
/// future days, and recess are greyed out and cannot be tapped.
///
/// Tapping an enabled day pops the sheet, returning that [DateTime]. Dismissing
/// the sheet returns `null`. The set of enabled days for the visible month is
/// loaded lazily via [DateSelectorViewModel.sittingDaysInMonth]; a spinner
/// covers the first load of each month (cached months render instantly).
class SittingDayCalendar extends StatefulWidget {
  final DateSelectorViewModel viewModel;

  /// The month to open on (any day within it; only the year/month are used).
  final DateTime initialMonth;

  /// The currently selected day, highlighted in the grid (may be `null`).
  final DateTime? selectedDay;

  /// The latest selectable/visible day — today. Paging and selection never go
  /// beyond this.
  final DateTime lastDay;

  const SittingDayCalendar({
    super.key,
    required this.viewModel,
    required this.initialMonth,
    required this.selectedDay,
    required this.lastDay,
  });

  @override
  State<SittingDayCalendar> createState() => _SittingDayCalendarState();
}

class _SittingDayCalendarState extends State<SittingDayCalendar> {
  static final DateTime _firstDay = DateTime(2000, 1, 1);

  late DateTime _focusedMonth;
  Set<DateTime> _enabledDays = <DateTime>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(
      widget.initialMonth.year,
      widget.initialMonth.month,
    );
    unawaited(_loadMonth(_focusedMonth));
  }

  Future<void> _loadMonth(DateTime month) async {
    setState(() => _loading = true);
    Set<DateTime> days;
    try {
      days = await widget.viewModel.sittingDaysInMonth(month);
    } catch (_) {
      days = <DateTime>{};
    }
    if (!mounted) return;
    setState(() {
      _enabledDays = days;
      _loading = false;
    });
  }

  /// Keeps the focused day within the `firstDay`..`lastDay` range that
  /// TableCalendar asserts. When the focused month is the current month, the
  /// 1st is fine; we only need to guard the upper bound.
  DateTime _clampedFocusedDay() {
    final candidate = _focusedMonth;
    if (candidate.isAfter(widget.lastDay)) return widget.lastDay;
    if (candidate.isBefore(_firstDay)) return _firstDay;
    return candidate;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Sitting days get a solid, clearly-visible pill so they read as the only
    // tappable cells; non-sitting days are faded hard to recede into the grid.
    final sittingTextStyle = TextStyle(
      color: scheme.onPrimaryContainer,
      fontWeight: FontWeight.w600,
    );
    final sittingDecoration = BoxDecoration(
      color: scheme.primaryContainer,
      shape: BoxShape.circle,
    );
    final disabledColor = scheme.onSurface.withValues(alpha: 0.28);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            TableCalendar<void>(
              firstDay: _firstDay,
              lastDay: widget.lastDay,
              focusedDay: _clampedFocusedDay(),
              currentDay: widget.lastDay,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableGestures: AvailableGestures.horizontalSwipe,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarStyle: CalendarStyle(
                // Sitting days: solid pill, full-strength label.
                defaultTextStyle: sittingTextStyle,
                defaultDecoration: sittingDecoration,
                weekendTextStyle: sittingTextStyle,
                weekendDecoration: sittingDecoration,
                // Non-sitting days: strongly faded, no fill.
                disabledTextStyle: TextStyle(color: disabledColor),
                outsideTextStyle:
                    TextStyle(color: scheme.onSurface.withValues(alpha: 0.18)),
              ),
              selectedDayPredicate: (day) =>
                  widget.selectedDay != null &&
                  isSameDay(day, widget.selectedDay),
              enabledDayPredicate: (day) {
                final d = DateTime(day.year, day.month, day.day);
                if (d.isAfter(widget.lastDay)) return false;
                return _enabledDays.any((e) => isSameDay(e, d));
              },
              onDaySelected: (selectedDay, _) {
                Navigator.of(context).pop(
                  DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day,
                  ),
                );
              },
              onPageChanged: (focusedDay) {
                _focusedMonth = DateTime(focusedDay.year, focusedDay.month);
                unawaited(_loadMonth(_focusedMonth));
              },
            ),
            if (_loading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x11000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
