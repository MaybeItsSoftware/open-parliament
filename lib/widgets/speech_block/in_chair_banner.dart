import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../utils/party_colors.dart' as party_util;

/// Divider banner shown for "[Name in the Chair]" rows in committee sittings.
class InChairBanner extends StatelessWidget {
  final String chairName;
  final Member? member;
  final VoidCallback? onMemberTap;

  const InChairBanner({
    super.key,
    required this.chairName,
    required this.member,
    this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party ?? '');
    final partyColor = party_util.partyColor(
      partyKey,
      fallback: theme.colorScheme.outline,
    );
    final url = member?.thumbnailUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.dividerColor)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onMemberTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: partyColor, width: 2),
                  ),
                  child: ClipOval(
                    child: url != null && url.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: url,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                _initialsAvatar(theme, partyColor, chairName),
                            errorWidget: (_, __, ___) =>
                                _initialsAvatar(theme, partyColor, chairName),
                          )
                        : _initialsAvatar(theme, partyColor, chairName),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chairName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'in the Chair',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.dividerColor)),
        ],
      ),
    );
  }

  Widget _initialsAvatar(ThemeData theme, Color partyColor, String name) {
    final initials = _initialsFor(name);
    return CircleAvatar(
      radius: 18,
      backgroundColor: partyColor.withValues(alpha: 0.2),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _foregroundFor(partyColor, theme),
        ),
      ),
    );
  }
}

String _initialsFor(String name) {
  if (name.isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

Color _foregroundFor(Color background, ThemeData theme) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  return brightness == Brightness.dark
      ? Colors.white
      : theme.colorScheme.onSurface;
}
