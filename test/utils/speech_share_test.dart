import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/speech_share.dart';

void main() {
  group('buildSpeechShareText', () {
    test('combines speaker, body and a context footer', () {
      final text = buildSpeechShareText(
        speakerName: 'Jane Smith',
        speechText: 'I beg to move.',
        debateTitle: 'Finance Bill',
        displayDate: '25 May 2026',
      );
      expect(
        text,
        'Jane Smith\n'
        'I beg to move.\n'
        '\n'
        '— Finance Bill · 25 May 2026, Hansard',
      );
    });

    test('omits the speaker line when there is no speaker', () {
      final text = buildSpeechShareText(
        speakerName: '   ',
        speechText: 'Question put and agreed to.',
        debateTitle: 'Finance Bill',
        displayDate: '25 May 2026',
      );
      expect(text.startsWith('Question put and agreed to.'), isTrue);
    });

    test('omits the footer when there is no context', () {
      final text = buildSpeechShareText(
        speakerName: 'Jane Smith',
        speechText: 'Hear, hear.',
        debateTitle: '',
        displayDate: '',
      );
      expect(text, 'Jane Smith\nHear, hear.');
    });
  });
}
