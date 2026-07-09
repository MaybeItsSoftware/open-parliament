import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Circular portrait for any person (MP, Lord, councillor, speaker). Falls
/// back to a colour-tinted initials circle when [imageUrl] is null/empty or
/// the network image fails to load.
class PersonAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final Color color;
  final double size;

  const PersonAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => _initialsAvatar(theme, color, name, size),
            errorWidget: (_, __, ___) =>
                _initialsAvatar(theme, color, name, size),
          ),
        ),
      );
    }
    return _initialsAvatar(theme, color, name, size);
  }
}

Widget _initialsAvatar(
  ThemeData theme,
  Color color,
  String name,
  double diameter,
) {
  final initials = _initials(name);
  return CircleAvatar(
    radius: diameter / 2,
    backgroundColor: color.withValues(alpha: 0.2),
    child: Text(
      initials,
      style: TextStyle(
        fontSize: diameter * 0.35,
        fontWeight: FontWeight.bold,
        color: _foregroundFor(color, theme),
      ),
    ),
  );
}

String _initials(String name) {
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
