import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/party_colors.dart' as party_util;
import 'package:open_hansard/widgets/control_split_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<ControlSegment> segments) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControlSplitBar(segments: segments)),
      ),
    );
  }

  testWidgets('renders one weighted segment per non-zero entry', (tester) async {
    await pump(tester, const [
      (label: 'Lab', value: 17),
      (label: 'Con', value: 0), // skipped
      (label: 'Green', value: 2),
    ]);

    final expandeds = tester.widgetList<Expanded>(find.byType(Expanded));
    expect(expandeds, hasLength(2));
    expect(expandeds.map((e) => e.flex), [17, 2]);
  });

  testWidgets('colours the Vacant bucket with the neutral no-control colour',
      (tester) async {
    await pump(tester, const [
      (label: 'Lab', value: 10),
      (label: 'Vacant', value: 3),
    ]);

    final boxes = tester
        .widgetList<ColoredBox>(find.descendant(
          of: find.byType(ControlSplitBar),
          matching: find.byType(ColoredBox),
        ))
        .toList();
    expect(boxes, hasLength(2));
    expect(boxes.first.color, party_util.partyColor('Lab'));
    expect(boxes.last.color, party_util.noControlColor);
  });

  testWidgets('renders nothing when every segment is empty', (tester) async {
    await pump(tester, const [(label: 'Lab', value: 0)]);
    expect(find.byType(Expanded), findsNothing);
  });
}
