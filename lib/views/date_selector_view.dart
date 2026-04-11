import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../viewmodels/date_selector_viewmodel.dart';
import 'transcript_view.dart';

/// The redesigned landing screen for the app's main page.
class DateSelectorView extends StatefulWidget {
  const DateSelectorView({super.key});

  @override
  State<DateSelectorView> createState() => _DateSelectorViewState();
}

class _DateSelectorViewState extends State<DateSelectorView> {
  late DateSelectorViewModel _vm;

  static const Color _pulseMaxColor = Color(0xFF005EA5);
  static const Color _pulseMinColor = Color(0xFFE2E5EA);
  static const DateTime _minDate = DateTime(2000, 1, 1);
  static const int _averageWordsPerMinute = 130;
  static const int _maxDebateItems = 8;
  static const int _maxDurationMinutes = 24 * 60;
  static final RegExp _wordRegex = RegExp(r'\S+');

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
          final selectedDay = vm.selectedDay ?? vm.focusedDay;
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(context),
                    const SizedBox(height: 20),
                    _buildActivityPulse(context, vm, selectedDay),
                    const SizedBox(height: 16),
                    _buildContextualDateSelector(context, vm, selectedDay),
                    const SizedBox(height: 20),
                    Text(
                      'Today’s Key Debates',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildDebatesFeed(vm, selectedDay),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.public_outlined, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'ParliamentPulse',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const Icon(Icons.account_circle_outlined, size: 24),
      ],
    );
  }

  Widget _buildActivityPulse(
    BuildContext context,
    DateSelectorViewModel vm,
    DateTime anchorDate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chamber Activity Pulse',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<int>>(
          future: _loadActivityWordCounts(vm, anchorDate),
          builder: (context, snapshot) {
            final values = snapshot.data ?? List<int>.filled(28, 0);
            final maxValue = values.fold<int>(0, (a, b) => a > b ? a : b);
            return Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: values.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final value = values[index];
                    final intensity = value == 0 || maxValue == 0
                        ? 0.0
                        : value / maxValue;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: value == 0
                            ? _pulseMinColor
                            : Color.lerp(_pulseMinColor, _pulseMaxColor, intensity),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Low',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_right_alt, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'High',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildContextualDateSelector(
    BuildContext context,
    DateSelectorViewModel vm,
    DateTime selectedDay,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final canMoveForward = !selectedDay.isAtSameMomentAs(today);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftBySittingDay(vm, selectedDay, -1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _navigateToTranscript(selectedDay),
              child: Text(
                _friendlyDate(selectedDay),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () => _pickDate(vm, selectedDay),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canMoveForward
                ? () => _shiftBySittingDay(vm, selectedDay, 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDebatesFeed(DateSelectorViewModel vm, DateTime day) {
    return FutureBuilder<List<_DebateFeedItem>>(
      future: _loadDebatesFeed(vm, day),
      builder: (context, snapshot) {
        final items = snapshot.data ?? _fallbackDebates();
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.durationLabel),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _navigateToTranscript(day),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickDate(DateSelectorViewModel vm, DateTime selectedDay) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDay,
      firstDate: _minDate,
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;

    var adjusted = DateTime(picked.year, picked.month, picked.day);
    var guard = 0;
    while (!vm.isSittingDay(adjusted) &&
        adjusted.isAfter(_minDate) &&
        guard < 14) {
      adjusted = adjusted.subtract(const Duration(days: 1));
      guard++;
    }
    if (!vm.isSittingDay(adjusted)) return;
    vm.setFocusedDay(adjusted);
    vm.selectDay(adjusted);
  }

  void _shiftBySittingDay(DateSelectorViewModel vm, DateTime current, int deltaDays) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var next = current;
    var guard = 0;
    do {
      next = next.add(Duration(days: deltaDays));
      guard++;
    } while (!vm.isSittingDay(next) && next.isAfter(_minDate) && guard < 14);

    if (next.isAfter(today) || !vm.isSittingDay(next)) return;
    vm.setFocusedDay(next);
    vm.selectDay(next);
  }

  Future<List<int>> _loadActivityWordCounts(
    DateSelectorViewModel vm,
    DateTime anchorDate,
  ) async {
    final service = context.read<ParliamentaryDataService>();
    final days = _last28Days(anchorDate);
    return Future.wait(days.map((day) async {
      if (!vm.isSittingDay(day)) {
        return 0;
      }
      final date = DateSelectorViewModel.formatDate(day);
      final isCached = await vm.isCached(day);
      if (!isCached) {
        return 0;
      }

      try {
        final speeches = await service.getSpeeches(date);
        return speeches.fold<int>(
          0,
          (sum, speech) => sum + _wordCount(speech.speechText),
        );
      } catch (_) {
        return 0;
      }
    }));
  }

  Future<List<_DebateFeedItem>> _loadDebatesFeed(
    DateSelectorViewModel vm,
    DateTime day,
  ) async {
    final service = context.read<ParliamentaryDataService>();
    final isCached = await vm.isCached(day);
    if (!isCached) {
      return _fallbackDebates();
    }

    final date = DateSelectorViewModel.formatDate(day);
    try {
      final speeches = await service.getSpeeches(date);
      final wordCountsByDebate = <String, int>{};
      for (final speech in speeches) {
        final title = speech.debateTitle.trim().isEmpty
            ? 'Untitled Parliamentary Debate'
            : speech.debateTitle.trim();
        wordCountsByDebate[title] =
            (wordCountsByDebate[title] ?? 0) + _wordCount(speech.speechText);
      }

      if (wordCountsByDebate.isEmpty) {
        return _fallbackDebates();
      }

      final items = wordCountsByDebate.entries
          .map(
            (entry) => _DebateFeedItem(
              title: entry.key,
              durationMinutes: _minutesFromWords(entry.value),
            ),
          )
          .toList()
        ..sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));

      return items.take(_maxDebateItems).toList();
    } catch (_) {
      return _fallbackDebates();
    }
  }

  List<_DebateFeedItem> _fallbackDebates() {
    return const [
      _DebateFeedItem(
        title: 'Healthcare Reform Bill: Second Reading',
        durationMinutes: 195,
      ),
      _DebateFeedItem(
        title: 'National Infrastructure and Transport Funding',
        durationMinutes: 160,
      ),
      _DebateFeedItem(
        title: 'Education Standards and School Accountability',
        durationMinutes: 115,
      ),
      _DebateFeedItem(
        title: 'Energy Security and Household Costs',
        durationMinutes: 90,
      ),
    ];
  }

  static List<DateTime> _last28Days(DateTime anchor) {
    final end = DateTime(anchor.year, anchor.month, anchor.day);
    return List<DateTime>.generate(28, (index) {
      final daysAgo = 27 - index;
      return end.subtract(Duration(days: daysAgo));
    });
  }

  static int _wordCount(String text) {
    return _wordRegex.allMatches(text).length;
  }

  static int _minutesFromWords(int words) {
    return (words / _averageWordsPerMinute)
        .round()
        .clamp(1, _maxDurationMinutes);
  }

  static String _durationLabelFromMinutes(int minutes) {
    final hoursPart = minutes ~/ 60;
    final minutesPart = minutes % 60;
    if (hoursPart == 0) return '${minutesPart}m';
    if (minutesPart == 0) return '${hoursPart}h';
    return '${hoursPart}h ${minutesPart}m';
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

class _DebateFeedItem {
  final String title;
  final int durationMinutes;

  const _DebateFeedItem({
    required this.title,
    required this.durationMinutes,
  });

  String get durationLabel =>
      _DateSelectorViewState._durationLabelFromMinutes(durationMinutes);
}
