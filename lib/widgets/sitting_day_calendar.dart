import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../viewmodels/date_selector_viewmodel.dart';

/// A month-view calendar, shown as a modal bottom sheet, in which only days
/// that actually have debates (sitting days) are selectable. Non-sitting days
/// and future days are greyed out and cannot be tapped; days falling inside a
/// named recess (e.g. summer recess, Christmas adjournment) get a distinct
/// tint, with a legend under the grid naming the recess(es) in view.
///
/// Tapping an enabled day pops the sheet, returning that [DateTime]. Dismissing
/// the sheet returns `null`. The set of enabled days for the visible month is
/// loaded lazily via [DateSelectorViewModel.sittingDaysInMonth] (recess labels
/// via [DateSelectorViewModel.recessDaysInMonth]); a spinner covers the first
/// load of each month (cached months render instantly).
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
  Map<DateTime, String> _recessDays = <DateTime, String>{};
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
    // Kick both loads off together; each failure degrades independently
    // (no sitting days / no recess labels) rather than blanking the sheet.
    final daysFuture = widget.viewModel.sittingDaysInMonth(month);
    final recessFuture = widget.viewModel.recessDaysInMonth(month);
    Set<DateTime> days;
    Map<DateTime, String> recessDays;
    try {
      days = await daysFuture;
    } catch (_) {
      days = <DateTime>{};
    }
    try {
      recessDays = await recessFuture;
    } catch (_) {
      recessDays = <DateTime, String>{};
    }
    if (!mounted) return;
    setState(() {
      _enabledDays = days;
      _recessDays = recessDays;
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

  /// The recess name covering [day], or `null` when it isn't in a recess.
  String? _recessLabelFor(DateTime day) =>
      _recessDays[DateTime(day.year, day.month, day.day)];

  /// The distinct recess names visible in the focused month, in date order.
  List<String> _visibleRecessNames() {
    final ordered = _recessDays.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final names = <String>[];
    for (final entry in ordered) {
      if (!names.contains(entry.value)) names.add(entry.value);
    }
    return names;
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
    // Recess days stay non-tappable but are grouped by a soft tertiary tint
    // so a holiday reads as one block rather than scattered "missing" days.
    final recessFill = scheme.tertiaryContainer.withValues(alpha: 0.4);
    final recessTextColor = scheme.onTertiaryContainer.withValues(alpha: 0.55);
    final recessNames = _visibleRecessNames();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
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
                    outsideTextStyle: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.18)),
                  ),
                  calendarBuilders: CalendarBuilders(
                    // Recess days are always disabled (no sittings), so this
                    // only needs to restyle the disabled cell; returning null
                    // falls back to the default disabled rendering.
                    disabledBuilder: (context, day, focusedDay) {
                      if (_recessLabelFor(day) == null) return null;
                      return Container(
                        margin: const EdgeInsets.all(6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: recessFill,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(color: recessTextColor),
                        ),
                      );
                    },
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
                if (recessNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final name in recessNames)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: recessFill,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
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
