/// A single broadcast event on parliamentlive.tv.
///
/// Each Parliament-Live event corresponds to one continuous video stream
/// (a chamber sitting, a committee session, a Westminster Hall debate, etc.)
/// and is identified by a stable GUID assigned by parliamentlive.tv.
class ParliamentLiveEvent {
  final String guid;
  final String title;

  const ParliamentLiveEvent({
    required this.guid,
    required this.title,
  });

  /// Top-level page for this event.
  Uri get url => Uri.parse('https://parliamentlive.tv/event/index/$guid');

  /// Deep-link that scrubs the player to [timecode] (`HH:MM:SS`).
  Uri urlAt(String timecode) {
    return url.replace(queryParameters: {'in': timecode});
  }

  @override
  bool operator ==(Object other) =>
      other is ParliamentLiveEvent && other.guid == guid;

  @override
  int get hashCode => guid.hashCode;

  @override
  String toString() => 'ParliamentLiveEvent($guid, $title)';
}
