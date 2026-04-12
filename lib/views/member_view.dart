import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/member_viewmodel.dart';
import 'transcript_view.dart';

/// Profile page for a single parliamentary member.
///
/// Shows portrait, party, constituency, constituency map (Commons MPs),
/// posts held, and recent Hansard contributions.
class MemberView extends StatefulWidget {
  final Member member;

  const MemberView({super.key, required this.member});

  @override
  State<MemberView> createState() => _MemberViewState();
}

class _MemberViewState extends State<MemberView> {
  late MemberViewModel _vm;
  final ScrollController _scrollController = ScrollController();
  bool _titleVisible = false;

  // The app bar title fades in once the flexible space has mostly collapsed.
  static const double _collapseThreshold = 160;

  @override
  void initState() {
    super.initState();
    _vm = MemberViewModel(member: widget.member);
    unawaited(_vm.load());
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > _collapseThreshold;
    if (collapsed != _titleVisible) {
      setState(() => _titleVisible = collapsed);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<MemberViewModel>(
        builder: (context, vm, _) {
          final pColor = party_util.partyColor(
            vm.member.partyAbbreviation.isNotEmpty
                ? vm.member.partyAbbreviation
                : vm.member.party,
          );
          final fgColor = party_util.foregroundForParty(pColor);

          return Scaffold(
            body: CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildAppBar(vm, pColor, fgColor),
                if (vm.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (vm.error != null)
                  SliverFillRemaining(child: _buildError(vm))
                else ...[
                  SliverToBoxAdapter(
                    child: _buildInfoSection(context, vm, pColor),
                  ),
                  if (vm.constituencyLatLng != null)
                    SliverToBoxAdapter(
                      child: _buildConstituencyMap(
                        context,
                        vm.constituencyLatLng!,
                        vm.constituency ?? '',
                        pColor,
                      ),
                    ),
                  if (vm.governmentPosts.isNotEmpty ||
                      vm.oppositionPosts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildPostsSection(context, vm, pColor),
                    ),
                  if (vm.contributions.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _sectionHeader(context, 'Recent Contributions'),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildContributionTile(
                          context,
                          vm.contributions[i],
                          pColor,
                        ),
                        childCount: vm.contributions.length,
                      ),
                    ),
                  ],
                  if (vm.contributions.isEmpty &&
                      vm.governmentPosts.isEmpty &&
                      vm.oppositionPosts.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No additional information available.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── App bar ──────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(MemberViewModel vm, Color pColor, Color fgColor) {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: pColor,
      iconTheme: IconThemeData(color: fgColor),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _buildHeaderBackground(vm, pColor, fgColor),
      ),
      // Title fades in once the flexible space has collapsed.
      title: AnimatedOpacity(
        opacity: _titleVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Text(
          vm.member.name,
          style: TextStyle(
            color: fgColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildHeaderBackground(
    MemberViewModel vm,
    Color pColor,
    Color fgColor,
  ) {
    final url = vm.member.thumbnailUrl;
    return Container(
      color: pColor,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: fgColor.withValues(alpha: 0.4),
                  width: 3,
                ),
              ),
              child: ClipOval(
                child: url != null && url.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            _initialsCircle(vm.member.name, pColor, fgColor),
                        errorWidget: (_, __, ___) =>
                            _initialsCircle(vm.member.name, pColor, fgColor),
                      )
                    : _initialsCircle(vm.member.name, pColor, fgColor),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                vm.member.name,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (vm.member.party.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                vm.member.party,
                style: TextStyle(
                  color: fgColor.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _initialsCircle(String name, Color bg, Color fg) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : '?';
    return Container(
      color: bg.withValues(alpha: 0.3),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: fg,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─── Info section ─────────────────────────────────────────────────────────

  Widget _buildInfoSection(
    BuildContext context,
    MemberViewModel vm,
    Color pColor,
  ) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final locationText = !vm.isLord && vm.constituency?.isNotEmpty == true
        ? 'MP for ${vm.constituency}'
        : vm.isLord
            ? 'Member of the House of Lords'
            : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vm.member.party.isNotEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: pColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: pColor.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Text(
                vm.member.party,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: pColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (locationText != null) ...[
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(locationText, style: subtitleStyle)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (vm.membershipStartDate != null)
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Member since ${vm.membershipStartDate!.year}',
                  style: subtitleStyle,
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ─── Constituency map ─────────────────────────────────────────────────────

  Widget _buildConstituencyMap(
    BuildContext context,
    LatLng center,
    String constituencyName,
    Color pColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 180,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 10.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'open_hansard',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.location_pin,
                      color: pColor,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Posts section ────────────────────────────────────────────────────────

  Widget _buildPostsSection(
    BuildContext context,
    MemberViewModel vm,
    Color pColor,
  ) {
    final theme = Theme.of(context);
    final allPosts = [
      ...vm.governmentPosts.map((p) => (post: p, isGov: true)),
      ...vm.oppositionPosts.map((p) => (post: p, isGov: false)),
    ]..sort((a, b) {
        final aDate = a.post.startDate;
        final bDate = b.post.startDate;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate); // newest first
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Posts Held',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...allPosts.map((entry) {
            final post = entry.post;
            final start = post.startDate?.year.toString();
            final end = post.isCurrent
                ? 'present'
                : post.endDate?.year.toString();
            final dateRange = (start != null && end != null)
                ? '$start – $end'
                : start ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(
                      color: post.isCurrent
                          ? pColor
                          : theme.colorScheme.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: post.isCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (dateRange.isNotEmpty)
                          Text(
                            dateRange,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Contributions ────────────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildContributionTile(
    BuildContext context,
    MemberContribution contrib,
    Color pColor,
  ) {
    final theme = Theme.of(context);
    final dateStr =
        '${contrib.house} · ${_formatDate(contrib.sittingDate)}';

    return InkWell(
      onTap: () => _openTranscript(context, contrib.sittingDate),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contrib.debateTitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              dateStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: pColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (contrib.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                contrib.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Divider(height: 20),
          ],
        ),
      ),
    );
  }

  // ─── Error state ──────────────────────────────────────────────────────────

  Widget _buildError(MemberViewModel vm) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Could not load member details.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => unawaited(vm.load()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _openTranscript(BuildContext context, DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TranscriptView(
          date: dateStr,
          displayDate: _formatDate(date),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
