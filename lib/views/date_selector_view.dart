import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../utils/house_colors.dart';
import '../utils/party_colors.dart';
import '../viewmodels/date_selector_viewmodel.dart';
import '../widgets/sitting_day_calendar.dart';
import 'app_drawer.dart';
import 'bill_view.dart';
import 'transcript_view.dart';

/// The redesigned landing screen for the app's main page.
class DateSelectorView extends StatefulWidget {
  const DateSelectorView({super.key});

  @override
  State<DateSelectorView> createState() => _DateSelectorViewState();
}

class _DateSelectorViewState extends State<DateSelectorView> {
  late DateSelectorViewModel _vm;

  // Tall enough that even the shortest debates (which get clamped to this
  // height) have room for a 2-line title — see _DebateCardContent, which
  // always allows 2 title lines on narrow screens regardless of card height.
  static const double _minDebateCardHeight = 92;
  static const double _pixelsPerMinute = 3.5;

  /// True until [_initializeLandingDay] resolves. While `true`, the
  /// view-model's focused day is still its raw `DateTime.now()` default and
  /// hasn't been vetted for content, so the debates feed shows a loading
  /// state instead of "today" (which would otherwise flash a false "no
  /// debates" card whenever today turns out to have none).
  bool _resolvingLandingDay = true;

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
    try {
      final landingDay = await _vm.resolveLandingDay(today);
      _vm.setFocusedDay(landingDay);
      _vm.selectDay(landingDay);
    } finally {
      if (mounted) setState(() => _resolvingLandingDay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<DateSelectorViewModel>(
        builder: (context, vm, _) {
          final selectedDay = vm.selectedDay ?? vm.focusedDay;
          return Scaffold(
            drawer: const AppDrawer(current: AppDestination.debates),
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
                            _buildTopBar(context, vm, selectedDay),
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
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragEnd: (details) {
                                  final velocity =
                                      details.primaryVelocity ?? 0;
                                  if (velocity > 300) {
                                    unawaited(
                                      _shiftBySittingDay(
                                        vm,
                                        selectedDay,
                                        -1,
                                      ),
                                    );
                                  } else if (velocity < -300) {
                                    unawaited(
                                      _shiftBySittingDay(
                                        vm,
                                        selectedDay,
                                        1,
                                      ),
                                    );
                                  }
                                },
                                child: _buildDebatesFeed(vm, selectedDay),
                              ),
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

  /// Inline top bar: the drawer button sits outside the date-selector box's
  /// tinted background.
  Widget _buildTopBar(
    BuildContext context,
    DateSelectorViewModel vm,
    DateTime selectedDay,
  ) {
    return Row(
      children: [
        Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildContextualDateSelector(context, vm, selectedDay),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => unawaited(_shiftBySittingDay(vm, selectedDay, -1)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _pickDate(vm, selectedDay),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _friendlyDate(selectedDay),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: canMoveForward
                ? () => unawaited(_shiftBySittingDay(vm, selectedDay, 1))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDebatesFeed(DateSelectorViewModel vm, DateTime day) {
    if (_resolvingLandingDay) {
      // Landing-day resolution hasn't finished, so `day` is still the raw
      // "today" default and hasn't been checked for content — show a loading
      // state rather than a premature "no debates" card for a day we may be
      // about to navigate away from.
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day.isAtSameMomentAs(today);
    return FutureBuilder<DebateFeedResult>(
      future: vm.loadDebateFeedWithStatus(day, isToday: isToday),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final result = snapshot.data;
        final items = result?.items ?? const <DebateFeedItem>[];
        if (items.isEmpty) {
          return (result?.isPendingPublication ?? false)
              ? _buildPendingPublicationCard(vm, day)
              : _buildNoDebatesCard(day);
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
                onTap: () =>
                    _navigateToTranscript(day, debateId: item.debateId),
                child: _DebateCardContent(item: item),
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
    return scaled < _minDebateCardHeight ? _minDebateCardHeight : scaled;
  }

  Future<void> _pickDate(DateSelectorViewModel vm, DateTime selectedDay) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SittingDayCalendar(
        viewModel: vm,
        initialMonth: DateTime(selectedDay.year, selectedDay.month),
        selectedDay: selectedDay,
        lastDay: today,
      ),
    );
    if (picked == null) return;

    // The calendar only enables Hansard sitting days, but a sitting day can
    // still turn out to be placeholder-only (e.g. "The House met at ... and
    // adjourned") — snap those to the nearest day with real debate content.
    var resolved = picked;
    if (!await vm.hasVisibleDebates(picked)) {
      resolved = await vm.previousVisibleSittingDay(picked) ?? picked;
    }
    if (!mounted) return;
    if (resolved != picked) {
      _showInfoMessage(
        'No debates on ${_friendlyDate(picked)}; showing '
        '${_friendlyDate(resolved)} instead.',
      );
    }

    vm.setFocusedDay(resolved);
    vm.selectDay(resolved);
  }

  Future<void> _shiftBySittingDay(
    DateSelectorViewModel vm,
    DateTime current,
    int deltaDays,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = deltaDays < 0
        ? await vm.previousVisibleSittingDay(current)
        : await vm.nextVisibleSittingDay(current);

    if (next == null) {
      if (!mounted) return;
      _showInfoMessage('No more sitting dates available in that direction.');
      return;
    }

    if (next.isAfter(today)) return;
    vm.setFocusedDay(next);
    vm.selectDay(next);
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

  Widget _buildPendingPublicationCard(DateSelectorViewModel vm, DateTime day) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Today’s debates haven’t been published yet.\n'
                'Check back later, or view the previous sitting day.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => unawaited(_shiftBySittingDay(vm, day, -1)),
                icon: const Icon(Icons.arrow_back),
                label: const Text('View previous sitting day'),
              ),
            ],
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

/// Card body for a single debate. Reveals progressively more detail as the
/// card grows taller (cards are sized in proportion to debate duration), so
/// long debates fill their extra space with engagement stats and a party
/// contribution bar instead of leaving it blank.
class _DebateCardContent extends StatelessWidget {
  final DebateFeedItem item;

  const _DebateCardContent({required this.item});

  // Height thresholds (px) at which each extra tier becomes visible.
  static const double _metaTier = 100;
  static const double _chipTier = 152;
  static const double _speakersTier = 190;
  static const double _pieTier = 270;

  // Below this card width, a single line of title text holds too few
  // characters for titles to be usable in their 1-line form (bill/motion
  // titles are frequently long), so narrow cards always get 2 lines
  // regardless of the height-driven tier below.
  static const double _narrowWidth = 400;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final isNarrow = width < _narrowWidth;
        final titleMaxLines = isNarrow ? 2 : (height >= _metaTier ? 2 : 1);
        final hasParties = item.partyBreakdown.isNotEmpty;
        final showMeta = height >= _metaTier && _metaSegments(item).isNotEmpty;
        final chips = _contextChips(context);
        final showChips = height >= _chipTier && chips.isNotEmpty;
        final showSpeakers =
            height >= _speakersTier && item.topSpeakers.isNotEmpty;
        final showPie = height >= _pieTier && hasParties;

        // Below the title, everything else is optional "extra" content whose
        // real height only loosely tracks the tier thresholds above (text
        // scale, locale, and speaker-list length can all push it taller than
        // assumed). Below the pie tier that extra content is laid out inside
        // a non-scrolling SingleChildScrollView so it clips gracefully
        // instead of overflowing the card when it doesn't quite fit.
        final extraChildren = [
          if (showChips) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: chips),
          ],
          if (showMeta) ...[
            const SizedBox(height: 6),
            Text(
              _metaSegments(item).join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ];

        final Widget extra = _AdaptiveExtraContent(
          extraChildren: extraChildren,
          showChips: showChips,
          showMeta: showMeta,
          showSpeakers: showSpeakers,
          showPie: showPie,
          hasParties: hasParties,
          item: item,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    // Even at 2 lines, long bill/motion titles can still be
                    // clipped — the Tooltip guarantees the full title is
                    // always readable via long-press (or hover on desktop),
                    // rather than the ellipsis being a dead end.
                    child: Tooltip(
                      message: item.title,
                      child: Text(
                        item.title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              Expanded(child: extra),
            ],
          ),
        );
      },
    );
  }

  static List<String> _metaSegments(DebateFeedItem item) {
    final segments = <String>[];
    if (item.speakerCount > 0) {
      segments.add(
        '${item.speakerCount} '
        '${item.speakerCount == 1 ? 'speaker' : 'speakers'}',
      );
    }
    if (item.contributionCount > 0) {
      segments.add(
        '${item.contributionCount} '
        '${item.contributionCount == 1 ? 'contribution' : 'contributions'}',
      );
    }
    final start = item.startTimecode;
    if (start != null && start.length >= 5) {
      segments.add(start.substring(0, 5));
    }
    return segments;
  }

  /// Context chips shown above the meta row: the debate's section/type and, if
  /// the title names a bill, a tappable chip that opens bills.parliament.uk.
  List<Widget> _contextChips(BuildContext context) {
    final chips = <Widget>[];
    final section = item.section?.trim() ?? '';
    // Skip the section when it just restates the title.
    if (section.isNotEmpty &&
        !item.title.toLowerCase().contains(section.toLowerCase())) {
      chips.add(_StaticChip(label: section));
    }
    final bill = item.relatedBillTitle;
    if (bill != null) {
      chips.add(
        _ActionChipLink(
          icon: Icons.article,
          label: 'View bill',
          onTap: () => _openBill(context, bill),
        ),
      );
    }
    return chips;
  }

  void _openBill(BuildContext context, String billTitle) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BillView(billTitle: billTitle)),
    );
  }
}

/// Adaptive container for the debate card's extra content.
/// It uses a LayoutBuilder to calculate the remaining available space and dynamically
/// sizes and filters its children to avoid clipping the speakers list.
class _AdaptiveExtraContent extends StatelessWidget {
  final List<Widget> extraChildren;
  final bool showChips;
  final bool showMeta;
  final bool showSpeakers;
  final bool showPie;
  final bool hasParties;
  final DebateFeedItem item;

  const _AdaptiveExtraContent({
    required this.extraChildren,
    required this.showChips,
    required this.showMeta,
    required this.showSpeakers,
    required this.showPie,
    required this.hasParties,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final textScaler = MediaQuery.textScalerOf(context);

        // 1. Calculate estimated height of extraChildren
        double extraChildrenHeight = 0;
        if (showChips) {
          final double baseChipFontSize = Theme.of(context).textTheme.labelSmall?.fontSize ?? 10.0;
          final double scaledChipFontSize = textScaler.scale(baseChipFontSize);
          final double chipHeight = scaledChipFontSize + 8.0;
          extraChildrenHeight += chipHeight + 6.0;
        }
        if (showMeta) {
          final double baseMetaFontSize = Theme.of(context).textTheme.labelMedium?.fontSize ?? 11.0;
          final double scaledMetaFontSize = textScaler.scale(baseMetaFontSize);
          final double metaHeight = scaledMetaFontSize * 1.3;
          extraChildrenHeight += metaHeight + 6.0;
        }

        final remainingHeight = maxHeight - extraChildrenHeight;

        // 2. Determine how many speakers can fit
        // Spacing: 8.0, row height: 38.0
        int visibleSpeakerCount = 0;
        if (showSpeakers && item.topSpeakers.isNotEmpty) {
          for (int i = 1; i <= item.topSpeakers.length; i++) {
            final needed = 8.0 + (38.0 * i);
            if (needed <= remainingHeight) {
              visibleSpeakerCount = i;
            } else {
              break;
            }
          }
        }

        final hasVisibleSpeakers = visibleSpeakerCount > 0;

        if (showPie && hasParties && hasVisibleSpeakers) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...extraChildren,
              const SizedBox(height: 8),
              _TopSpeakersList(speakers: item.topSpeakers.take(visibleSpeakerCount).toList()),
              const SizedBox(height: 8),
              Expanded(
                child: _PartyContributionPie(breakdown: item.partyBreakdown),
              ),
            ],
          );
        }

        final showSpeakersList = showSpeakers && hasVisibleSpeakers;
        final showPartyBar = !showSpeakersList && hasParties && (remainingHeight >= 12.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...extraChildren,
            if (showSpeakersList) ...[
              const SizedBox(height: 8),
              _TopSpeakersList(speakers: item.topSpeakers.take(visibleSpeakerCount).toList()),
            ] else if (showPartyBar) ...[
              const SizedBox(height: 6),
              _PartyContributionBar(breakdown: item.partyBreakdown),
            ],
          ],
        );
      },
    );
  }
}

