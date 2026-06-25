import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/council.dart';
import 'package:open_hansard/viewmodels/council_history_viewmodel.dart';
import 'package:open_hansard/widgets/council_control_history_chart.dart';

void main() {
  CouncilYearControl year(int y, Map<String, int> seats) => CouncilYearControl(
        year: y,
        // total: 0 on purpose — the historical snapshots report an unreliable
        // total, so the chart must size columns from the seat counts instead.
        council: Council(
          name: 'Adur',
          type: 'District',
          control: 'LAB',
          seats: seats,
          total: 0,
        ),
      );

  Future<void> pump(WidgetTester tester, List<CouncilYearControl> history,
      {double width = 800}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: CouncilControlHistoryChart(history: history),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders bars with real height even when council.total is 0',
      (tester) async {
    await pump(tester, [
      year(2024, const {'Lab': 30, 'Con': 10}),
      year(2023, const {'Lab': 25, 'Con': 15}),
    ]);

    // The tallest year (40 seats) should fill (nearly) the full chart height.
    final boxes = find.descendant(
      of: find.byType(CouncilControlHistoryChart),
      matching: find.byType(ColoredBox),
    );
    expect(boxes, findsWidgets);

    // Bars must have BOTH real height and real width — a ColoredBox with no
    // intrinsic width collapses to 0px wide unless the column stretches it,
    // which is exactly the bug that left the chart blank on screen.
    var sawRealBar = false;
    for (final element in boxes.evaluate()) {
      final size = element.size;
      if (size != null && size.height > 1 && size.width > 1) sawRealBar = true;
    }
    expect(sawRealBar, isTrue,
        reason: 'bars must have non-zero height AND width (regression: '
            'invisible / zero-width bars)');
  });

  testWidgets('stretches to fill the width when few years are shown',
      (tester) async {
    await pump(tester, [year(2024, const {'Lab': 20, 'Con': 20})], width: 600);
    // A single year filling the width: no horizontal scroll view is created.
    expect(
      find.descendant(
        of: find.byType(CouncilControlHistoryChart),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('renders bars inside an unbounded-height sliver context',
      (tester) async {
    // Mirrors the real placement: the chart lives in a SliverToBoxAdapter,
    // which hands its child UNBOUNDED height — the case a Center/SizedBox test
    // never exercises.
    final years = [
      for (var y = 2017; y <= 2026; y++) year(y, const {'Con': 28, 'Lab': 20}),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CouncilControlHistoryChart(history: years),
              ),
            ],
          ),
        ),
      ),
    );

    final boxes = find.descendant(
      of: find.byType(CouncilControlHistoryChart),
      matching: find.byType(ColoredBox),
    );
    expect(boxes, findsWidgets);
    final real = boxes.evaluate().any(
        (e) => (e.size?.height ?? 0) > 1 && (e.size?.width ?? 0) > 1);
    expect(real, isTrue,
        reason: 'bars must have height AND width in a sliver context');
  });

  testWidgets('scrolls horizontally when too many years to fit', (tester) async {
    final many = [
      for (var y = 1990; y <= 2026; y++) year(y, const {'Lab': 10, 'Con': 5}),
    ];
    await pump(tester, many, width: 300); // 37 years can't fit in 300px
    expect(
      find.descendant(
        of: find.byType(CouncilControlHistoryChart),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders SankeyFlowPainter in both layouts', (WidgetTester tester) async {
    const history = [
      CouncilYearControl(
        year: 2026,
        council: Council(
          name: 'Adur',
          type: 'District',
          control: 'LAB',
          seats: {'Lab': 17, 'Con': 0, 'Oth': 12},
          total: 29,
        ),
      ),
      CouncilYearControl(
        year: 2025,
        council: Council(
          name: 'Adur',
          type: 'District',
          control: 'LAB',
          seats: {'Lab': 15, 'Con': 2, 'Oth': 12},
          total: 29,
        ),
      ),
    ];

    // Layout 1: Stretched (few years, wide screen)
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800, // Wide enough for stretched layout
            child: CouncilControlHistoryChart(history: history),
          ),
        ),
      ),
    ));

    expect(find.byType(CustomPaint), findsWidgets);
    var customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    var hasSankey = customPaints.any((p) => p.painter is SankeyFlowPainter);
    expect(hasSankey, isTrue, reason: 'SankeyFlowPainter should be rendered in stretched layout');

    // Layout 2: Scrollable (many years, narrow screen)
    final manyYears = [
      for (var y = 2000; y <= 2026; y++)
        CouncilYearControl(
          year: y,
          council: const Council(
            name: 'Adur',
            type: 'District',
            control: 'LAB',
            seats: {'Lab': 15, 'Con': 2, 'Oth': 12},
            total: 29,
          ),
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200, // Too narrow, forces scrollable layout
            child: CouncilControlHistoryChart(history: manyYears),
          ),
        ),
      ),
    ));

    expect(find.byType(CustomPaint), findsWidgets);
    customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    hasSankey = customPaints.any((p) => p.painter is SankeyFlowPainter);
    expect(hasSankey, isTrue, reason: 'SankeyFlowPainter should be rendered in scrollable layout');
  });

  test('SankeyFlowPainter paints without error when history is empty', () {
    final painter = SankeyFlowPainter(
      years: [],
      order: [],
      maxTotal: 10,
      columnWidth: 20,
      columnGap: 6,
    );
    // Verifying it extends CustomPainter and can be instanced.
    expect(painter, isA<CustomPainter>());
  });

  test('SankeyFlowPainter shouldRepaint returns true when fields change', () {
    final painter1 = SankeyFlowPainter(
      years: [],
      order: const ['Lab'],
      maxTotal: 10,
      columnWidth: 20,
      columnGap: 6,
    );
    final painter2 = SankeyFlowPainter(
      years: [],
      order: const ['Lab'],
      maxTotal: 10,
      columnWidth: 20,
      columnGap: 6,
    );
    // When no fields change
    expect(painter1.shouldRepaint(painter2), isFalse);

    final painter3 = SankeyFlowPainter(
      years: [],
      order: const ['Con'],
      maxTotal: 10,
      columnWidth: 20,
      columnGap: 6,
    );
    expect(painter1.shouldRepaint(painter3), isTrue);
  });

  test('SankeyFlowPainter draws paths between years with seats', () {
    const y2023 = CouncilYearControl(
      year: 2023,
      council: Council(
        name: 'Test',
        type: 'District',
        control: 'LAB',
        seats: {'Lab': 10},
        total: 10,
      ),
    );
    const y2024 = CouncilYearControl(
      year: 2024,
      council: Council(
        name: 'Test',
        type: 'District',
        control: 'LAB',
        seats: {'Lab': 10},
        total: 10,
      ),
    );

    final painter = SankeyFlowPainter(
      years: const [y2023, y2024],
      order: const ['Lab'],
      maxTotal: 10,
      columnWidth: 20,
      columnGap: 6,
    );

    final canvas = TestCanvas();
    painter.paint(canvas, const Size(100, 100));

    expect(canvas.drawnPaths, hasLength(1));
    expect(canvas.drawnPaints, hasLength(1));
    expect(canvas.drawnPaints.first.color.a, closeTo(0.3, 0.01));
  });

  test('SankeyFlowPainter stacks parties correctly top-to-bottom and draws flows', () {
    const y2023 = CouncilYearControl(
      year: 2023,
      council: Council(
        name: 'Test',
        type: 'District',
        control: 'LAB',
        seats: {'Con': 25, 'Lab': 15},
        total: 40,
      ),
    );
    const y2024 = CouncilYearControl(
      year: 2024,
      council: Council(
        name: 'Test',
        type: 'District',
        control: 'LAB',
        seats: {'Con': 30, 'Lab': 10},
        total: 40,
      ),
    );

    final painter = SankeyFlowPainter(
      years: const [y2023, y2024],
      order: const ['Con', 'Lab'],
      maxTotal: 40,
      columnWidth: 20,
      columnGap: 6,
    );

    final canvas = TestCanvas();
    painter.paint(canvas, const Size(100, 100));

    expect(canvas.drawnPaths, hasLength(2));
    
    final conPath = canvas.drawnPaths[0];
    final labPath = canvas.drawnPaths[1];

    final conBounds = conPath.getBounds();
    final labBounds = labPath.getBounds();

    // StartX = 20 (columnWidth). EndX = 26 (StartX + columnGap).
    expect(conBounds.left, closeTo(20.0, 0.01));
    expect(conBounds.right, closeTo(26.0, 0.01));
    // Con top in 2023 is 37.5. Con top in 2024 is 25.0. Minimum is 25.0.
    expect(conBounds.top, closeTo(25.0, 0.01));
    // Con bottom is 100 in both.
    expect(conBounds.bottom, closeTo(100.0, 0.01));

    expect(labBounds.left, closeTo(20.0, 0.01));
    expect(labBounds.right, closeTo(26.0, 0.01));
    // Lab top in 2023 is 0. Lab top in 2024 is 0. Minimum is 0.
    expect(labBounds.top, closeTo(0.0, 0.01));
    // Lab bottom in 2023 is 37.5. Lab bottom in 2024 is 25.0. Maximum is 37.5.
    expect(labBounds.bottom, closeTo(37.5, 0.01));
  });
}

class TestCanvas extends Fake implements Canvas {
  final List<Path> drawnPaths = [];
  final List<Paint> drawnPaints = [];

  @override
  void drawPath(Path path, Paint paint) {
    drawnPaths.add(path);
    drawnPaints.add(paint);
  }
}
