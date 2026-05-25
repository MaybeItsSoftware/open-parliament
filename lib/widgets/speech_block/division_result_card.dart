import 'package:flutter/material.dart';

import '../../utils/house_colors.dart';

/// Renders the structured "Division" (vote result) card.
///
/// The raw `Speech.speechText` for a division is encoded by Hansard as a
/// pipe-delimited string: `index|time|ayes|noes|description|result||ayes|noes`.
/// This widget parses the leading fields and renders the totals; speaker
/// lists are intentionally omitted (too noisy in transcript flow).
class DivisionResultCard extends StatelessWidget {
  final String rawSpeechText;

  const DivisionResultCard({super.key, required this.rawSpeechText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = rawSpeechText.trim().split('|');
    final ayes = parts.length > 2 ? int.tryParse(parts[2]) : null;
    final noes = parts.length > 3 ? int.tryParse(parts[3]) : null;
    final description = parts.length > 4 ? parts[4].trim() : 'Division';
    final result = parts.length > 5 ? parts[5].trim() : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.how_to_vote_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Division',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (ayes != null && noes != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _DivisionCount(
                      label: 'Ayes',
                      count: ayes,
                      color: HouseColors.commons,
                    ),
                    const SizedBox(width: 16),
                    _DivisionCount(
                      label: 'Noes',
                      count: noes,
                      color: HouseColors.lords,
                    ),
                  ],
                ),
              ],
              if (result.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  result,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DivisionCount extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DivisionCount({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: $count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}