/// A small non-interactive label chip (e.g. the debate's section/type).
class _StaticChip extends StatelessWidget {
  final String label;

  const _StaticChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// A tappable outlined chip with a leading icon, used for the bill deep-link.
class _ActionChipLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChipLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 2),
              Icon(Icons.open_in_new, size: 11, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ranked list of a debate's most engaged speakers, shown once a card is tall
/// enough to host it. Each row is a small party-ringed portrait (with a
/// contribution-count badge) and the speaker's name.
class _TopSpeakersList extends StatelessWidget {
  final List<SpeakerContribution> speakers;

  const _TopSpeakersList({required this.speakers});

  static const double _avatarSize = 28;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final speaker in speakers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _SpeakerAvatar(speaker: speaker, size: _avatarSize),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    speaker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small circular portrait for one speaker: a party-coloured ring around the
/// image (or initials, when no thumbnail is available or it fails to load),
/// with a contribution-count badge at the bottom-right corner.
class _SpeakerAvatar extends StatelessWidget {
  final SpeakerContribution speaker;
  final double size;

  const _SpeakerAvatar({required this.speaker, required this.size});

  @override
  Widget build(BuildContext context) {
    final ringColor = partyColor(speaker.partyToken ?? '');
    final theme = Theme.of(context);
    final url = speaker.thumbnailUrl;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 1.5),
            ),
            child: ClipOval(
              child: url != null && url.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: url,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          _initialsAvatar(theme, ringColor, speaker.name, size),
                      errorWidget: (_, __, ___) =>
                          _initialsAvatar(theme, ringColor, speaker.name, size),
                    )
                  : _initialsAvatar(theme, ringColor, speaker.name, size),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: ringColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1,
                ),
              ),
              child: Text(
                '${speaker.contributionCount}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: _foregroundFor(ringColor, theme),
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _initialsAvatar(
    ThemeData theme,
    Color color,
    String name,
    double diameter,
  ) {
    return CircleAvatar(
      radius: diameter / 2,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: diameter * 0.35,
          fontWeight: FontWeight.bold,
          color: _foregroundFor(color, theme),
        ),
      ),
    );
  }

  static String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  static Color _foregroundFor(Color background, ThemeData theme) {
    final brightness = ThemeData.estimateBrightnessForColor(background);
    return brightness == Brightness.dark
        ? Colors.white
        : theme.colorScheme.onSurface;
  }
}

