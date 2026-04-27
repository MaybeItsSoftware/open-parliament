import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/member.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/transcript_viewmodel.dart';
import '../widgets/speech_block.dart';
import 'member_view.dart';

/// Displays the verbatim transcript for a single Parliamentary sitting day.
///
/// Performance notes:
///  - Uses [ScrollablePositionedList] (backed by a [SliverList]) so that the
///    minimap can jump directly to an item index without traversing the full
///    list.
///  - [SpeechBlock] widgets are lightweight and avoid unnecessary rebuilds
///    through the use of `const` constructors and `RepaintBoundary`.
///
/// Navigation:
///  - A right-edge minimap shows one party-coloured segment per speech and
///    scrolls in parallax with the main list. Tap any segment to jump.
class TranscriptView extends StatefulWidget {
  final String date;
  final String displayDate;
  /// If set, the transcript will scroll to the first speech of this debate
  /// once loading completes.
  final String? initialDebateId;

  const TranscriptView({
    super.key,
    required this.date,
    required this.displayDate,
    this.initialDebateId,
  });

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  late TranscriptViewModel _vm;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final ScrollController _minimapController = ScrollController();
  final ValueNotifier<_VisibleRange> _visibleRange =
      ValueNotifier(const _VisibleRange(0, 0));

  /// Pixel height per speech in the minimap. Smaller = more "compressed",
  /// i.e. minimap moves slower relative to the main list.
  static const double _minimapSegmentHeight = 8;
  static const double _minimapWidth = 28;

  @override
  void initState() {
    super.initState();
    final service = context.read<ParliamentaryDataService>();
    _vm = TranscriptViewModel(
      service,
      date: widget.date,
      initialDebateId: widget.initialDebateId,
    );
    _positionsListener.itemPositions.addListener(_onPositionsChanged);
    unawaited(_vm.loadSpeeches());
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    _minimapController.dispose();
    _visibleRange.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _onPositionsChanged() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    int? top;
    int? bottom;
    for (final p in positions) {
      // Skip items entirely above or below the viewport.
      if (p.itemTrailingEdge <= 0 || p.itemLeadingEdge >= 1) continue;
      top = (top == null) ? p.index : (p.index < top ? p.index : top);
      bottom =
          (bottom == null) ? p.index : (p.index > bottom ? p.index : bottom);
    }
    if (top == null || bottom == null) return;

    final newRange = _VisibleRange(top, bottom);
    if (newRange != _visibleRange.value) {
      _visibleRange.value = newRange;
    }
    _syncMinimapScroll(top);
  }

  /// Slides the minimap so the current top speech sits at a proportional
  /// position within the minimap's own viewport — this is what produces the
  /// "slower pace" parallax effect.
  void _syncMinimapScroll(int topIndex) {
    if (!_minimapController.hasClients) return;
    final total = _vm.speeches.length;
    if (total <= 1) return;
    final maxScroll = _minimapController.position.maxScrollExtent;
    if (maxScroll <= 0) return;
    final ratio = topIndex / (total - 1);
    final target = (ratio * maxScroll).clamp(0.0, maxScroll);
    if ((_minimapController.offset - target).abs() > 0.5) {
      _minimapController.jumpTo(target);
    }
  }

