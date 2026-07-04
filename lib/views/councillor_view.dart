import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/councillor.dart';
import '../models/councillor_profile.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/area_match.dart';
import '../utils/party_colors.dart' as party_util;
import 'party_view.dart';

/// Profile page for a single councillor.
///
/// The core facts (name, ward, party, role, next-election) come from
/// OpenCouncilData; a photo, email, social links and "first elected" are
/// enriched lazily from Democracy Club and only appear when a match is found.
class CouncillorView extends StatefulWidget {
  final Councillor councillor;

  const CouncillorView({super.key, required this.councillor});

  @override
  State<CouncillorView> createState() => _CouncillorViewState();
}

class _CouncillorViewState extends State<CouncillorView> {
  late final Future<CouncillorProfile?> _profile;

  Councillor get councillor => widget.councillor;

  @override
  void initState() {
    super.initState();
    _profile = context
        .read<ParliamentaryDataService>()
        .fetchCouncillorProfile(councillor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCity = isCityOfLondonCouncil(councillor.council);
    final displayParty =
        councillor.party.isNotEmpty || !isCity ? councillor.party : 'Independent';
    final color = party_util.partyColor(displayParty);
    final fg = party_util.foregroundForParty(color);

    return Scaffold(
      body: FutureBuilder<CouncillorProfile?>(
        future: _profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: color,
                foregroundColor: fg,
                expandedHeight: 120,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsetsDirectional.only(
                      start: 56, bottom: 14, end: 16),
                  title: Text(
                    councillor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _body(
                  context,
                  theme,
                  color,
                  displayParty,
                  isCity,
                  profile,
                  loading: snapshot.connectionState != ConnectionState.done,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ThemeData theme,
    Color color,
    String displayParty,
    bool isCity,
    CouncillorProfile? profile, {
    required bool loading,
  }) {
    final enriched = profile != null && !profile.isEmpty;
    final hasPhoto =
        profile?.thumbnailUrl != null || profile?.imageUrl != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (hasPhoto) ...[
            Center(child: _photo(color, profile!)),
            const SizedBox(height: 16),
          ],
          if (displayParty.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: InkWell(
                onTap: () => _openPartyPage(context, displayParty),
                child: Text(
                  displayParty,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (councillor.ward.isNotEmpty)
            _fact(theme, Icons.map_outlined, 'Ward', councillor.ward),
          if (councillor.council.isNotEmpty)
            _fact(theme, Icons.account_balance_outlined, 'Council',
                councillor.council),
          if (isCity || councillor.role != CouncillorRole.councillor)
            _fact(theme, Icons.badge_outlined, 'Role', councillor.roleLabel),
          if (councillor.memberships.isNotEmpty)
            _fact(
              theme,
              Icons.groups_outlined,
              councillor.memberships.length > 1 ? 'Memberships' : 'Membership',
              councillor.memberships.join(' · '),
            ),
          if (_termLabel(isCity) != null)
            _fact(theme, Icons.calendar_today_outlined, 'Term length',
                _termLabel(isCity)!),
          if (isCity && councillor.isPaid == false)
            _fact(theme, Icons.volunteer_activism_outlined, 'Allowance',
                'Unpaid (voluntary role)'),
          if (profile?.firstElectedYear != null)
            _fact(theme, Icons.how_to_vote_outlined, 'First elected',
                '${profile!.firstElectedYear}'),
          if (councillor.nextElection != null)
            _fact(theme, Icons.event_outlined, 'Next election',
                _formatDate(councillor.nextElection!)),
          if (profile?.email != null)
            _fact(theme, Icons.email_outlined, 'Email', profile!.email!,
                onTap: () => _launch(context, 'mailto:${profile.email}')),
          if (profile != null && profile.links.isNotEmpty) ...[
            const SizedBox(height: 8),
            _links(context, profile.links),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _search(context),
            icon: const Icon(Icons.search),
            label: const Text('Search the web for this councillor'),
          ),
          const SizedBox(height: 16),
          Text(
            enriched
                ? 'Sources: OpenCouncilData (CC BY-SA 4.0); photo & contacts '
                    'from Democracy Club (CC BY 4.0).'
                : 'Source: OpenCouncilData (CC BY-SA 4.0). No Democracy Club '
                    'match found for a photo or contacts.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (isCity) ...[
            const SizedBox(height: 8),
            Text(
              'City of London elections differ: Aldermen hold rolling '
              'six-year terms alongside four-year Common Councillor terms.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openPartyPage(BuildContext context, String partyName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartyView(partyName: partyName),
      ),
    );
  }

  Widget _photo(Color color, CouncillorProfile profile) {
    final url = profile.thumbnailUrl ?? profile.imageUrl!;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox(
            width: 120,
            height: 120,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) =>
              const Icon(Icons.person, size: 64, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _links(BuildContext context, List<SocialLink> links) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final link in links)
          ActionChip(
            avatar: const Icon(Icons.link, size: 18),
            label: Text(link.label),
            onPressed: () => _launch(context, link.url),
          ),
      ],
    );
  }

  String? _termLabel(bool isCity) {
    final years = councillor.termYears;
    if (years == null) return null;
    if (isCity && councillor.role == CouncillorRole.alderman) {
      return '$years years (rolling)';
    }
    return '$years years';
  }

  Widget _fact(ThemeData theme, IconData icon, String label, String value,
      {VoidCallback? onTap}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(value,
                    style: theme.textTheme.bodyLarge?.copyWith(
                        color:
                            onTap != null ? theme.colorScheme.primary : null)),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }

  Future<void> _launch(BuildContext context, String url) async {
    // `url` can come from Democracy Club (councillor social links), a
    // third-party source we don't validate — guard against a malformed URL
    // rather than letting Uri.parse throw out of this tap handler.
    final uri = Uri.tryParse(url);
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that link.')),
      );
    }
  }

  Future<void> _search(BuildContext context) async {
    final query = Uri.encodeQueryComponent(
      '${councillor.name} councillor ${councillor.council}',
    );
    await _launch(context, 'https://duckduckgo.com/?q=$query');
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
