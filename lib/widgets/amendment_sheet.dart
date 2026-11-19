import 'package:flutter/material.dart';

import '../models/amendment.dart';
import '../utils/amendment_diff.dart';

// Same green / red as the Aye / No tags in the voting record, so "added" and
// "removed" read the same way as the vote itself.
const Color _addedColor = Color(0xFF006548);
const Color _removedColor = Color(0xFFB50938);

/// Opens a bottom sheet showing what a division was voting on: the
/// amendment's text as a diff (removed text struck through in red, added text
/// in green), its explanatory statement and, for the Lords, the motion as
/// recorded by the House.
///
/// [future] is resolved inside the sheet so it opens instantly.
/// [onOpenBill] is shown as an "Open bill" action once a bill id is known.
Future<void> showAmendmentSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<DivisionAmendment> future,
  void Function(int billId)? onOpenBill,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => AmendmentSheet(
        title: title,
        subtitle: subtitle,
        future: future,
        scrollController: controller,
        onOpenBill: onOpenBill == null
            ? null
            : (id) {
                Navigator.of(sheetContext).pop();
                onOpenBill(id);
              },
      ),
    ),
  );
}

/// Content of [showAmendmentSheet]. Public so it can be pumped directly in
/// widget tests.
class AmendmentSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final Future<DivisionAmendment> future;
  final ScrollController? scrollController;
  final void Function(int billId)? onOpenBill;

  const AmendmentSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.future,
    this.scrollController,
    this.onOpenBill,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<DivisionAmendment>(
      future: future,
      builder: (context, snap) {
        final children = <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ];

        if (snap.connectionState != ConnectionState.done) {
          children.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ));
        } else if (snap.hasError || !snap.hasData) {
          children.add(const _Notice("Couldn't load the amendment. Check your "
              'connection and try again.'));
        } else {
          children.addAll(_content(context, snap.data!));
        }

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: children,
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, DivisionAmendment data) {
    final theme = Theme.of(context);
    final a = data.amendment;
    final widgets = <Widget>[];

    if (data.motionText != null) {
      widgets
        ..add(const _Label('Motion'))
        ..add(const SizedBox(height: 6))
        ..add(_DiffText(
          lines: [data.motionText!],
          baseStyle: theme.textTheme.bodyMedium,
        ))
        ..add(const SizedBox(height: 20));
    }

    if (a != null) {
      final header = [
        'Amendment ${a.number}',
        if (data.stageName != null) data.stageName!,
      ].join(' · ');
      widgets.add(Row(
        children: [
          Expanded(child: _Label(header)),
          if (a.decisionLabel != null) _DecisionTag(a.decisionLabel!),
        ],
      ));
      if (a.sponsors.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Tabled by ${_sponsorLine(a.sponsors)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ));
      }
      final explanation = a.explanatoryText == null
          ? ''
          : _plain(a.explanatoryText!);
      if (explanation.isNotEmpty) {
        widgets
          ..add(const SizedBox(height: 12))
          ..add(DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('In plain English'),
                  const SizedBox(height: 4),
                  Text(explanation, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ));
      }
      widgets
        ..add(const SizedBox(height: 16))
        ..add(_AmendmentBody(amendment: a));
    } else if (data.unavailableReason != null) {
      widgets.add(_Notice(data.unavailableReason!));
    }

    if (data.billId != null && onOpenBill != null) {
      widgets
        ..add(const SizedBox(height: 16))
        ..add(Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => onOpenBill!(data.billId!),
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('Open bill'),
          ),
        ));
    }

    widgets
      ..add(const SizedBox(height: 16))
      ..add(Text(
        'Source: UK Parliament Bills API'
        '${data.motionText != null ? ' and Lords Votes API' : ''}.',
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ));
    return widgets;
  }

  static String _sponsorLine(List<String> names) {
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    final others = names.length - 1;
    return '${names.first} and $others others';
  }

  static String _plain(String html) => cleanAmendmentHtml(html)
      .replaceAll('\u0001', '')
      .replaceAll('\u0002', '')
      .trim();
}

