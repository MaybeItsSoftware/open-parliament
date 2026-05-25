import 'package:flutter/material.dart';

import '../../utils/committee_roster.dart';
import '../../utils/party_colors.dart' as party_util;

/// Structured card for "The Committee consisted of the following Members:"
/// blocks. Replaces a long italic paragraph with a chair pill row,
/// per-member rows with party badges, and a clerks footer.
class CommitteeRosterCard extends StatelessWidget {
  final CommitteeRoster roster;

  const CommitteeRosterCard({super.key, required this.roster});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Committee membership',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (roster.chairs.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ChairsRow(chairs: roster.chairs),
              ],
              if (roster.members.isNotEmpty) ...[
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 560;
                    return _MemberList(
                      members: roster.members,
                      twoCol: twoCol,
                    );
                  },
                ),
              ],
              if (roster.clerks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: theme.dividerColor),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Clerks: ',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: roster.clerks),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (roster.attendedAny) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'attended the Committee',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChairsRow extends StatelessWidget {
  final List<CommitteeChair> chairs;
  const _ChairsRow({required this.chairs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            chairs.length == 1 ? 'Chair' : 'Chairs',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chair in chairs)
                _ChairPill(name: chair.name, attended: chair.attended),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberList extends StatelessWidget {
  final List<CommitteeMember> members;
  final bool twoCol;
  const _MemberList({required this.members, required this.twoCol});

  @override
  Widget build(BuildContext context) {
    if (!twoCol) {
      return Column(
        children: [
          for (final m in members) _MemberRow(member: m),
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < members.length; i += 2) {
      final left = members[i];
      final right = i + 1 < members.length ? members[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MemberRow(member: left)),
            const SizedBox(width: 8),
            Expanded(
              child: right != null
                  ? _MemberRow(member: right)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

class _ChairPill extends StatelessWidget {
  final String name;
  final bool attended;
  const _ChairPill({required this.name, required this.attended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attended) ...[
              Icon(
                Icons.check_circle,
                size: 12,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final CommitteeMember member;
  const _MemberRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partyColor = party_util.partyColor(
      member.party,
      fallback: theme.colorScheme.outline,
    );
    final hasParty = member.party.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: partyColor, width: 3),
          ),
          color: hasParty
              ? partyColor.withValues(alpha: 0.06)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 14,
                child: member.attended
                    ? Icon(
                        Icons.check_circle,
                        size: 12,
                        color: theme.colorScheme.primary,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (member.constituency.isNotEmpty)
                      Text(
                        member.constituency,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (member.role.isNotEmpty)
                      Text(
                        member.role,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              if (hasParty) ...[
                const SizedBox(width: 6),
                _PartyBadge(party: member.party, color: partyColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PartyBadge extends StatelessWidget {
  final String party;
  final Color color;
  const _PartyBadge({required this.party, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : theme.colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          party,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: fg,
          ),
        ),
      ),
    );
  }
}
