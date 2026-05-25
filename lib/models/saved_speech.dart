/// A speech the user has bookmarked from a transcript.
///
/// This is a self-contained snapshot: it stores the text and the context
/// needed to display and re-locate the speech without re-fetching the sitting.
class SavedSpeech {
  /// The originating `Speech.id`. Used as the bookmark's unique key.
  final String speechId;

  /// Sitting date in `YYYY-MM-DD` form (matches the cache key / route arg).
  final String date;

  /// Human-readable sitting date, e.g. "25 May 2026".
  final String displayDate;

  final String debateId;
  final String debateTitle;
  final String speakerName;
  final String speechText;

  /// When the user saved it; used to order the Saved screen newest-first.
  final DateTime savedAt;

  const SavedSpeech({
    required this.speechId,
    required this.date,
    required this.displayDate,
    required this.debateId,
    required this.debateTitle,
    required this.speakerName,
    required this.speechText,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'speechId': speechId,
        'date': date,
        'displayDate': displayDate,
        'debateId': debateId,
        'debateTitle': debateTitle,
        'speakerName': speakerName,
        'speechText': speechText,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedSpeech.fromJson(Map<String, dynamic> json) => SavedSpeech(
        speechId: json['speechId'] as String? ?? '',
        date: json['date'] as String? ?? '',
        displayDate: json['displayDate'] as String? ?? '',
        debateId: json['debateId'] as String? ?? '',
        debateTitle: json['debateTitle'] as String? ?? '',
        speakerName: json['speakerName'] as String? ?? '',
        speechText: json['speechText'] as String? ?? '',
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
