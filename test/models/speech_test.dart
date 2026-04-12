import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/speech.dart';

void main() {
  group('Speech', () {
    const debateId = 'debate-001';
    const debateTitle = 'Oral Answers to Questions';

    test('fromApiJson parses typical Hansard response', () {
      final json = {
        'ItemId': 'item-001',
        'MemberId': 172,
        'MemberName': 'Adam Smith',
        'AttributedTo': 'Adam Smith (Labour, Some Constituency)',
        'Value': '<p>I thank the Minister for his answer.</p>',
        'Timecode': '10:00:00',
      };

      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 0,
      );

      expect(speech.id, 'item-001');
      expect(speech.memberId, 172);
      expect(speech.memberName, 'Adam Smith');
      expect(speech.debateId, debateId);
      expect(speech.debateTitle, debateTitle);
      expect(speech.timecode, '10:00:00');
      expect(speech.orderIndex, 0);
    });

    test('fromApiJson strips HTML tags from Value', () {
      final json = {
        'ItemId': 'item-002',
        'Value': '<p>First paragraph.</p><p>Second paragraph.</p>',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 1,
      );
      expect(speech.speechText, isNot(contains('<p>')));
      expect(speech.speechText, contains('First paragraph.'));
      expect(speech.speechText, contains('Second paragraph.'));
    });

    test('fromApiJson decodes HTML entities', () {
      final json = {
        'ItemId': 'item-003',
        'Value': 'A &amp; B &lt;C&gt; &quot;D&quot; &#39;E&#39; &mdash; Z',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 2,
      );
      expect(speech.speechText, 'A & B <C> "D" \'E\' — Z');
    });

    test('fromApiJson removes column-number spans before text extraction', () {
      final json = {
        'ItemId': 'item-003b',
        'Value':
            '<span class="column-number">Column 123</span><p>Real content</p>',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 2,
      );
      expect(speech.speechText, 'Real content');
    });

    test('fromApiJson captures HRSTag fields', () {
      final json = {
        'ItemId': 'item-003c',
        'HRSTag': 'hs_quote',
        'Value': 'Quoted line',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 2,
      );
      expect(speech.hrsTag, 'hs_quote');
      expect(speech.isQuote, isTrue);
    });

    test('fromApiJson generates id from debateId + orderIndex when absent', () {
      final json = {'Value': 'Some text'};
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 5,
      );
      expect(speech.id, '${debateId}_5');
    });

    test('fromApiJson extracts memberName from AttributedTo when absent', () {
      final json = {
        'AttributedTo': 'Jane Doe (Conservative)',
        'Value': 'Hear, hear.',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 0,
      );
      expect(speech.memberName, 'Jane Doe');
    });

    test('fromApiJson accepts numeric ItemId and string MemberId', () {
      final json = {
        'ItemId': 48456144,
        'MemberId': '172',
        'Value': 'Some text',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 0,
      );
      expect(speech.id, '48456144');
      expect(speech.memberId, 172);
    });

    test('fromApiJson marks timestamp items and derives display time', () {
      final json = {
        'ItemType': 'Timestamp',
        'Value': '10:07:00',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 0,
      );
      expect(speech.isTimestamp, isTrue);
      expect(speech.displayTime, '10:07');
      expect(speech.hasNamedSpeaker, isFalse);
    });

    test('fromApiJson marks unattributed contribution as procedural', () {
      final json = {
        'ItemType': 'Contribution',
        'Value': 'Announcement',
      };
      final speech = Speech.fromApiJson(
        json,
        debateId: debateId,
        debateTitle: debateTitle,
        orderIndex: 0,
      );
      expect(speech.isProceduralText, isTrue);
      expect(speech.isTimestamp, isFalse);
    });

    test('toDb / fromDb round-trip preserves all fields', () {
      const speech = Speech(
        id: 'sp-1',
        debateId: 'debate-1',
        debateTitle: 'Some Debate',
        itemType: 'Contribution',
        hrsTag: 'hs_para',
        memberId: 42,
        memberName: 'Jane Doe',
        attributedTo: 'Jane Doe (Con)',
        speechText: 'Thank you, Mr Speaker.',
        timecode: '14:30:00',
        orderIndex: 7,
      );

      final row = speech.toDb();
      final restored = Speech.fromDb(row);

      expect(restored.id, speech.id);
      expect(restored.debateId, speech.debateId);
      expect(restored.debateTitle, speech.debateTitle);
      expect(restored.itemType, speech.itemType);
      expect(restored.hrsTag, speech.hrsTag);
      expect(restored.memberId, speech.memberId);
      expect(restored.memberName, speech.memberName);
      expect(restored.attributedTo, speech.attributedTo);
      expect(restored.speechText, speech.speechText);
      expect(restored.timecode, speech.timecode);
      expect(restored.orderIndex, speech.orderIndex);
    });

    test('equality is based on id', () {
      const a = Speech(
        id: 'sp-1',
        debateId: 'd1',
        debateTitle: 'T1',
        memberName: 'A',
        attributedTo: '',
        speechText: 'foo',
        orderIndex: 0,
      );
      const b = Speech(
        id: 'sp-1',
        debateId: 'd2',
        debateTitle: 'T2',
        memberName: 'B',
        attributedTo: '',
        speechText: 'bar',
        orderIndex: 1,
      );
      expect(a, equals(b));
    });
  });
}
