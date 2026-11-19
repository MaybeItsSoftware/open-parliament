import 'package:flutter/material.dart';

import '../models/member_contribution.dart';

/// One spoken contribution in a member's speech list: debate title, venue and
/// date, and the opening of what they said. Used on the member profile and
/// the full "All speeches" list.
class ContributionTile extends StatelessWidget {
  final MemberContribution contribution;

  /// Tints the venue/date line (the member's party colour).
  final Color accentColor;
  final VoidCallback onTap;

  const ContributionTile({
    super.key,
    required this.contribution,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = contribution;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.debateTitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${c.venue} · ${formatContributionDate(c.sittingDate)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (c.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                c.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Divider(height: 20),
          ],
        ),
      ),
    );
  }
}

/// "11 Nov 2026".
String formatContributionDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
