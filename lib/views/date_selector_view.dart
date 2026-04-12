import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../viewmodels/date_selector_viewmodel.dart';
import 'settings_view.dart';
import 'transcript_view.dart';

/// The redesigned landing screen for the app's main page.
class DateSelectorView extends StatefulWidget {
  const DateSelectorView({super.key});

  @override
  State<DateSelectorView> createState() => _DateSelectorViewState();
}

class _DateSelectorViewState extends State<DateSelectorView> {
  late DateSelectorViewModel _vm;

  static final DateTime _minDate = DateTime(2000, 1, 1);
  static const int _averageWordsPerMinute = 130;
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
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsView()),
          ),
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
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      if (item.house.isNotEmpty) ...[
                        _HousePill(item.house),
                        const SizedBox(width: 6),
                      ],
                      Text(item.durationLabel),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _navigateToTranscript(day, debateId: item.debateId),
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

  Future<List<_DebateFeedItem>> _loadDebatesFeed(
    DateSelectorViewModel vm,
    DateTime day,
  ) async {
    final service = context.read<ParliamentaryDataService>();
    final date = DateSelectorViewModel.formatDate(day);
    try {
      final speechesFuture = service.getSpeeches(date);
      final debatesFuture = service.getDebatesForDate(date);

      final speeches = await speechesFuture;
      final debates = await debatesFuture;

      // Build root debate lookups from the debates table.
      final rootIds = {for (final d in debates) d.id};
      final houseByDebateId = {for (final d in debates) d.id: d.house};
      final titleByDebateId = {for (final d in debates) d.id: d.title};
      final orderByDebateId = {for (final d in debates) d.id: d.orderIndex};

      // Group speeches by root debate — sub-section speeches inherit the
      // most recently seen root debate ID.
      final wordCountsByDebateId = <String, int>{};
      String? currentRoot;
      for (final speech in speeches) {
        if (rootIds.contains(speech.debateId)) {
          currentRoot = speech.debateId;
        }
        if (currentRoot == null) continue;
        wordCountsByDebateId[currentRoot] =
            (wordCountsByDebateId[currentRoot] ?? 0) +
                _wordCount(speech.speechText);
      }

      if (wordCountsByDebateId.isEmpty) {
        // No speeches yet — fall back to showing debate titles with no duration.
        return debates
            .map((d) => _DebateFeedItem(
                  debateId: d.id,
                  title: d.title,
                  durationMinutes: 0,
                  house: d.house,
                  order: d.orderIndex,
                ))
            .toList();
      }

      final items = wordCountsByDebateId.entries
          .map(
            (entry) => _DebateFeedItem(
              debateId: entry.key,
              title: titleByDebateId[entry.key] ?? '',
              durationMinutes: _minutesFromWords(entry.value),
              house: houseByDebateId[entry.key] ?? '',
              order: orderByDebateId[entry.key] ?? 0,
            ),
          )
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      return items;
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

  static int _wordCount(String text) {
    return _wordRegex.allMatches(text).length;
  }

  static int _minutesFromWords(int words) {
    return (words / _averageWordsPerMinute)
        .round()
        .clamp(1, _maxDurationMinutes);
  }

  void _navigateToTranscript(DateTime day, {String debateId = ''}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TranscriptView(
          date: DateSelectorViewModel.formatDate(day),
          displayDate: _friendlyDate(day),
          initialDebateId: debateId.isNotEmpty ? debateId : null,
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

/// Small colored pill showing "Commons" or "Lords" on debate feed cards.
class _HousePill extends StatelessWidget {
  final String house;

  const _HousePill(this.house);

  @override
  Widget build(BuildContext context) {
    final h = house.toLowerCase();
    final color = (h.contains('lords') || h.contains('grand committee'))
        ? const Color(0xFFB50938)
        : (h.contains('westminster hall'))
            ? const Color(0xFF006548)
            : (h.contains('committee'))
                ? const Color(0xFF1A5276)
                : const Color(0xFF006548); // Commons default

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        house,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _DebateFeedItem {
  final String title;
  final int durationMinutes;
  final String house;
  final String debateId;
  final int order;

  const _DebateFeedItem({
    required this.title,
    required this.durationMinutes,
    this.house = '',
    this.debateId = '',
    this.order = 0,
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
