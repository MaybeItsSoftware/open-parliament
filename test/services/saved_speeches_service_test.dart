import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/saved_speech.dart';
import 'package:open_hansard/services/saved_speeches_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedSpeech _speech(String id, {DateTime? savedAt}) => SavedSpeech(
      speechId: id,
      date: '2026-05-25',
      displayDate: '25 May 2026',
      debateId: 'deb-1',
      debateTitle: 'Finance Bill',
      speakerName: 'Jane Smith',
      speechText: 'I beg to move.',
      savedAt: savedAt ?? DateTime(2026, 5, 25, 12),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('toggle saves then removes and reports the new state', () async {
    final service = SavedSpeechesService();

    expect(service.isSaved('a'), isFalse);
    expect(await service.toggle(_speech('a')), isTrue);
    expect(service.isSaved('a'), isTrue);
    expect(service.saved, hasLength(1));

    expect(await service.toggle(_speech('a')), isFalse);
    expect(service.isSaved('a'), isFalse);
    expect(service.saved, isEmpty);
  });

  test('saved is ordered newest-first', () async {
    final service = SavedSpeechesService();
    await service.toggle(_speech('old', savedAt: DateTime(2026, 1, 1)));
    await service.toggle(_speech('new', savedAt: DateTime(2026, 5, 1)));

    expect(service.saved.map((s) => s.speechId).toList(), ['new', 'old']);
  });

  test('persisted bookmarks survive a reload', () async {
    final first = SavedSpeechesService();
    await first.toggle(_speech('a'));

    final second = SavedSpeechesService();
    await second.load();

    expect(second.isSaved('a'), isTrue);
    expect(second.saved.single.speakerName, 'Jane Smith');
  });

  test('notifies listeners on change', () async {
    final service = SavedSpeechesService();
    var notified = 0;
    service.addListener(() => notified++);

    await service.toggle(_speech('a'));
    await service.remove('a');

    expect(notified, 2);
  });
}
