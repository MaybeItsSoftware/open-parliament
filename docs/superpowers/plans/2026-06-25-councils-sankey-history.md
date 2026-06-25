# Council Control History Sankey Diagram Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement smooth, continuous Sankey-style flows connecting the party segments between year columns in the council control history chart.

**Architecture:** Use a `CustomPainter` to draw Bezier curves (ribbons) connecting matching party segments from one year to the next. The painter sits in the background of a `Stack` directly under the columns.

**Tech Stack:** Flutter CustomPainter, Bezier Curves.

## Global Constraints
* The custom paint flows must align pixel-perfectly with the vertical column layout.
* Supported years range from 1973 to 2026 (or whichever years are loaded in `history`).
* Oppacity for the flows is 30% (`withOpacity(0.3)`).

---

### Task 1: Implement SankeyFlowPainter

**Files:**
- Modify: `lib/widgets/council_control_history_chart.dart`
- Test: `test/widgets/council_control_history_chart_test.dart`

**Interfaces:**
- Produces: `SankeyFlowPainter` class extending `CustomPainter`

- [ ] **Step 1: Write failing test verifying painter exists and handles empty history**
  Add a test to `test/widgets/council_control_history_chart_test.dart`:
  ```dart
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
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/widgets/council_control_history_chart_test.dart`
  Expected: FAIL (compilation error, SankeyFlowPainter not found)

- [ ] **Step 3: Write minimal implementation of SankeyFlowPainter**
  Define `SankeyFlowPainter` in `lib/widgets/council_control_history_chart.dart`:
  ```dart
  class SankeyFlowPainter extends CustomPainter {
    final List<CouncilYearControl> years;
    final List<String> order;
    final int maxTotal;
    final double columnWidth;
    final double columnGap;

    SankeyFlowPainter({
      required this.years,
      required this.order,
      required this.maxTotal,
      required this.columnWidth,
      required this.columnGap,
    });

    @override
    void paint(Canvas canvas, Size size) {
      if (years.isEmpty || maxTotal <= 0) return;

      final count = years.length;
      // Stretched mode vs Scrollable mode:
      // If columnWidth is dynamic (i.e. <= 0), compute it from size.width.
      final colW = columnWidth > 0
          ? columnWidth
          : (size.width - columnGap * (count - 1)) / count;

      // Track vertical segment coordinates for each column
      final columnSegmentsY = List.generate(count, (_) => <String, ({double top, double bottom})>{});

      for (var i = 0; i < count; i++) {
        final council = years[i].council;
        double yCurrent = size.height;

        for (final label in order.reversed) {
          final seats = council.seats[label] ?? 0;
          if (seats > 0) {
            final double height = (seats / maxTotal) * size.height;
            final double top = yCurrent - height;
            columnSegmentsY[i][label] = (top: top, bottom: yCurrent);
            yCurrent = top;
          } else {
            columnSegmentsY[i][label] = (top: yCurrent, bottom: yCurrent);
          }
        }
      }

      // Draw flows between consecutive columns
      for (var i = 0; i < count - 1; i++) {
        final startX = i * (colW + columnGap) + colW;
        final endX = startX + columnGap;

        for (final label in order) {
          final segmentLeft = columnSegmentsY[i][label];
          final segmentRight = columnSegmentsY[i + 1][label];
          if (segmentLeft == null || segmentRight == null) continue;

          // Only draw if there are seats in either column
          if (segmentLeft.bottom > segmentLeft.top || segmentRight.bottom > segmentRight.top) {
            final color = controlSegmentColor(label).withOpacity(0.3);
            final paint = Paint()
              ..color = color
              ..style = PaintingStyle.fill;

            final path = Path()
              ..moveTo(startX, segmentLeft.top)
              ..cubicTo(
                startX + columnGap / 2,
                segmentLeft.top,
                startX + columnGap / 2,
                segmentRight.top,
                endX,
                segmentRight.top,
              )
              ..lineTo(endX, segmentRight.bottom)
              ..cubicTo(
                startX + columnGap / 2,
                segmentRight.bottom,
                startX + columnGap / 2,
                segmentLeft.bottom,
                startX,
                segmentLeft.bottom,
              )
              ..close();

            canvas.drawPath(path, paint);
          }
        }
      }
    }

    @override
    bool shouldRepaint(covariant SankeyFlowPainter oldDelegate) {
      return oldDelegate.years != years ||
          oldDelegate.order != order ||
          oldDelegate.maxTotal != maxTotal ||
          oldDelegate.columnWidth != columnWidth ||
          oldDelegate.columnGap != columnGap;
    }
  }
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/widgets/council_control_history_chart_test.dart`
  Expected: PASS

---

### Task 2: Integrate SankeyFlowPainter into CouncilControlHistoryChart Layout

**Files:**
- Modify: `lib/widgets/council_control_history_chart.dart`
- Test: `test/widgets/council_control_history_chart_test.dart`

- [ ] **Step 1: Write a failing widget test verifying Stack and painter integration**
  Add a test to `test/widgets/council_control_history_chart_test.dart` to assert that `CustomPaint` containing `SankeyFlowPainter` is rendered in both the Row and scrollable layouts.
  ```dart
  testWidgets('renders SankeyFlowPainter in both layouts', (WidgetTester tester) async {
    final history = [
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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CouncilControlHistoryChart(history: history),
      ),
    ));

    expect(find.byType(CustomPaint), findsWidgets);
    final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    final hasSankey = customPaints.any((p) => p.painter is SankeyFlowPainter);
    expect(hasSankey, isTrue);
  });
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/widgets/council_control_history_chart_test.dart`
  Expected: FAIL (No CustomPaint/SankeyFlowPainter in widget tree)

- [ ] **Step 3: Modify CouncilControlHistoryChart layout to wrap in Stack**
  In `lib/widgets/council_control_history_chart.dart`, wrap the rows with the custom painter.
  For the stretched row:
  ```dart
              if (perColumn >= _minColumnWidth) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: SankeyFlowPainter(
                          years: years,
                          order: order,
                          maxTotal: maxTotal,
                          columnWidth: 0, // dynamic width
                          columnGap: _columnGap,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < years.length; i++) ...[
                          if (i > 0) const SizedBox(width: _columnGap),
                          Expanded(child: _column(theme, years[i], order, maxTotal)),
                        ],
                      ],
                    ),
                  ],
                );
              }
  ```
  For the scrollable row:
  ```dart
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 20, // offset labels at bottom (labels height is approx 20)
                      child: CustomPaint(
                        painter: SankeyFlowPainter(
                          years: years,
                          order: order,
                          maxTotal: maxTotal,
                          columnWidth: _scrollColumnWidth,
                          columnGap: _columnGap,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final entry in years)
                          Padding(
                            padding: const EdgeInsets.only(right: _columnGap),
                            child: SizedBox(
                              width: _scrollColumnWidth,
                              child: _column(theme, entry, order, maxTotal),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
  ```

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/widgets/council_control_history_chart_test.dart`
  Expected: PASS
