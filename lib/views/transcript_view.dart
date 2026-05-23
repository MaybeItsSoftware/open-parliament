import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../models/member.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/parliament_live.dart';
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
  static const int _speechListStartIndex = 1;
  static final RegExp _guidPattern = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  );

  late TranscriptViewModel _vm;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final ScrollController _minimapController = ScrollController();
  Future<_ParliamentLiveTarget>? _liveTargetFuture;
  String? _liveTargetKey;

  /// Cumulative y-offsets in the minimap, one per speech plus a trailing
  /// total (so [_segmentOffsets].length == speeches.length + 1). Recomputed
  /// in [_buildMinimap] whenever the speech list count changes.
  List<double> _segmentOffsets = const [0];
  double _totalSegmentHeight = 0;

  /// Minimap segment height = clamp(chars * _pxPerChar, _min, _max). This
  /// makes the strip a faithful zoomed-out colour preview where long
  /// speeches form thicker bands.
  static const double _pxPerChar = 0.026;
  static const double _minSegmentHeight = 8;
  static const double _maxSegmentHeight = 160;
  static const double _segmentGap = 3;
  static const double _minimapWidth = 32;

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
    _vm.dispose();
    super.dispose();
  }

  void _onPositionsChanged() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Find the topmost visible item.
    ItemPosition? topItem;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0 || p.itemLeadingEdge >= 1) continue;
      if (topItem == null || p.index < topItem.index) topItem = p;
    }
    if (topItem == null) return;
    if (topItem.index < _speechListStartIndex) {
      _syncMinimapScroll(0, 0);
      return;
    }

    final speechIndex = topItem.index - _speechListStartIndex;

    // Fraction of the top item that is scrolled out of view above. Range
    // [0, 1]; lets the minimap track the main list smoothly within an item.
    final itemSpan = topItem.itemTrailingEdge - topItem.itemLeadingEdge;
    final withinFraction = itemSpan > 0
        ? (-topItem.itemLeadingEdge / itemSpan).clamp(0.0, 1.0)
        : 0.0;

    _syncMinimapScroll(speechIndex, withinFraction);
  }

  /// Slides the minimap so the current top speech's segment sits at the top
  /// of the minimap viewport. The within-item fraction interpolates between
  /// adjacent segment offsets so scrolling is smooth across boundaries.
  void _syncMinimapScroll(int topIndex, double withinFraction) {
    if (!_minimapController.hasClients) return;
    if (_totalSegmentHeight <= 0) return;
    if (topIndex < 0 || topIndex >= _segmentOffsets.length - 1) return;
    final maxScroll = _minimapController.position.maxScrollExtent;
    if (maxScroll <= 0) return;
    final segStart = _segmentOffsets[topIndex];
    final segEnd = _segmentOffsets[topIndex + 1];
    final cumulative = segStart + (segEnd - segStart) * withinFraction;
    final target = cumulative.clamp(0.0, maxScroll);
    if ((_minimapController.offset - target).abs() > 0.5) {
      _minimapController.jumpTo(target);
    }
  }

  void _jumpToIndex(int index) {
    if (index < 0 || index >= _vm.speeches.length) return;
    _scrollController.scrollTo(
      index: index + _speechListStartIndex,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _openParliamentLiveUrl(Uri url, {String? title}) async {
    await openParliamentLive(context: context, url: url, title: title);
  }

  Future<_ParliamentLiveTarget> _resolveParliamentLiveTarget(
    TranscriptViewModel vm,
  ) async {
    final service = context.read<ParliamentaryDataService>();
    final debateTitle = (vm.primaryDebateTitle ?? '').trim();
    final seekTimecode =
        vm.parliamentLiveStartTimecodeForDebateTitle(debateTitle) ??
            vm.sittingStartTimecode;
    final event = await service.findLiveEventForDebate(
      date: widget.date,
      debateTitle: debateTitle,
      house: vm.primaryHouse,
    );

    if (event != null) {
      final launchUrl = parliamentLiveEventUrl(
        event.guid,
        timecode: seekTimecode,
      );
      return _ParliamentLiveTarget(
        launchUrl: launchUrl,
        inlineUrl: _inlineParliamentLiveUrl(launchUrl),
        title: event.title,
        hasDirectEvent: true,
      );
    }

    final launchUrl = parliamentLiveSearchUrl(
      date: widget.date,
      house: vm.primaryHouse,
    );
    return _ParliamentLiveTarget(
      launchUrl: launchUrl,
      inlineUrl: null,
      title: widget.date,
      hasDirectEvent: false,
    );
  }

  Future<_ParliamentLiveTarget> _parliamentLiveTargetFuture(
    TranscriptViewModel vm,
  ) {
    final key = '${widget.date}|'
        '${vm.primaryDebateTitle ?? ''}|'
        '${vm.primaryHouse ?? ''}|'
        '${vm.sittingStartTimecode}|'
        '${vm.parliamentLiveStartTimecodeForDebateTitle(vm.primaryDebateTitle)}';
    if (_liveTargetFuture == null || _liveTargetKey != key) {
      _liveTargetKey = key;
      _liveTargetFuture = _resolveParliamentLiveTarget(vm);
    }
    return _liveTargetFuture!;
  }

  Uri? _inlineParliamentLiveUrl(Uri launchUrl) {
    if (!_supportsInlineWebView) return null;
    final guid = _eventGuidFromEventUrl(launchUrl);
    if (guid == null) return null;
    // Keep the event page when deep-linking by timecode so it can relay the seek.
    if (launchUrl.queryParameters.containsKey('in')) return launchUrl;
    // Use the standalone player in-card for reliable play controls otherwise.
    return parliamentLivePlayerUrl(guid, parentUrl: launchUrl);
  }

  bool get _supportsInlineWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  String? _eventGuidFromEventUrl(Uri url) {
    if (url.host.toLowerCase() != 'parliamentlive.tv') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 3) return null;
    if (segments[0].toLowerCase() != 'event' ||
        segments[1].toLowerCase() != 'index') {
      return null;
    }
    final guid = segments[2].toLowerCase();
    if (!_guidPattern.hasMatch(guid)) return null;
    return guid;
  }

  String? _timeLabelFromTimecode(String? timecode) {
    if (timecode == null) return null;
    final parts = timecode.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (h == null || m == null || s == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Rightmost segment index whose top edge is at or above `y`. Used for
  /// converting a tap's local y into the speech to jump to.
  int _segmentIndexForY(double y) {
    final n = _segmentOffsets.length - 1;
    if (n <= 0) return 0;
    if (y <= 0) return 0;
    if (y >= _totalSegmentHeight) return n - 1;
    int lo = 0;
    int hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_segmentOffsets[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static double _segmentHeightFor(Speech speech) {
    final chars = speech.speechText.length;
    final raw = chars * _pxPerChar;
    if (raw < _minSegmentHeight) return _minSegmentHeight;
    if (raw > _maxSegmentHeight) return _maxSegmentHeight;
    return raw;
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
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ScrollablePositionedList.builder(
        itemCount: vm.speeches.length + _speechListStartIndex,
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildParliamentLiveHeader(vm);
          }

          final speechIndex = index - _speechListStartIndex;
          final speech = vm.speeches[speechIndex];
          final member = vm.memberForSpeech(speech);
          final timeLabel = vm.estimatedTimeForSpeechIndex(speechIndex);
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
      ),
    );
  }

  Widget _buildParliamentLiveHeader(TranscriptViewModel vm) {
    final hasVideo = parliamentLiveSectionHasVideo(vm.primarySection);
    final metTime = vm.sittingStartTimeLabel;
    final debateTitle = (vm.primaryDebateTitle ?? '').trim();
    final debateTimecode =
        vm.parliamentLiveStartTimecodeForDebateTitle(debateTitle);
    final debateStartLabel = _timeLabelFromTimecode(debateTimecode);
    final showDebateStart =
        debateStartLabel != null && debateStartLabel != metTime;
    final unavailableMessage =
        parliamentLiveSectionUnavailableMessage(vm.primarySection);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: hasVideo
              ? FutureBuilder<_ParliamentLiveTarget>(
                  future: _parliamentLiveTargetFuture(vm),
                  builder: (context, snapshot) {
                    final target = snapshot.data;
                    const heading = 'Parliament Live';
                    final Widget videoPane;
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      videoPane = const _ParliamentLiveLoadingPane();
                    } else if (target != null && target.inlineUrl != null) {
                      videoPane =
                          _ParliamentLiveInlinePlayer(url: target.inlineUrl!);
                    } else if (target != null) {
                      videoPane = SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openParliamentLiveUrl(
                            target.launchUrl,
                            title: 'Parliament Live · ${target.title}',
                          ),
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(
                            target.hasDirectEvent
                                ? 'Open player'
                                : 'Open video search',
                          ),
                        ),
                      );
                    } else {
                      videoPane = const _ParliamentLiveLoadingPane();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.play_circle_outline),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                heading,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (target != null)
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                tooltip: 'Open full player',
                                onPressed: () => _openParliamentLiveUrl(
                                  target.launchUrl,
                                  title: 'Parliament Live · ${target.title}',
                                ),
                              ),
                          ],
                        ),
                          const SizedBox(height: 8),
                          videoPane,
                          if (metTime != null || showDebateStart)
                            const SizedBox(height: 6),
                          if (metTime != null)
                            Text(
                              'House met at $metTime',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          if (showDebateStart)
                            Text(
                              'Debate starts at $debateStartLabel',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                        ],
                    );
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.play_circle_outline),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Parliament Live',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (metTime != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'House met at $metTime',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                    if (showDebateStart) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Debate starts at $debateStartLabel',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      unavailableMessage ??
                          'No Parliament Live video is available for this section.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static bool _isEventPageUrl(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (url.host.toLowerCase() != 'parliamentlive.tv') return false;
    if (segments.length < 3) return false;
    return segments[0].toLowerCase() == 'event' &&
        segments[1].toLowerCase() == 'index';
  }

  // ─── Minimap ────────────────────────────────────────────────────────────────

  /// Vertical strip on the right edge with one party-coloured segment per
  /// speech, sized in proportion to the speech's text length. Acts as a
  /// zoomed-out colour preview of the transcript. Its own scroll position is
  /// driven by the main list, producing parallax: a long speech in the main
  /// view advances the minimap by only a few pixels.
  Widget _buildMinimap(TranscriptViewModel vm) {
    final theme = Theme.of(context);
    final colors = <Color>[
      for (final s in vm.speeches)
        _minimapColor(s, vm.memberForSpeech(s), theme),
    ];

    // Recompute cumulative offsets whenever the speech count changes.
    if (_segmentOffsets.length != vm.speeches.length + 1) {
      final offsets = <double>[0.0];
      var sum = 0.0;
      for (final s in vm.speeches) {
        sum += _segmentHeightFor(s);
        offsets.add(sum);
      }
      _segmentOffsets = offsets;
      _totalSegmentHeight = sum;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: _minimapWidth,
        child: ClipRect(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _minimapController,
              physics: const NeverScrollableScrollPhysics(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final index = _segmentIndexForY(details.localPosition.dy);
                  _jumpToIndex(index);
                },
                child: CustomPaint(
                  size: Size(_minimapWidth, _totalSegmentHeight),
                  painter: _MinimapPainter(
                    colors: colors,
                    offsets: _segmentOffsets,
                    gap: _segmentGap,
                    width: _minimapWidth,
                  ),
                ),
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

class _ParliamentLiveTarget {
  final Uri launchUrl;
  final Uri? inlineUrl;
  final String title;
  final bool hasDirectEvent;

  const _ParliamentLiveTarget({
    required this.launchUrl,
    required this.inlineUrl,
    required this.title,
    required this.hasDirectEvent,
  });
}

class _ParliamentLiveLoadingPane extends StatelessWidget {
  const _ParliamentLiveLoadingPane();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _ParliamentLiveInlinePlayer extends StatefulWidget {
  final Uri url;

  const _ParliamentLiveInlinePlayer({required this.url});

  @override
  State<_ParliamentLiveInlinePlayer> createState() =>
      _ParliamentLiveInlinePlayerState();
}

class _ParliamentLiveInlinePlayerState
    extends State<_ParliamentLiveInlinePlayer> {
  late WebViewController _controller;
  bool _isLoading = true;
  String _urlKey = '';

  @override
  void initState() {
    super.initState();
    _urlKey = widget.url.toString();
    _controller = _buildController(widget.url);
  }

  @override
  void didUpdateWidget(covariant _ParliamentLiveInlinePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUrl = widget.url.toString();
    if (nextUrl == _urlKey) return;
    _urlKey = nextUrl;
    _isLoading = true;
    _controller = _buildController(widget.url);
  }

  WebViewController _buildController(Uri url) {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (_TranscriptViewState._isEventPageUrl(url)) {
              unawaited(
                controller.runJavaScript(
                  "document.getElementById('videoContainer')?.scrollIntoView();",
                ),
              );
            }
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      );
    controller.loadRequest(url);

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            WebViewWidget(
              controller: _controller,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<EagerGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
            if (_isLoading)
              const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final List<Color> colors;

  /// Cumulative segment offsets; length == colors.length + 1.
  final List<double> offsets;
  final double gap;
  final double width;

  _MinimapPainter({
    required this.colors,
    required this.offsets,
    required this.gap,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barLeft = width * 0.18;
    final barWidth = width * 0.64;

    final segmentPaint = Paint();
    final radius = Radius.circular(barWidth * 0.25);
    for (int i = 0; i < colors.length; i++) {
      segmentPaint.color = colors[i];
      final y = offsets[i];
      final h = offsets[i + 1] - offsets[i] - gap;
      if (h <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, y, barWidth, h),
          radius,
        ),
        segmentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter old) {
    return !identical(colors, old.colors) ||
        !identical(offsets, old.offsets) ||
        gap != old.gap ||
        width != old.width;
  }
}
