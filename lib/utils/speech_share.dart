/// Formats a speech into plain text suitable for the clipboard or share sheet.
///
/// Shape:
///
///     Jane Smith
///     "…the speech body…"
///
///     — Debate title · 25 May 2026, Hansard
String buildSpeechShareText({
  required String speakerName,
  required String speechText,
  required String debateTitle,
  required String displayDate,
}) {
  final buf = StringBuffer();
  final speaker = speakerName.trim();
  if (speaker.isNotEmpty) buf.writeln(speaker);
  buf.writeln(speechText.trim());

  final context = [debateTitle.trim(), displayDate.trim()]
      .where((s) => s.isNotEmpty)
      .join(' · ');
  if (context.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('— $context, Hansard');
  }
  return buf.toString().trim();
}
