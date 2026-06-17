import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/house_colors.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/bill_viewmodel.dart';
import 'member_view.dart';

/// Detail page for a single bill.
class BillView extends StatefulWidget {
  final String billTitle;
  final int? billId;

  const BillView({super.key, required this.billTitle, this.billId});

  @override
  State<BillView> createState() => _BillViewState();
}

class _BillViewState extends State<BillView> {
  late BillViewModel _vm;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _vm = BillViewModel(
      context.read<ParliamentaryDataService>(),
      billTitle: widget.billTitle,
      billId: widget.billId,
    );
    unawaited(_vm.load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _vm.dispose();
    super.dispose();
  }

  Color _houseColor(String? house) {
    return switch (house?.toLowerCase()) {
      'lords' => HouseColors.lords,
      'commons' => HouseColors.commons,
      _ => HouseColors.mixed,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<BillViewModel>(
        builder: (context, vm, _) {
          final hColor = _houseColor(vm.bill?.currentHouse);
          final fgColor = party_util.foregroundForParty(hColor);
          final title = vm.bill?.shortTitle ?? widget.billTitle;

          return Scaffold(
            appBar: AppBar(
              backgroundColor: hColor,
              foregroundColor: fgColor,
              iconTheme: IconThemeData(color: fgColor),
              title: Row(
                children: [
                  const Icon(Icons.article_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            body: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : vm.error != null && vm.bill == null
                    ? _buildError(vm)
                    : ListView(
                        controller: _scrollController,
                        children: [
                          _buildInfoSection(context, vm),
                          if (vm.bill?.sponsors.isNotEmpty == true)
                            _buildSponsors(context, vm),
                          if (vm.news.isNotEmpty) ...[
                            _sectionHeader(context, 'Latest Updates'),
                            ...vm.news.map((n) => _buildNewsTile(context, n)),
                          ],
                          if (vm.stages.isNotEmpty) ...[
                            _sectionHeader(context, 'Progress'),
                            ...vm.stages.asMap().entries.map(
                                  (e) => _buildStageTile(
                                    context,
                                    e.value,
                                    hColor,
                                    isLast: e.key == vm.stages.length - 1,
                                  ),
                                ),
                          ],
                          if (vm.billPageUrl != null)
                            _buildExternalLink(context, vm),
                          const SizedBox(height: 40),
                        ],
                      ),
          );
        },
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, BillViewModel vm) {
    final theme = Theme.of(context);
    final bill = vm.bill;
    final description = (bill?.summary?.trim().isNotEmpty == true)
        ? bill!.summary!.trim()
        : (bill?.longTitle ?? '');
    final detailRows = <Widget>[];

    if (bill?.originatingHouse.isNotEmpty == true) {
      detailRows.add(
        _detailRow(
          context,
          Icons.flag_outlined,
          'Originating house',
          bill!.originatingHouse,
        ),
      );
    }

    final billType = vm.billType;
    if (billType != null) {
      final value = [
        if (billType.category.isNotEmpty) billType.category,
        if (billType.name.isNotEmpty) billType.name,
      ].join(' · ');
      if (value.isNotEmpty) {
        detailRows.add(
          _detailRow(
            context,
            Icons.local_offer_outlined,
            'Bill type',
            value,
          ),
        );
      }
    }

    if (bill?.formerShortTitle?.trim().isNotEmpty == true) {
      detailRows.add(
        _detailRow(
          context,
          Icons.history,
          'Former title',
          bill!.formerShortTitle!.trim(),
        ),
      );
    }

    final (statusLabel, statusColor) = switch (bill?.status) {
      BillStatus.act => ('Royal Assent — now an Act', HouseColors.commons),
      BillStatus.defeated => ('Defeated', HouseColors.lords),
      BillStatus.withdrawn => ('Withdrawn', theme.colorScheme.outline),
      _ => ('In progress', theme.colorScheme.primary),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, statusLabel, statusColor, filled: true),
              if (bill?.currentHouse.isNotEmpty == true)
                _chip(context, bill!.currentHouse, _houseColor(bill.currentHouse)),
              if (bill?.currentStageDescription?.isNotEmpty == true)
                _chip(
                  context,
                  bill!.currentStageDescription!,
                  theme.colorScheme.outline,
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
          if (detailRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < detailRows.length; i++) ...[
              detailRows[i],
              if (i != detailRows.length - 1) const SizedBox(height: 6),
            ],
          ],
          if (vm.bill?.lastUpdate != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.update,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Last updated ${_formatDate(vm.bill!.lastUpdate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    Color color, {
    bool filled = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $value',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSponsors(BuildContext context, BillViewModel vm) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vm.bill!.sponsors.length > 1 ? 'Sponsors' : 'Sponsor',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...vm.bill!.sponsors.map((s) => _buildSponsorRow(context, s)),
        ],
      ),
    );
  }

  Widget _buildSponsorRow(BuildContext context, BillSponsor sponsor) {
    final theme = Theme.of(context);
    final pColor = party_util.partyColor(sponsor.party ?? '');
    final subtitle = [
      if (sponsor.party?.isNotEmpty == true) sponsor.party!,
      if (sponsor.constituency?.isNotEmpty == true) sponsor.constituency!,
    ].join(' · ');

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: pColor.withValues(alpha: 0.2),
            backgroundImage:
                (sponsor.photoUrl != null && sponsor.photoUrl!.isNotEmpty)
                    ? CachedNetworkImageProvider(sponsor.photoUrl!)
                    : null,
            child: (sponsor.photoUrl == null || sponsor.photoUrl!.isEmpty)
                ? Icon(Icons.person, color: pColor)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sponsor.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (sponsor.memberId != null)
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (sponsor.memberId == null) return row;
    return InkWell(
      onTap: () => _openMember(context, sponsor),
      child: row,
    );
  }

  Widget _buildNewsTile(BuildContext context, BillNews news) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (news.date != null)
            Text(
              _formatDate(news.date!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (news.title.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              news.title,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (news.content.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(news.content, style: theme.textTheme.bodySmall),
          ],
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _buildStageTile(
    BuildContext context,
    BillStage stage,
    Color hColor, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final dotColor =
        stage.isCurrent ? hColor : theme.colorScheme.outlineVariant;

    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: stage.isCurrent
                        ? Border.all(color: hColor.withValues(alpha: 0.3), width: 4)
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: stage.isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (stage.house.isNotEmpty) stage.house,
                        if (stage.date != null) _formatDate(stage.date!),
                        if (stage.isCurrent) 'current stage',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: stage.isCurrent
                            ? hColor
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            stage.isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalLink(BuildContext context, BillViewModel vm) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: OutlinedButton.icon(
        onPressed: () => unawaited(
          launchUrl(vm.billPageUrl!, mode: LaunchMode.externalApplication),
        ),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('View on bills.parliament.uk'),
      ),
    );
  }

  Widget _buildError(BillViewModel vm) {
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
            const SizedBox(height: 12),
            Text(vm.error ?? 'Could not load bill details.'),
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

  void _openMember(BuildContext context, BillSponsor sponsor) {
    final member = Member(
      id: sponsor.memberId!,
      name: sponsor.name,
      party: sponsor.party ?? '',
      partyAbbreviation: '',
      thumbnailUrl: sponsor.photoUrl,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberView(member: member)),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
