import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../models/member.dart';
import '../models/saved_speech.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/house_colors.dart';
import '../utils/parliament_live.dart';
import '../utils/party_colors.dart' as party_util;
import '../utils/speaker_identity.dart';
import '../viewmodels/transcript_viewmodel.dart';
import '../widgets/speech_actions_sheet.dart';
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

class _TranscriptViewState extends State<TranscriptView>
    with SingleTickerProviderStateMixin {
  static const int _speechListStartIndex = 1;

  late TranscriptViewModel _vm;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final ScrollController _minimapController = ScrollController();

  /// Parliament Live video tray that drops down from the AppBar. The WebView is
  /// built lazily on first open ([_playerEverOpened]) and then kept mounted —
  /// the tray is collapsed by clipping it to zero height — so playback and
  /// position survive a close/reopen.
  late final AnimationController _trayController;
  bool _isPlayerOpen = false;
  bool _playerEverOpened = false;

  /// True once the list is scrolled away from the very top. Drives the AppBar
  /// collapsing to a single compact line so the pinned video tray has room.
  bool _scrolled = false;

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
    _trayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    unawaited(_vm.loadSpeeches());
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    _trayController.dispose();
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

    // Collapse the AppBar once the first item (the info header) has scrolled up.
    final scrolled =
        topItem.index > 0 || topItem.itemLeadingEdge < -0.01;
    if (scrolled != _scrolled) {
      setState(() => _scrolled = scrolled);
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

  /// Opens/closes the Parliament Live video tray. The first open marks
  /// [_playerEverOpened] so the WebView is mounted from then on (collapsed by
  /// the [SizeTransition] when closed) rather than rebuilt each time.
  void _togglePlayer() {
    setState(() {
      _isPlayerOpen = !_isPlayerOpen;
      if (_isPlayerOpen) _playerEverOpened = true;
    });
    if (_isPlayerOpen) {
      _trayController.forward();
    } else {
      _trayController.reverse();
    }
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
          final titleText = (vm.primaryDebateTitle != null &&
                  vm.primaryDebateTitle!.isNotEmpty)
              ? vm.primaryDebateTitle!
              : 'Hansard Debate';

          return Scaffold(
            appBar: AppBar(
              backgroundColor: appBarColor,
              foregroundColor: appBarColor != null ? appBarForeground : null,
              iconTheme: appBarColor != null
                  ? const IconThemeData(color: appBarForeground)
                  : null,
              toolbarHeight: _scrolled ? 48 : kToolbarHeight,
              title: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _scrolled
                    ? Text(
                        titleText,
                        key: const ValueKey('title-compact'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Column(
                        key: const ValueKey('title-full'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.displayDate,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: appBarColor != null
                                      ? appBarForeground.withValues(alpha: 0.8)
                                      : null,
                                ),
                          ),
                        ],
                      ),
              ),
              actions: [
                if (parliamentLiveSectionHasVideo(vm.primarySection)) ...[
                  if (_isPlayerOpen)
                    FutureBuilder<ParliamentLiveTarget>(
                      future: vm.parliamentLiveTarget(),
                      builder: (context, snapshot) {
                        final target = snapshot.data;
                        if (target == null) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(Icons.open_in_new),
                          tooltip: 'Open full player',
                          onPressed: () => _openParliamentLiveUrl(
                            target.launchUrl,
                            title: 'Parliament Live · ${target.title}',
                          ),
                        );
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      _isPlayerOpen
                          ? Icons.smart_display
                          : Icons.smart_display_outlined,
                    ),
                    tooltip: _isPlayerOpen
                        ? 'Hide Parliament Live video'
                        : 'Show Parliament Live video',
                    onPressed: _togglePlayer,
                  ),
                ],
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 1200 ? 1080.0 : 920.0;
                if (vm.isLoading) return _buildLoadingIndicator();
                if (vm.error != null) return _buildErrorView(vm.error!);
                if (vm.speeches.isEmpty) return _buildEmptyView();
                final contentWidth = maxWidth + _minimapWidth;
                return Column(
                  children: [
                    _buildPlayerTraySection(vm, contentWidth),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentWidth),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _buildTranscriptList(vm)),
                                _buildMinimap(vm),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 48, color: muted),
          const SizedBox(height: 16),
          Text(
            'No sitting transcript available for this date.\n'
            'Parliament may be in recess.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
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
            return _buildDebateInfoHeader(vm);
          }

          final speechIndex = index - _speechListStartIndex;
          final speech = vm.speeches[speechIndex];
          final member = vm.memberForSpeech(speech);
          final timeLabel = vm.estimatedTimeForSpeechIndex(speechIndex);
          return RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onLongPress: speech.speechText.trim().isEmpty
                  ? null
                  : () => _showSpeechActions(speech, member),
              child: SpeechBlock(
                speech: speech,
                member: member,
                timeLabel: timeLabel,
                onMemberTap: member != null
                    ? () => _openMemberProfile(context, member)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Small informational line at the very top of the debate (scrolls away with
  /// the content) showing when the House met and when this debate begins —
  /// previously shown inside the video tray.
  Widget _buildDebateInfoHeader(TranscriptViewModel vm) {
    final theme = Theme.of(context);
    final metTime = vm.sittingStartTimeLabel;
    final debateTitle = (vm.primaryDebateTitle ?? '').trim();
    final debateStartLabel =
        vm.parliamentLiveStartLabelForDebateTitle(debateTitle);
    final showDebateStart =
        debateStartLabel != null && debateStartLabel != metTime;
    if (metTime == null && !showDebateStart) return const SizedBox.shrink();
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Wrap(
        spacing: 14,
        runSpacing: 2,
        children: [
          if (metTime != null) Text('House met at $metTime', style: style),
          if (showDebateStart)
            Text('Debate starts at $debateStartLabel', style: style),
        ],
      ),
    );
  }

  /// The Parliament Live video tray. It sits in the layout flow (a [Column]
  /// child above the scrolling list) so opening it pushes the transcript and
  /// minimap down rather than floating over them, and it stays pinned while the
  /// debate scrolls. Built lazily on first open and then kept mounted —
  /// collapsed to zero height by the [SizeTransition] — so playback and
  /// position survive a close/reopen.
  ///
  /// [Align] uses `heightFactor: 1` so the section shrink-wraps its child's
  /// height (a plain greedy [Align] would overflow the unbounded vertical
  /// space a [Column] hands its children).
  Widget _buildPlayerTraySection(TranscriptViewModel vm, double maxWidth) {
    if (!_playerEverOpened) return const SizedBox.shrink();
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _trayController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: _buildPlayerTray(vm),
        ),
      ),
    );
  }

  Widget _buildPlayerTray(TranscriptViewModel vm) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          color: theme.colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FutureBuilder<ParliamentLiveTarget>(
              future: vm.parliamentLiveTarget(),
              builder: (context, snapshot) {
                final target = snapshot.data;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _ParliamentLiveLoadingPane();
                }
                if (target != null && target.inlineUrl != null) {
                  return _ParliamentLiveInlinePlayer(
                    url: target.inlineUrl!,
                    isOpen: _isPlayerOpen,
                  );
                }
                if (target != null) {
                  return SizedBox(
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
                }
                return const _ParliamentLiveLoadingPane();
              },
            ),
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

  void _showSpeechActions(Speech speech, Member? member) {
    final speaker = speakerIdentityFor(speech, member);
    showSpeechActionsSheet(
      context,
      speech: SavedSpeech(
        speechId: speech.id,
        date: widget.date,
        displayDate: widget.displayDate,
        debateId: speech.debateId,
        debateTitle: speech.debateTitle,
        speakerName: speaker.name,
        speechText: speech.speechText,
        savedAt: DateTime.now(),
      ),
    );
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
      return HouseColors.lords;
    }
    if (h.contains('commons') || h.contains('westminster hall')) {
      return HouseColors.commons;
    }
    if (h.contains('&')) return HouseColors.mixed;
    // Committee rooms — use a neutral dark teal.
    return HouseColors.committee;
  }
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

  /// Whether the tray is currently open. The player stays mounted while the
  /// tray is collapsed (so it can resume), so we pause its media when this
  /// flips to false.
  final bool isOpen;

  const _ParliamentLiveInlinePlayer({required this.url, required this.isOpen});

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
    if (nextUrl != _urlKey) {
      _urlKey = nextUrl;
      _isLoading = true;
      _controller = _buildController(widget.url);
      return;
    }
    // The tray was collapsed — pause so audio doesn't keep playing underneath.
    if (oldWidget.isOpen && !widget.isOpen) {
      _pauseMedia();
    }
  }

  void _pauseMedia() {
    unawaited(
      _controller.runJavaScript(
        "document.querySelectorAll('video,audio')"
        ".forEach(function(m){try{m.pause();}catch(e){}});",
      ),
    );
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
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            unawaited(
              controller.runJavaScript(
                "var style = document.createElement('style');"
                "style.innerHTML = 'html, body { background: transparent !important; }';"
                "(document.head || document.documentElement).appendChild(style);",
              ),
            );
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
            // No gestureRecognizers: on iOS/WKWebView an EagerGestureRecognizer
            // greedily claims the pointer and swallows the single taps the
            // player's controls need. Leaving it unset lets the WebView handle
            // its own taps (matching the full-screen ParliamentLiveView).
            WebViewWidget(controller: _controller),
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
