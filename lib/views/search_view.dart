import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/councillor.dart';
import '../models/councillor_profile.dart';
import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/area_match.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/search_viewmodel.dart';
import '../widgets/person_avatar.dart';
import 'app_drawer.dart';
import 'bill_view.dart';
import 'council_view.dart';
import 'member_view.dart';
import 'transcript_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late SearchViewModel _vm;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = SearchViewModel(context.read<ParliamentaryDataService>());
    _controller.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _vm.updateQuery(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SearchViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Search')),
            drawer: const AppDrawer(current: AppDestination.search),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText:
                          'MPs, Lords, councillors, bills, debates, constituencies',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: vm.query.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () => _controller.clear(),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (vm.isLoading)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _buildResults(context, vm)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResults(BuildContext context, SearchViewModel vm) {
    if (vm.query.trim().isEmpty) {
      return _buildPrompt(
        context,
        'Start typing to search across MPs, Lords, councillors, bills, debates, and constituencies.',
      );
    }
    if (vm.isQueryShort) {
      return _buildPrompt(
        context,
        'Type at least 2 characters to search.',
      );
    }

    final results = vm.results;
    final children = <Widget>[];

    if (vm.error != null) {
      children.add(_buildErrorBanner(context, vm.error!));
      children.add(const SizedBox(height: 12));
    }

    if (results.isEmpty && !vm.isLoading) {
      children.add(_buildPrompt(context, 'No results found.'));
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: children,
      );
    }

    _addSection(
      context,
      children,
      title: 'Members',
      count: results.members.length,
      tiles: [
        for (final member in results.members)
          _memberTile(context, member: member),
      ],
    );

    _addSection(
      context,
      children,
      title: 'Constituencies',
      count: results.constituencies.length,
      tiles: [
        for (final constituency in results.constituencies)
          _constituencyTile(context, constituency: constituency),
      ],
    );

    _addSection(
      context,
      children,
      title: 'Councillors',
      count: results.councillors.length,
      tiles: [
        for (final councillor in results.councillors)
          _councillorTile(context, vm: vm, result: councillor),
      ],
      footer: results.councillors.isNotEmpty
          ? 'Source: OpenCouncilData (CC BY-SA 4.0)'
          : null,
    );

    _addSection(
      context,
      children,
      title: 'Bills',
      count: results.bills.length,
      tiles: [
        for (final bill in results.bills) _billTile(context, bill: bill),
      ],
    );

    _addSection(
      context,
      children,
      title: 'Debates',
      count: results.debates.length,
      tiles: [
        for (final debate in results.debates)
          _debateTile(context, debate: debate),
      ],
      footer: results.debates.isNotEmpty
          ? 'Debates are searched from cached sittings only.'
          : null,
    );

    if (children.isEmpty && vm.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: children,
    );
  }

  Widget _buildPrompt(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _addSection(
    BuildContext context,
    List<Widget> children, {
    required String title,
    required int count,
    required List<Widget> tiles,
    String? footer,
  }) {
    if (tiles.isEmpty) return;
    children.add(_sectionHeader(context, title, count));
    children.addAll(tiles);
    if (footer != null) {
      children.add(const SizedBox(height: 6));
      children.add(
        Text(
          footer,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    children.add(const SizedBox(height: 16));
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$title ($count)',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _memberTile(BuildContext context, {required Member member}) {
    final isLord = member.constituency.isEmpty;
    final parts = <String>[];
    if (member.party.isNotEmpty) parts.add(member.party);
    if (isLord) {
      parts.add('House of Lords');
    } else if (member.constituency.isNotEmpty) {
      parts.add('MP for ${member.constituency}');
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _memberAvatar(member),
      title: Text(member.name),
      subtitle: parts.isNotEmpty ? Text(parts.join(' · ')) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberView(member: member)),
      ),
    );
  }

  Widget _memberAvatar(Member member) {
    final partyKey =
        member.partyAbbreviation.isNotEmpty ? member.partyAbbreviation : member.party;
    return PersonAvatar(
      imageUrl: member.thumbnailUrl,
      name: member.name,
      color: party_util.partyColor(partyKey),
    );
  }

  Widget _constituencyTile(
    BuildContext context, {
    required ConstituencySearchResult constituency,
  }) {
    final subtitleParts = <String>[
      'MP: ${constituency.member.name}',
    ];
    if (constituency.member.party.isNotEmpty) {
      subtitleParts.add(constituency.member.party);
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _memberAvatar(constituency.member),
      title: Text(constituency.name),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberView(member: constituency.member)),
      ),
    );
  }

  Widget _councillorTile(
    BuildContext context, {
    required SearchViewModel vm,
    required CouncillorSearchResult result,
  }) {
    final councillor = result.councillor;
    final subtitleParts = <String>[];
    if (councillor.role != CouncillorRole.councillor) {
      subtitleParts.add(councillor.roleLabel);
    }
    if (councillor.council.isNotEmpty) subtitleParts.add(councillor.council);
    if (councillor.ward.isNotEmpty) subtitleParts.add(councillor.ward);
    final displayParty =
        councillor.party.isNotEmpty || !isCityOfLondonCouncil(councillor.council)
            ? councillor.party
            : 'Independent';
    if (displayParty.isNotEmpty) subtitleParts.add(displayParty);
    final council = result.council;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: FutureBuilder<CouncillorProfile?>(
        future: vm.profileFor(councillor),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          return PersonAvatar(
            imageUrl: profile?.thumbnailUrl ?? profile?.imageUrl,
            name: councillor.name,
            color: party_util.partyColor(displayParty),
          );
        },
      ),
      title: Text(councillor.name),
      subtitle: subtitleParts.isNotEmpty ? Text(subtitleParts.join(' · ')) : null,
      trailing:
          council != null ? const Icon(Icons.chevron_right) : const SizedBox(),
      onTap: council == null
          ? null
          : () {
              final list = vm.councillorsForCouncil(councillor.council);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CouncilView(
                    council: council,
                    councillors: Future<List<Councillor>>.value(list),
                  ),
                ),
              );
            },
    );
  }

  Widget _billTile(BuildContext context, {required BillSearchResult bill}) {
    final subtitleParts = <String>[];
    if (bill.house.isNotEmpty) subtitleParts.add(bill.house);
    if (bill.stage?.isNotEmpty == true) subtitleParts.add(bill.stage!);
    if (bill.lastUpdate != null) {
      subtitleParts.add('Updated ${_shortDate(bill.lastUpdate!)}');
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.article_outlined),
      title: Text(bill.title),
      subtitle: subtitleParts.isNotEmpty ? Text(subtitleParts.join(' · ')) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BillView(billTitle: bill.title, billId: bill.id),
        ),
      ),
    );
  }

  Widget _debateTile(
    BuildContext context, {
    required DebateSearchResult debate,
  }) {
    final subtitleParts = <String>[];
    final date = debate.dateValue;
    if (date != null) subtitleParts.add(_shortDate(date));
    if (debate.house.isNotEmpty) subtitleParts.add(debate.house);
    if (debate.section?.isNotEmpty == true) subtitleParts.add(debate.section!);
    final displayDate = date != null ? _friendlyDate(date) : debate.date;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.forum_outlined),
      title: Text(debate.title),
      subtitle: subtitleParts.isNotEmpty ? Text(subtitleParts.join(' · ')) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TranscriptView(
            date: debate.date,
            displayDate: displayDate,
            initialDebateId: debate.debateId,
          ),
        ),
      ),
    );
  }

  static String _shortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

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
