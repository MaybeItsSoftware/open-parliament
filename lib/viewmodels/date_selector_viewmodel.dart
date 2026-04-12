import 'package:flutter/foundation.dart';

import '../services/parliamentary_data_service.dart';

/// View-model backing the date selector screen.
///
/// Provides the set of sitting days that are available to browse and tracks
/// the currently selected date.
class DateSelectorViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  DateSelectorViewModel(this._service);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// The day currently displayed in the calendar widget.
  DateTime get focusedDay => _focusedDay;

  /// The day the user has tapped (may be `null` before any selection).
  DateTime? get selectedDay => _selectedDay;

  /// Whether [day] has already been fetched and cached locally.
  Future<bool> isCached(DateTime day) =>
      _service.isSittingCached(_formatDate(day));

  /// Returns true if Hansard has sitting data for [day].
  Future<bool> hasSittingData(DateTime day) =>
      _service.hasSittingData(_formatDate(day));

  /// Returns the closest previous parliamentary sitting day.
  Future<DateTime?> previousSittingDay(DateTime day) =>
      _service.getPreviousSittingDate(_formatDate(day));

  /// Returns the closest next parliamentary sitting day.
  Future<DateTime?> nextSittingDay(DateTime day) =>
      _service.getNextSittingDate(_formatDate(day));

  /// Returns [day] if it has data, otherwise the nearest available sitting day.
  Future<DateTime?> nearestSittingDay(DateTime day) async {
    if (await hasSittingData(day)) {
      return DateTime(day.year, day.month, day.day);
    }

    final previous = await previousSittingDay(day);
    final next = await nextSittingDay(day);

    if (previous == null) return next;
    if (next == null) return previous;

    final distanceToPrevious = day.difference(previous).inDays.abs();
    final distanceToNext = next.difference(day).inDays.abs();
    return distanceToPrevious <= distanceToNext ? previous : next;
  }

  /// Returns the latest sitting day on or before [day] that has debates.
  Future<DateTime?> mostRecentSittingDay(DateTime day) async {
    final normalized = DateTime(day.year, day.month, day.day);
    if (await hasSittingData(normalized)) {
      return normalized;
    }
    return previousSittingDay(normalized);
  }

  void setFocusedDay(DateTime day) {
    _focusedDay = day;
    notifyListeners();
  }

  void selectDay(DateTime day) {
    _selectedDay = day;
    notifyListeners();
  }

  /// Returns true if [day] is a weekday (Mon–Fri), which is the only time
  /// Parliament sits. This is used to disable weekends in the calendar.
  bool isSittingDay(DateTime day) {
    return day.weekday >= DateTime.monday && day.weekday <= DateTime.friday;
  }

  /// Formats [day] as `YYYY-MM-DD` for use with the API and database.
  static String formatDate(DateTime day) => _formatDate(day);

  static String _formatDate(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
