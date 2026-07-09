import 'package:flutter/material.dart';

/// Splits [text] into spans, wrapping every case-insensitive occurrence of
/// [query] with [highlightStyle] merged over [style]. Used to mark
/// find-in-transcript search matches inline within speech text and speaker
/// names. Returns a single unhighlighted span when [query] is empty.
List<InlineSpan> highlightedSpans({
  required String text,
  required String query,
  TextStyle? style,
  required TextStyle highlightStyle,
}) {
  final needle = query.trim();
  if (needle.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final lowerText = text.toLowerCase();
  final lowerNeedle = needle.toLowerCase();
  final spans = <InlineSpan>[];
  var start = 0;
  while (true) {
    final index = lowerText.indexOf(lowerNeedle, start);
    if (index < 0) {
      spans.add(TextSpan(text: text.substring(start), style: style));
      break;
    }
    if (index > start) {
      spans.add(TextSpan(text: text.substring(start, index), style: style));
    }
    spans.add(
      TextSpan(
        text: text.substring(index, index + needle.length),
        style: style?.merge(highlightStyle) ?? highlightStyle,
      ),
    );
    start = index + needle.length;
  }
  return spans;
}

/// Drop-in replacement for [Text] that highlights occurrences of [query]
/// (typically the active find-in-transcript search term).
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final TextAlign? textAlign;

  const HighlightedText(
    this.text, {
    super.key,
    required this.query,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return Text(text, style: style, textAlign: textAlign);
    }
    final theme = Theme.of(context);
    final highlightStyle = TextStyle(
      backgroundColor: theme.colorScheme.tertiaryContainer,
      color: theme.colorScheme.onTertiaryContainer,
      fontWeight: FontWeight.bold,
    );
    return Text.rich(
      TextSpan(
        children: highlightedSpans(
          text: text,
          query: query,
          style: style,
          highlightStyle: highlightStyle,
        ),
      ),
      textAlign: textAlign,
    );
  }
}
