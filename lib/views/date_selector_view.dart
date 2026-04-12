import 'dart:async';

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
  DateTime? _lastPulseAnchorDate;
  int _pulseSlideDirection = 1;

  static const Color _pulseMaxColor = Color(0xFF005EA5);
  static const Color _pulseMinColor = Color(0xFFE2E5EA);
  static final DateTime _minDate = DateTime(2000, 1, 1);
  static const int _averageWordsPerMinute = 130;
  static const int _maxDebateItems = 8;
  static const int _maxDurationMinutes = 24 * 60;
  static final RegExp _wordRegex = RegExp(r'\S+');

  @override
  void initState() {
    super.initState();
    final service = context.read<ParliamentaryDataService>();
    _vm = DateSelectorViewModel(service);
    unawaited(_initializeLandingDay());
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _initializeLandingDay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final latestDay = await _vm.mostRecentSittingDay(today);
    if (latestDay == null) return;
    _vm.setFocusedDay(latestDay);
    _vm.selectDay(latestDay);
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth =
                      constraints.maxWidth >= 1200 ? 1080.0 : 900.0;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(context),
                            const SizedBox(height: 20),
                            _buildActivityPulse(context, vm, selectedDay),
                            const SizedBox(height: 16),
                            _buildContextualDateSelector(
                              context,
                              vm,
                              selectedDay,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Today’s Key Debates',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
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
            'Open Hansard',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityPulse(
    BuildContext context,
    DateSelectorViewModel vm,
    DateTime anchorDate,
  ) {
    _updatePulseDirection(anchorDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chamber Activity Pulse',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        Text(
          'Last 7 days',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<int>>(
          future: _loadActivityWordCounts(vm, anchorDate),
          builder: (context, snapshot) {
            final values = snapshot.data ?? List<int>.filled(7, 0);
            final maxValue = values.fold<int>(0, (a, b) => a > b ? a : b);
            return Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final beginOffset = Offset(
                      0.25 * _pulseSlideDirection,
                      0,
                    );
                    final slide = Tween<Offset>(
                      begin: beginOffset,
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: _buildPulseGrid(
                    values: values,
                    maxValue: maxValue,
                    key: ValueKey(DateSelectorViewModel.formatDate(anchorDate)),
                  ),
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

  void _updatePulseDirection(DateTime anchorDate) {
    final normalized =
        DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
    final last = _lastPulseAnchorDate;
    if (last != null) {
      if (normalized.isAfter(last)) {
        _pulseSlideDirection = 1;
      } else if (normalized.isBefore(last)) {
        _pulseSlideDirection = -1;
      }
    }
    _lastPulseAnchorDate = normalized;
  }

  Widget _buildPulseGrid({
    required List<int> values,
    required int maxValue,
    required Key key,
  }) {
    return GridView.builder(
      key: key,
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
        final intensity = value == 0 || maxValue == 0 ? 0.0 : value / maxValue;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: value == 0
                ? _pulseMinColor
                : Color.lerp(_pulseMinColor, _pulseMaxColor, intensity),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
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
            onPressed: () => unawaited(_shiftBySittingDay(vm, selectedDay, -1)),
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
                ? () => unawaited(_shiftBySittingDay(vm, selectedDay, 1))
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? const <_DebateFeedItem>[];
        if (items.isEmpty) {
          return _buildNoDebatesCard(day);
        }

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

    final chosenDay = DateTime(picked.year, picked.month, picked.day);
    final nearest = await vm.nearestSittingDay(chosenDay);
    if (nearest == null) {
      if (!mounted) return;
      _showInfoMessage('Parliament appears to be in recess around this date.');
      return;
    }
    vm.setFocusedDay(nearest);
    vm.selectDay(nearest);

    if (!mounted) return;
    if (!nearest.isAtSameMomentAs(chosenDay)) {
      _showInfoMessage(
        'No sitting on ${_friendlyDate(chosenDay)}. Showing ${_friendlyDate(nearest)} instead.',
      );
    }
  }

  Future<void> _shiftBySittingDay(
    DateSelectorViewModel vm,
    DateTime current,
    int deltaDays,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = deltaDays < 0
        ? await vm.previousSittingDay(current)
        : await vm.nextSittingDay(current);

    if (next == null) {
      if (!mounted) return;
      _showInfoMessage('No more sitting dates available in that direction.');
      return;
    }

    if (next.isAfter(today)) return;
    vm.setFocusedDay(next);
    vm.selectDay(next);
  }

  Future<List<int>> _loadActivityWordCounts(
    DateSelectorViewModel vm,
    DateTime anchorDate,
  ) async {
    final service = context.read<ParliamentaryDataService>();
    final days = _last7Days(anchorDate);
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
        return const <_DebateFeedItem>[];
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
      return const <_DebateFeedItem>[];
    }
  }

  Widget _buildNoDebatesCard(DateTime day) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No debates are available for ${_friendlyDate(day)}.\n'
            'Parliament may be in recess.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  void _showInfoMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static List<DateTime> _last7Days(DateTime anchor) {
    final end = DateTime(anchor.year, anchor.month, anchor.day);
    return List<DateTime>.generate(7, (index) {
      final daysAgo = 6 - index;
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
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
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

  String get durationLabel => _durationLabelFromMinutes(durationMinutes);

  static String _durationLabelFromMinutes(int minutes) {
    final hoursPart = minutes ~/ 60;
    final minutesPart = minutes % 60;
    if (hoursPart == 0) return '${minutesPart}m';
    if (minutesPart == 0) return '${hoursPart}h';
    return '${hoursPart}h ${minutesPart}m';
  }
}