  void _jumpToIndex(int index) {
    if (index < 0 || index >= _vm.speeches.length) return;
    _scrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<TranscriptViewModel>(
        builder: (context, vm, _) {
          final house = vm.primaryHouse;
          final appBarColor = _houseColor(house);
          const appBarForeground = Color(0xFFFFE000);

          return Scaffold(
            appBar: AppBar(
              backgroundColor: appBarColor,
              foregroundColor: appBarColor != null ? appBarForeground : null,
              iconTheme: appBarColor != null
                  ? const IconThemeData(color: appBarForeground)
                  : null,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (vm.primaryDebateTitle != null &&
                            vm.primaryDebateTitle!.isNotEmpty)
                        ? vm.primaryDebateTitle!
                        : 'Hansard Debate',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.displayDate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: appBarColor != null
                              ? appBarForeground.withValues(alpha: 0.8)
                              : null,
                        ),
                  ),
                ],
              ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 1200 ? 1080.0 : 920.0;
                if (vm.isLoading) return _buildLoadingIndicator();
                if (vm.error != null) return _buildErrorView(vm.error!);
                if (vm.speeches.isEmpty) return _buildEmptyView();
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth + _minimapWidth,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildTranscriptList(vm)),
                        _buildMinimap(vm),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ─── Loading / error / empty states ────────────────────────────────────────

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading transcript…'),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to load transcript',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _vm.loadSpeeches,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No sitting transcript available for this date.\n'
            'Parliament may be in recess.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ─── Transcript list ────────────────────────────────────────────────────────

  /// High-performance scrollable list powered by [ScrollablePositionedList].
  ///
  /// Each item is wrapped in a [RepaintBoundary] so that scrolling a long
  /// transcript only repaints the visible viewport rather than the full list.
  Widget _buildTranscriptList(TranscriptViewModel vm) {
    return ScrollablePositionedList.builder(
      itemCount: vm.speeches.length,
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      itemBuilder: (context, index) {
        final speech = vm.speeches[index];
        final member = vm.memberForSpeech(speech);
        final timeLabel = vm.estimatedTimeForSpeechIndex(index);
        return RepaintBoundary(
          child: SpeechBlock(
            speech: speech,
            member: member,
            timeLabel: timeLabel,
            onMemberTap: member != null
                ? () => _openMemberProfile(context, member)
                : null,
          ),
        );
      },
    );
  }

  // ─── Minimap ────────────────────────────────────────────────────────────────

  /// Vertical strip on the right edge with one party-coloured segment per
  /// speech. The strip's own scroll position is driven by the main list — at
  /// `_minimapSegmentHeight` per item it advances much more slowly than the
  /// main scroll, producing the parallax effect.
  Widget _buildMinimap(TranscriptViewModel vm) {
    final theme = Theme.of(context);
    final colors = <Color>[
      for (final s in vm.speeches) _minimapColor(s, vm.memberForSpeech(s), theme),
    ];
    final totalHeight = vm.speeches.length * _minimapSegmentHeight;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: _minimapWidth,
        child: ClipRect(
          child: SingleChildScrollView(
            controller: _minimapController,
            physics: const NeverScrollableScrollPhysics(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final index =
                    (details.localPosition.dy / _minimapSegmentHeight).floor();
                _jumpToIndex(index);
              },
              child: ValueListenableBuilder<_VisibleRange>(
                valueListenable: _visibleRange,
                builder: (context, range, _) {
                  return CustomPaint(
                    size: Size(_minimapWidth, totalHeight),
                    painter: _MinimapPainter(
                      colors: colors,
                      segmentHeight: _minimapSegmentHeight,
                      width: _minimapWidth,
                      highlightStart: range.top,
                      highlightEnd: range.bottom,
                      highlightColor:
                          theme.colorScheme.primary.withValues(alpha: 0.18),
                      indicatorColor: theme.colorScheme.primary,
                      trackColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _minimapColor(Speech speech, Member? member, ThemeData theme) {
    if (speech.isPrayers || speech.isEventTag) {
      return theme.colorScheme.outlineVariant;
    }
    if (speech.isDivision) {
      return theme.colorScheme.tertiary;
    }
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party.isNotEmpty == true ? member!.party : '');
    if (partyKey.isNotEmpty) {
      return party_util.partyColor(
        partyKey,
        fallback: theme.colorScheme.outline,
      );
    }
    return theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
  }

  void _openMemberProfile(BuildContext context, Member member) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberView(member: member)),
    );
  }

  static Color? _houseColor(String? house) {
    if (house == null) return null;
    final h = house.toLowerCase();
    if (h.contains('lords') || h.contains('grand committee')) {
      return const Color(0xFFB50938);
    }
    if (h.contains('commons') || h.contains('westminster hall')) {
      return const Color(0xFF006548);
    }
    if (h.contains('&')) return const Color(0xFF5B1A6B);
    // Committee rooms — use a neutral dark teal.
    return const Color(0xFF1A5276);
  }
}

class _VisibleRange {
  final int top;
  final int bottom;
  const _VisibleRange(this.top, this.bottom);

  @override
  bool operator ==(Object other) =>
      other is _VisibleRange && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);
}

class _MinimapPainter extends CustomPainter {
  final List<Color> colors;
  final double segmentHeight;
  final double width;
  final int highlightStart;
  final int highlightEnd;
  final Color highlightColor;
  final Color indicatorColor;
  final Color trackColor;

  _MinimapPainter({
    required this.colors,
    required this.segmentHeight,
    required this.width,
    required this.highlightStart,
    required this.highlightEnd,
    required this.highlightColor,
    required this.indicatorColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barLeft = width * 0.28;
    final barWidth = width * 0.44;

    final trackPaint = Paint()..color = trackColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, 0, barWidth, size.height),
        const Radius.circular(2),
      ),
      trackPaint,
    );

    final segmentPaint = Paint();
    for (int i = 0; i < colors.length; i++) {
      segmentPaint.color = colors[i];
      final y = i * segmentHeight;
      canvas.drawRect(
        Rect.fromLTWH(barLeft, y, barWidth, segmentHeight - 0.5),
        segmentPaint,
      );
    }

    if (highlightEnd >= highlightStart && highlightStart >= 0) {
      final hlY = highlightStart * segmentHeight;
      final hlH = (highlightEnd - highlightStart + 1) * segmentHeight;
      final highlightPaint = Paint()..color = highlightColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, hlY, width - 4, hlH),
          const Radius.circular(4),
        ),
        highlightPaint,
      );
      final indicatorPaint = Paint()
        ..color = indicatorColor
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(2, hlY),
        Offset(width - 2, hlY),
        indicatorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter old) {
    return !identical(colors, old.colors) ||
        colors.length != old.colors.length ||
        segmentHeight != old.segmentHeight ||
        width != old.width ||
        highlightStart != old.highlightStart ||
        highlightEnd != old.highlightEnd ||
        highlightColor != old.highlightColor ||
        indicatorColor != old.indicatorColor ||
        trackColor != old.trackColor;
  }
}
