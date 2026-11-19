import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../models/member_contribution.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/member_speeches_viewmodel.dart';
import '../widgets/contribution_tile.dart';
import 'transcript_view.dart';

/// Opens the transcript at [c]: narrowed to its debate and scrolled to the
/// speech itself.
void openContribution(BuildContext context, MemberContribution c) {
  final d = c.sittingDate;
  final date =
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TranscriptView(
        date: date,
        displayDate: formatContributionDate(d),
        initialDebateId: c.debateSectionId.isNotEmpty ? c.debateSectionId : null,
        initialSpeechId: c.speechId.isNotEmpty ? c.speechId : null,
      ),
    ),
  );
}

/// Every spoken contribution a member has made, newest first, paged in as
/// the list scrolls. Tapping one opens the transcript at that speech.
class MemberSpeechesView extends StatefulWidget {
  final Member member;

  const MemberSpeechesView({super.key, required this.member});

  @override
  State<MemberSpeechesView> createState() => _MemberSpeechesViewState();
}

class _MemberSpeechesViewState extends State<MemberSpeechesView> {
  late final MemberSpeechesViewModel _vm;
  final ScrollController _scroll = ScrollController();

  // Distance from the bottom at which the next page is requested.
  static const double _loadMoreThreshold = 600;

  @override
  void initState() {
    super.initState();
    _vm = MemberSpeechesViewModel(
      context.read<ParliamentaryDataService>(),
      member: widget.member,
    );
    unawaited(_vm.refresh());
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - _loadMoreThreshold) {
      unawaited(_vm.loadMore());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final accent = party_util.partyColor(
      m.partyAbbreviation.isNotEmpty ? m.partyAbbreviation : m.party,
    );
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<MemberSpeechesViewModel>(
        builder: (context, vm, _) {
          final theme = Theme.of(context);
          final speeches = vm.speeches;
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name),
                  if (vm.total > 0)
                    Text(
                      '${_grouped(vm.total)} speeches in Hansard',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            body: RefreshIndicator(
              onRefresh: vm.refresh,
              child: speeches.isEmpty
                  ? ListView(
                      // Scrollable so pull-to-refresh works when empty.
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: vm.isLoading
                                ? const CircularProgressIndicator()
                                : Text(
                                    vm.failed
                                        ? "Couldn't load speeches. Pull to retry."
                                        : 'No recorded speeches.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: speeches.length + (vm.hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == speeches.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final c = speeches[i];
                        return ContributionTile(
                          contribution: c,
                          accentColor: accent,
                          onTap: () => openContribution(context, c),
                        );
                      },
                    ),
            ),
          );
        },
      ),
    );
  }

  static String _grouped(int n) => n.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
}
