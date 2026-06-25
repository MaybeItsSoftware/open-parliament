# Design Spec: Continuous Sankey-style Flows for Council Control History Chart

Implement smooth, continuous Sankey-style colored ribbons connecting the party seat segments between year columns in the council control history chart.

## Problem Statement
The council history page currently shows political control over time as a series of disjointed vertical stacked columns. While this displays yearly compositions well, it does not visually convey the continuity of transitions (i.e. how party sizes flow and shift across the years).

## Proposed Design
We will draw continuous, semi-transparent colored flows (ribbons) connecting matching party segments from one year to the next using cubic Bezier curves.

```
   Year N                     Year N+1
   ┌─────┐      Ribbon        ┌─────┐
   │     │   ~~~~~~~~~~~~~~~  │     │
   │ Con │ ◄- (Bezier curve)  │ Con │
   │     │   ~~~~~~~~~~~~~~~  │     │
   ├─────┤                    ├─────┤
   │ Lab │                    │ Lab │
   └─────┘                    └─────┘
```

### Components and Layout
We will wrap the history chart in a `Stack` containing:
1. A background `CustomPaint` utilizing a new `SankeyFlowPainter` to draw the curves.
2. The existing `Row` of columns (rendered with transparent backgrounds or in their normal stack alignment) placed directly over the painted canvas.

### Coordinate Mathematics
To align the painter with the columns:
* **Stretched Mode**: Width of each column `colW` on a canvas of width `W` is:
  $$\text{colW} = \frac{W - \text{gap} \times (N - 1)}{N}$$
  where `gap = 6`.
* **Scrollable Mode**: Width of each column is fixed at `_scrollColumnWidth = 20`, and `gap = 6`.
* **Segment Y-coordinates**: In year column $i$, for each party $P$ (iterated from bottom Y to top Y, using the global stacking order `order.reversed`):
  * Bottom $Y$ of segment = current cumulative $Y$ (starts at `_chartHeight = 120`).
  * Top $Y$ of segment = $Y - \frac{\text{seats}[P]}{\text{maxTotal}} \times \text{_chartHeight}$.
  * Set cumulative $Y$ to the top $Y$ and proceed to the next party.

### Rendering the Flows
For each consecutive pair of years $(i, i+1)$ and each party:
* The flow ribbon starts at $X_1 = i \times (\text{colW} + \text{gap}) + \text{colW}$.
* The flow ribbon ends at $X_2 = X_1 + \text{gap}$.
* Draw a path from $X_1$ to $X_2$ using cubic Bezier curves:
  * Top curve: from $(X_1, y_{\text{top}, i})$ to $(X_2, y_{\text{top}, i+1})$ with control points $(X_1 + \frac{\text{gap}}{2}, y_{\text{top}, i})$ and $(X_1 + \frac{\text{gap}}{2}, y_{\text{top}, i+1})$.
  * Right edge: vertical line from $(X_2, y_{\text{top}, i+1})$ to $(X_2, y_{\text{bottom}, i+1})$.
  * Bottom curve: back to $(X_1, y_{\text{bottom}, i})$ with control points $(X_1 + \frac{\text{gap}}{2}, y_{\text{bottom}, i+1})$ and $(X_1 + \frac{\text{gap}}{2}, y_{\text{bottom}, i})$.
  * Close the path and fill it with the party's brand color at $30\%$ opacity (e.g. `color.withOpacity(0.3)`).

## Test Plan
1. **Unit Tests**: Add tests verifying coordinate calculations and path generation logic under both stretched and scrollable layouts.
2. **Visual Verification**: Verify that the columns align pixel-perfectly with the start and end edges of the custom-painted curves.
