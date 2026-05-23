import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/debate.dart';
import '../models/speech.dart';
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
  static const double _minDebateCardHeight = 72;
  static const double _pixelsPerMinute = 3.5;
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsView()),
            ),
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
            return SizedBox(
              height: _debateCardHeight(item.durationMinutes),
              child: _HouseAccentCard(
                house: item.house,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _navigateToTranscript(day, debateId: item.debateId),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _debateCardHeight(int minutes) {
    final clampedMinutes = minutes <= 0 ? 1 : minutes;
    final scaled = clampedMinutes * _pixelsPerMinute;
    return scaled < _minDebateCardHeight
        ? _minDebateCardHeight
        : scaled;
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
      final sectionByDebateId = {for (final d in debates) d.id: d.section};

      // Group speeches by root debate — sub-section speeches inherit the
      // most recently seen root debate ID.
      final wordCountsByDebateId = <String, int>{};
      final firstTimecodeByDebateId = <String, String>{};
      final hasMeaningfulSpeechByRoot = <String, bool>{};
      String? currentRoot;
      for (final speech in speeches) {
        if (rootIds.contains(speech.debateId)) {
          currentRoot = speech.debateId;
        }
        if (currentRoot == null) continue;
        final timecode = _normalizedHansardTimecode(speech.timecode) ??
            (speech.isTimestamp
                ? _normalizedHansardTimecode(speech.speechText)
                : null);
        if (timecode != null) {
          firstTimecodeByDebateId.putIfAbsent(currentRoot, () => timecode);
        }
        wordCountsByDebateId[currentRoot] =
            (wordCountsByDebateId[currentRoot] ?? 0) +
                _wordCount(speech.speechText);
        if (_isMeaningfulSpeech(speech)) {
          hasMeaningfulSpeechByRoot[currentRoot] = true;
        }
      }

      // Drop debates whose only content is the "House met at …" boilerplate.
      final placeholderRoots = <String>{
        for (final d in debates)
          if (_isPlaceholderDebate(d, hasMeaningfulSpeechByRoot[d.id] ?? false))
            d.id,
      };

      if (wordCountsByDebateId.isEmpty) {
        // No speeches yet — fall back to debate titles, still filtering out
        // placeholders detectable from the title alone.
        return debates
            .where((d) => !placeholderRoots.contains(d.id))
            .map((d) => _DebateFeedItem(
                  debateId: d.id,
                  title: d.title,
                  durationMinutes: 0,
                  house: d.house,
                  order: d.orderIndex,
                  section: d.section,
                  startTimecode: firstTimecodeByDebateId[d.id],
                ))
            .toList();
      }

      final items = wordCountsByDebateId.entries
          .where((entry) => !placeholderRoots.contains(entry.key))
          .map(
            (entry) => _DebateFeedItem(
              debateId: entry.key,
              title: titleByDebateId[entry.key] ?? '',
              durationMinutes: _minutesFromWords(entry.value),
              house: houseByDebateId[entry.key] ?? '',
              order: orderByDebateId[entry.key] ?? 0,
              section: sectionByDebateId[entry.key],
              startTimecode: firstTimecodeByDebateId[entry.key],
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

  /// A debate is a placeholder when it carries no real speech content —
  /// only the "The House met at …" announcement. Detected by the title
  /// pattern *and* the absence of any non-boilerplate speech.
  static bool _isPlaceholderDebate(Debate debate, bool hasMeaningfulSpeech) {
    if (hasMeaningfulSpeech) return false;
    final title = debate.title.toLowerCase().trim();
    if (_placeholderTitlePattern.hasMatch(title)) return true;
    // No speech content and no detectable title — keep, to avoid hiding
    // real debates that simply haven't been indexed yet.
    return false;
  }

  static bool _isMeaningfulSpeech(Speech speech) {
    if (speech.isSittingStartAnnouncement) return false;
    if (speech.isTimestamp) return false;
    if (speech.isDateHeading) return false;
    return speech.speechText.trim().isNotEmpty;
  }

  static final RegExp _placeholderTitlePattern = RegExp(
    r'^the\s+(house|lords|committee|grand\s+committee)\b.*\bmet\s+at\b',
  );

  static int _minutesFromWords(int words) {
    return (words / _averageWordsPerMinute)
        .round()
        .clamp(1, _maxDurationMinutes);
  }

  static String? _normalizedHansardTimecode(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (h == null || m == null || s == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
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

class _HouseAccentCard extends StatelessWidget {
  final String house;
  final Widget child;

  const _HouseAccentCard({
    required this.house,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = _houseAccentColor(house);
    return Card(
      child: Row(
        children: [
          Container(
            width: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Color _houseAccentColor(String house) {
  final h = house.toLowerCase();
  if (h.contains('lords') || h.contains('grand committee')) {
    return const Color(0xFFB50938);
  }
  if (h.contains('westminster hall')) {
    return const Color(0xFF006548);
  }
  if (h.contains('committee')) {
    return const Color(0xFF1A5276);
  }
  return const Color(0xFF006548); // Commons default
}

class _DebateFeedItem {
  final String title;
  final int durationMinutes;
  final String house;
  final String debateId;
  final int order;
  final String? startTimecode;
  final String? section;

  const _DebateFeedItem({
    required this.title,
    required this.durationMinutes,
    this.house = '',
    this.debateId = '',
    this.order = 0,
    this.startTimecode,
    this.section,
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
