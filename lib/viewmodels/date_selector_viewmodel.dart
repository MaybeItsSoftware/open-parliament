import 'package:flutter/foundation.dart';

import '../services/parliamentary_data_service.dart';

/// View-model for [DateSelectorView].
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