/// Horizontal stacked bar showing each party's share of the contributions in a
/// debate. Segments are sized in proportion to contribution count and coloured
/// with each party's brand colour.
class _PartyContributionBar extends StatelessWidget {
  final List<PartyContribution> breakdown;

  const _PartyContributionBar({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final total = breakdown.fold<int>(0, (sum, p) => sum + p.count);
    if (total == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            for (final p in breakdown)
              Expanded(
                flex: p.count,
                child: Container(color: partyColor(p.partyToken)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pie chart of party contributions with a compact legend, shown on tall
/// (long-duration) debate cards. Drawn with a [CustomPainter] to avoid pulling
/// in a charting dependency.
class _PartyContributionPie extends StatelessWidget {
  final List<PartyContribution> breakdown;

  const _PartyContributionPie({required this.breakdown});

  static const Map<String, String> _labels = {
    'labour': 'Lab',
    'conservative': 'Con',
    'libdem': 'Lib Dem',
    'snp': 'SNP',
    'green': 'Green',
    'plaidcymru': 'Plaid Cymru',
    'sinnfein': 'Sinn Féin',
    'dup': 'DUP',
    'uup': 'UUP',
    'alliance': 'Alliance',
    'crossbench': 'Crossbench',
    'independent': 'Independent',
    'speaker': 'Speaker',
    'reform': 'Reform',
  };

  @override
  Widget build(BuildContext context) {
    final total = breakdown.fold<int>(0, (sum, p) => sum + p.count);
    if (total == 0) return const SizedBox.shrink();

    final labelStyle = Theme.of(context).textTheme.labelMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the pie off the available height so it always fits the card,
        // capped so the legend keeps room (and bounded if height is unbounded).
        final maxHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 96.0;
        final side = maxHeight.clamp(0.0, constraints.maxWidth * 0.5);

        // Calculate how many legend items can fit in the available height.
        final textScaler = MediaQuery.textScalerOf(context);
        final double baseFontSize = labelStyle?.fontSize ?? 12.0;
        final double scaledFontSize = textScaler.scale(baseFontSize);
        // Estimate row height: font size + vertical padding (2px) + a small safety margin for line-height (e.g., 4px)
        final double itemHeight = scaledFontSize + 6.0;

        int limit = 0;
        for (int i = 1; i <= breakdown.length; i++) {
          final remainderCount = breakdown.length - i;
          final double neededHeight =
              i * itemHeight + (remainderCount > 0 ? itemHeight : 0);
          if (neededHeight <= maxHeight) {
            limit = i;
          } else {
            break;
          }
        }

        // Cap at at most 5 legend rows so it matches original design limits.
        if (limit > 5) {
          limit = 5;
        }

        final legendParties = limit > 0 ? breakdown.take(limit).toList() : <PartyContribution>[];
        final remainder = limit > 0 ? breakdown.length - legendParties.length : 0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: side,
              height: side,
              child: CustomPaint(
                painter: _PartyPiePainter(breakdown: breakdown, total: total),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in legendParties)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: partyColor(p.partyToken),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${_labels[p.partyToken] ?? p.partyToken}  ·  '
                              '${p.count}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: labelStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (remainder > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        '+$remainder more',
                        style: labelStyle?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PartyPiePainter extends CustomPainter {
  final List<PartyContribution> breakdown;
  final int total;

  _PartyPiePainter({required this.breakdown, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final rect = Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
    var start = -math.pi / 2;
    for (final p in breakdown) {
      final sweep = (p.count / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = partyColor(p.partyToken);
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PartyPiePainter old) =>
      old.total != total || old.breakdown != breakdown;
}

class _HouseAccentCard extends StatelessWidget {
  final String house;
  final Widget child;
  final VoidCallback? onTap;

  const _HouseAccentCard({
    required this.house,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _houseAccentColor(house);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
      ),
    );
  }
}

Color _houseAccentColor(String house) {
  final h = house.toLowerCase();
  if (h.contains('lords') || h.contains('grand committee')) {
    return HouseColors.lords;
  }
  if (h.contains('westminster hall')) {
    return HouseColors.commons;
  }
  if (h.contains('committee')) {
    return HouseColors.committee;
  }
  return HouseColors.commons; // Commons default
}
