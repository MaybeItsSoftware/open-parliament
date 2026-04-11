import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../services/parliamentary_data_service.dart';
import '../viewmodels/date_selector_viewmodel.dart';
import 'transcript_view.dart';

/// The landing screen of Open Hansard.
///
/// Displays a [TableCalendar] that lets the user select a Parliamentary sitting
/// day.  Weekends are disabled since Parliament does not sit on those days.
/// Below the calendar, a scrollable list of cached (recently viewed) sitting
/// days is shown for quick navigation.
class DateSelectorView extends StatefulWidget {
  const DateSelectorView({super.key});

  @override
  State<DateSelectorView> createState() => _DateSelectorViewState();
}

class _DateSelectorViewState extends State<DateSelectorView> {
  late DateSelectorViewModel _vm;

  @override
  void initState() {
    super.initState();
    final service = context.read<ParliamentaryDataService>();
    _vm = DateSelectorViewModel(service);
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<DateSelectorViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Open Hansard'),
              centerTitle: true,
            ),
            body: Column(
              children: [
                _buildCalendar(vm),
                const Divider(height: 1),
                Expanded(child: _buildRecentDaysList(vm)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendar(DateSelectorViewModel vm) {
    return TableCalendar(
      firstDay: DateTime(2000),
      lastDay: DateTime.now(),
      focusedDay: vm.focusedDay,
      selectedDayPredicate: (day) => isSameDay(day, vm.selectedDay),
      enabledDayPredicate: (day) => vm.isSittingDay(day),
      calendarFormat: CalendarFormat.month,
      headerStyle: const HeaderStyle(formatButtonVisible: false),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(100),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        disabledTextStyle: const TextStyle(color: Colors.grey),
      ),
      onDaySelected: (selectedDay, focusedDay) {
        vm.selectDay(selectedDay);
        vm.setFocusedDay(focusedDay);
        _navigateToTranscript(selectedDay);
      },
      onPageChanged: vm.setFocusedDay,
    );
  }

  /// A list of the most recent Parliamentary sitting days (Mon–Fri, up to 20).
  Widget _buildRecentDaysList(DateSelectorViewModel vm) {
    final today = DateTime.now();
    final recentDays = _recentSittingDays(today, count: 20);

    return ListView.separated(
      itemCount: recentDays.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        final day = recentDays[index];
        final dateStr = DateSelectorViewModel.formatDate(day);
        return FutureBuilder<bool>(
          future: vm.isCached(day),
          builder: (context, snapshot) {
            final isCached = snapshot.data ?? false;
            return ListTile(
              leading: Icon(
                isCached ? Icons.check_circle : Icons.circle_outlined,
                color: isCached
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: Text(_friendlyDate(day)),
              subtitle: Text(dateStr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                vm.selectDay(day);
                _navigateToTranscript(day);
              },
            );
          },
        );
      },
    );
  }

  void _navigateToTranscript(DateTime day) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TranscriptView(
          date: DateSelectorViewModel.formatDate(day),
          displayDate: _friendlyDate(day),
        ),
      ),
    );
  }

  /// Returns [count] most-recent weekdays on or before [from].
  static List<DateTime> _recentSittingDays(DateTime from, {required int count}) {
    final days = <DateTime>[];
    var current = DateTime(from.year, from.month, from.day);
    while (days.length < count) {
      if (current.weekday >= DateTime.monday &&
          current.weekday <= DateTime.friday) {
        days.add(current);
      }
      current = current.subtract(const Duration(days: 1));
    }
    return days;
  }

  /// Returns a human-readable date string like "Monday, 1 November 2024".
  static String _friendlyDate(DateTime day) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
      'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[day.weekday - 1]}, ${day.day} '
        '${months[day.month - 1]} ${day.year}';
  }
}
