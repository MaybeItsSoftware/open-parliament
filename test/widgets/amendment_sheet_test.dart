import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/amendment.dart';
import 'package:open_parliament/widgets/amendment_sheet.dart';

Widget _host(Future<DivisionAmendment> future, {void Function(int)? onOpen}) =>
    MaterialApp(
      home: Scaffold(
        body: AmendmentSheet(
          title: 'Railways Bill',
          subtitle: '18 Nov 2026 · Voted Aye',
          future: future,
          onOpenBill: onOpen,
        ),
      ),
    );

void main() {
  testWidgets('renders amendment, explanation, motion and legend',
      (tester) async {
    int? opened;
    await tester.pumpWidget(_host(
      Future.value(
        DivisionAmendment(
          billId: 20,
          stageName: 'Report stage',
          motionText: 'Baroness X moved amendment 16.',
          amendment: Amendment.fromJson(const {
            'marshalledListText': '16',
            'amendmentType': 'EditBillBody',
            'decision': 'Agreed',
            'clause': 3,
            'pageNumber': 4,
            'lineNumber': 5,
            'explanatoryText': '<p>Makes it stricter.</p>',
            'sponsors': [
              {'name': 'Baroness X', 'sortOrder': 1},
            ],
            'amendmentLines': [
              {'text': 'leave out “may” and insert “must”', 'indentation': 0},
            ],
          }),
        ),
      ),
      onOpen: (id) => opened = id,
    ));
    await tester.pumpAndSettle();

    expect(find.text('AMENDMENT 16 · REPORT STAGE'), findsOneWidget);
    expect(find.text('Agreed'), findsOneWidget);
    expect(find.text('Tabled by Baroness X'), findsOneWidget);
    expect(find.text('Makes it stricter.'), findsOneWidget);
    expect(find.text('Clause 3 · page 4 · line 5'), findsOneWidget);
    expect(find.text('Baroness X moved amendment 16.', findRichText: true),
        findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);

    await tester.tap(find.text('Open bill'));
    expect(opened, 20);
  });

  testWidgets('shows the reason when no amendment text exists',
      (tester) async {
    await tester.pumpWidget(_host(Future.value(const DivisionAmendment(
      unavailableReason: 'Not on a numbered amendment.',
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Not on a numbered amendment.'), findsOneWidget);
    expect(find.text('Open bill'), findsNothing);
  });

  testWidgets('shows an error when the lookup fails', (tester) async {
    // Marked handled up front: the error exists before FutureBuilder listens.
    final failed = Future<DivisionAmendment>.error(Exception('offline'))
      ..ignore();
    await tester.pumpWidget(_host(failed));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load the amendment"), findsOneWidget);
  });
}