/// The printed amendment, line by line with its indentation and hanging
/// labels, coloured as a diff.
class _AmendmentBody extends StatelessWidget {
  final Amendment amendment;
  const _AmendmentBody({required this.amendment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = amendment;
    // An inserted paragraph's opening quote is often printed in its hanging
    // label (`“(f)`), so move it onto the text for the diff to see it.
    bool opensQuote(AmendmentLine l) =>
        l.hangingIndentation?.startsWith('“') ?? false;
    final segmented = segmentAmendment(
      [for (final l in a.lines) opensQuote(l) ? '“${l.text}' : l.text],
      quotesAreInsertions: a.kind == AmendmentKind.addClause,
    );
    final hasRemoved = a.kind == AmendmentKind.deleteClause ||
        segmented.expand((s) => s).any((s) => s.op == DiffOp.deleted);
    final hasAdded =
        segmented.expand((s) => s).any((s) => s.op == DiffOp.inserted);

    final rows = <Widget>[];
    for (var i = 0; i < a.lines.length; i++) {
      final line = a.lines[i];
      rows.add(Padding(
        padding: EdgeInsets.only(
          left: (line.indentation.clamp(0, 4)) * 14.0,
          bottom: 6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (line.hangingIndentation != null)
              SizedBox(
                width: 34,
                child: Text(
                  line.hangingIndentation!.replaceFirst('“', ''),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: _spans(context, segmented[i]),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    // Whole-clause changes get a coloured rule down the side, like a diff
    // gutter, since every line is an addition / removal.
    final gutter = switch (a.kind) {
      AmendmentKind.addClause => _addedColor,
      AmendmentKind.deleteClause => _removedColor,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.location != null) ...[
          Text(
            a.location!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (a.kind == AmendmentKind.deleteClause)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Removes existing text from the bill.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _removedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Container(
          padding: EdgeInsets.only(left: gutter == null ? 0 : 12),
          decoration: gutter == null
              ? null
              : BoxDecoration(
                  border: Border(left: BorderSide(color: gutter, width: 3)),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
        if (hasRemoved || hasAdded) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              if (hasRemoved) const _LegendItem('Removed', _removedColor),
              if (hasAdded) const _LegendItem('Added', _addedColor),
            ],
          ),
        ],
      ],
    );
  }
}

/// Free-text motion wording (Lords notes) rendered with the same diff colours.
class _DiffText extends StatelessWidget {
  final List<String> lines;
  final TextStyle? baseStyle;
  const _DiffText({required this.lines, this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final segmented = segmentAmendment(lines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segs in segmented)
          Text.rich(
            TextSpan(children: _spans(context, segs), style: baseStyle),
          ),
      ],
    );
  }
}

List<InlineSpan> _spans(BuildContext context, List<DiffSegment> segs) {
  final theme = Theme.of(context);
  return [
    for (final s in segs)
      TextSpan(
        text: s.text,
        style: switch (s.op) {
          DiffOp.instruction => TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: s.bold ? FontWeight.w700 : null,
            ),
          DiffOp.anchor => TextStyle(
              fontWeight: s.bold ? FontWeight.w700 : FontWeight.w600,
            ),
          DiffOp.deleted => TextStyle(
              color: _removedColor,
              decoration: TextDecoration.lineThrough,
              decorationColor: _removedColor,
              backgroundColor: _removedColor.withValues(alpha: 0.10),
              fontWeight: s.bold ? FontWeight.w700 : null,
            ),
          DiffOp.inserted => TextStyle(
              color: _addedColor,
              backgroundColor: _addedColor.withValues(alpha: 0.10),
              fontWeight: s.bold ? FontWeight.w700 : null,
            ),
        },
      ),
  ];
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _DecisionTag extends StatelessWidget {
  final String label;
  const _DecisionTag(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = label.startsWith('Agreed')
        ? _addedColor
        : label.startsWith('Negatived') || label.startsWith('Disagreed')
            ? _removedColor
            : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
