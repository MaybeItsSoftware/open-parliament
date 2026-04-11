import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../services/parliamentary_data_service.dart';
import '../viewmodels/transcript_viewmodel.dart';
import '../widgets/speech_block.dart';

/// Displays the verbatim transcript for a single Parliamentary sitting day.
///
/// Performance notes:
///  - Uses [ScrollablePositionedList] (backed by a [SliverList]) so that the
///    Jump-to-Member feature can jump directly to an item index without
///    traversing the entire list.
///  - [SpeechBlock] widgets are lightweight and avoid unnecessary rebuilds
///    through the use of `const` constructors and `RepaintBoundary`.
///
/// Interaction:
///  - A search/jump FAB opens the speaker drawer.
///  - The speaker drawer lists all unique speakers sorted alphabetically.
///  - Tapping a speaker scrolls to their first contribution.
class TranscriptView extends StatefulWidget {
  final String date;
  final String displayDate;

  const TranscriptView({
    super.key,
    required this.date,
    required this.displayDate,
  });

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  late TranscriptViewModel _vm;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    final service = context.read<ParliamentaryDataService>();
    _vm = TranscriptViewModel(service, date: widget.date);
    unawaited(_vm.loadSpeeches());
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
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(widget.displayDate),
          actions: [
            IconButton(
              icon: const Icon(Icons.people),
              tooltip: 'Jump to speaker',
              onPressed: _openSpeakerDrawer,
            ),
          ],
        ),
        endDrawer: _buildSpeakerDrawer(),
        body: Consumer<TranscriptViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading) {
              return _buildLoadingIndicator();
            }
            if (vm.error != null) {
              return _buildErrorView(vm.error!);
            }
            if (vm.speeches.isEmpty) {
              return _buildEmptyView();
            }
            return _buildTranscriptList(vm);
          },
        ),
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
            'No sitting data available for this date.',
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
        final member = vm.memberFor(speech.memberId);
        return RepaintBoundary(
          child: SpeechBlock(speech: speech, member: member),
        );
      },
    );
  }

  // ─── Speaker drawer ─────────────────────────────────────────────────────────

  void _openSpeakerDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _buildSpeakerDrawer() {
    return Consumer<TranscriptViewModel>(
      builder: (context, vm, _) {
        return Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Jump to Speaker',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: vm.speakers.length,
                    itemBuilder: (context, index) {
                      final speaker = vm.speakers[index];
                      final member = vm.memberFor(speaker.memberId);
                      return ListTile(
                        title: Text(speaker.name),
                        subtitle: member?.party.isNotEmpty == true
                            ? Text(member!.party)
                            : null,
                        onTap: () {
                          Navigator.of(context).pop(); // close drawer
                          _scrollToSpeaker(speaker.firstSpeechIndex);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToSpeaker(int index) {
    _scrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }
}
