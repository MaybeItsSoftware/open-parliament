import 'package:flutter/foundation.dart';

import '../services/parliamentary_data_service.dart';

/// A member (or organisation) sponsoring a bill.
class BillSponsor {
  final int? memberId;
  final String name;
  final String? party;
  final String? photoUrl;
  final String? constituency;

  const BillSponsor({
    required this.name,
    this.memberId,
    this.party,
    this.photoUrl,
    this.constituency,
  });

  factory BillSponsor.fromJson(Map<String, dynamic> json) {
    final member = json['member'] as Map<String, dynamic>?;
    final organisation = json['organisation'] as Map<String, dynamic>?;
    if (member != null) {
      return BillSponsor(
        memberId: (member['memberId'] as num?)?.toInt(),
        name: (member['name'] as String?) ?? '',
        party: member['party'] as String?,
        photoUrl: member['memberPhoto'] as String?,
        constituency: member['memberFrom'] as String?,
      );
    }
    return BillSponsor(name: (organisation?['name'] as String?) ?? '');
  }
}

/// A single stage in a bill's passage (e.g. "2nd reading", "Committee stage").
class BillStage {
  final int id;
  final String description;
  final String house;
  final DateTime? date;
  final bool isCurrent;

  const BillStage({
    required this.id,
    required this.description,
    required this.house,
    required this.isCurrent,
    this.date,
  });

  factory BillStage.fromJson(
    Map<String, dynamic> json, {
    required int? currentStageId,
  }) {
    final sittings = (json['stageSittings'] as List<dynamic>?) ?? const [];
    DateTime? earliest;
    for (final sitting in sittings.whereType<Map<String, dynamic>>()) {
      final parsed = DateTime.tryParse((sitting['date'] as String?) ?? '');
      if (parsed == null) continue;
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (earliest == null || day.isBefore(earliest)) earliest = day;
    }
    final id = (json['id'] as num?)?.toInt() ?? 0;
    return BillStage(
      id: id,
      description: (json['description'] as String?) ?? '',
      house: (json['house'] as String?) ?? '',
      date: earliest,
      isCurrent: currentStageId != null && id == currentStageId,
    );
  }
}

/// A news article / update published about a bill.
class BillNews {
  final String title;
  final String content;
  final DateTime? date;

  const BillNews({required this.title, required this.content, this.date});

  factory BillNews.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['displayDate'] as String?) ?? '';
    final parsed = DateTime.tryParse(rawDate);
    return BillNews(
      title: (json['title'] as String?) ?? '',
      content: _stripHtml((json['content'] as String?) ?? ''),
      date: parsed != null
          ? DateTime(parsed.year, parsed.month, parsed.day)
          : null,
    );
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&mdash;', '—')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        // Collapse the space a stripped inline tag can leave before punctuation.
        .replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m.group(1)!)
        .trim();
  }
}

/// The canonical type/category for a bill (e.g. Government Bill, Private Bill).
class BillType {
  final int id;
  final String category;
  final String name;
  final String description;

  const BillType({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
  });

  factory BillType.fromJson(Map<String, dynamic> json) {
    return BillType(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: (json['category'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }
}

/// The status of a bill's progress through Parliament.
enum BillStatus { inProgress, act, defeated, withdrawn }

/// Top-level metadata for a single bill.
class Bill {
  final int id;
  final String shortTitle;
  final String longTitle;
  final String? summary;
  final String currentHouse;
  final String originatingHouse;
  final String? currentStageDescription;
  final DateTime? lastUpdate;
  final BillStatus status;
  final List<BillSponsor> sponsors;
  final int? billTypeId;
  final String? formerShortTitle;

  const Bill({
    required this.id,
    required this.shortTitle,
    required this.longTitle,
    required this.currentHouse,
    required this.originatingHouse,
    required this.status,
    required this.sponsors,
    this.summary,
    this.currentStageDescription,
    this.lastUpdate,
    this.billTypeId,
    this.formerShortTitle,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    final currentStage = json['currentStage'] as Map<String, dynamic>?;
    final sponsors = ((json['sponsors'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BillSponsor.fromJson)
        .where((s) => s.name.isNotEmpty)
        .toList();

    final isAct = (json['isAct'] as bool?) ?? false;
    final isDefeated = (json['isDefeated'] as bool?) ?? false;
    final withdrawn = json['billWithdrawn'] != null;
    final status = isAct
        ? BillStatus.act
        : withdrawn
            ? BillStatus.withdrawn
            : isDefeated
                ? BillStatus.defeated
                : BillStatus.inProgress;

    final lastRaw = json['lastUpdate'] as String?;

    return Bill(
      id: (json['billId'] as num?)?.toInt() ?? 0,
      shortTitle: (json['shortTitle'] as String?) ?? '',
      longTitle: (json['longTitle'] as String?) ?? '',
      summary: json['summary'] as String?,
      currentHouse: (json['currentHouse'] as String?) ?? '',
      originatingHouse: (json['originatingHouse'] as String?) ?? '',
      currentStageDescription: currentStage?['description'] as String?,
      lastUpdate: lastRaw != null ? DateTime.tryParse(lastRaw) : null,
      status: status,
      sponsors: sponsors,
      billTypeId: (json['billTypeId'] as num?)?.toInt(),
      formerShortTitle: json['formerShortTitle'] as String?,
    );
  }
}

/// Loads a single bill's detail, stage history, and news updates.
///
/// Construction takes a [billTitle] (as detected from a debate); [load]
/// resolves it to a bill id, then fetches detail, stages, and news in parallel.
class BillViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;
  final String billTitle;

  bool _isLoading = true;
  bool _disposed = false;
  String? _error;
  int? _billId;
  Bill? _bill;
  BillType? _billType;
  List<BillStage> _stages = const [];
  List<BillNews> _news = const [];

  /// When [billId] is supplied (e.g. opened from the recent-bills list) the
  /// title→id lookup is skipped.
  BillViewModel(this._service, {required this.billTitle, int? billId})
      : _billId = billId;

  bool get isLoading => _isLoading;
  String? get error => _error;
  int? get billId => _billId;
  Bill? get bill => _bill;
  BillType? get billType => _billType;

  /// Stage history, most recent first.
  List<BillStage> get stages => _stages;

  /// News updates, most recent first.
  List<BillNews> get news => _news;

  /// The public bills.parliament.uk page, available once the id is resolved.
  Uri? get billPageUrl =>
      _billId != null ? Uri.parse('https://bills.parliament.uk/bills/$_billId') : null;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final id = _billId ?? await _service.findBillId(billTitle);
      if (id == null) {
        _error = 'No matching bill found.';
        _isLoading = false;
        _safeNotify();
        return;
      }
      _billId = id;

      final detailFuture = _service.fetchBillDetail(id);
      final stagesFuture = _service.fetchBillStages(id);
      final newsFuture = _service.fetchBillNews(id);
      final typesFuture = _service.fetchBillTypes();

      final detail = await detailFuture;
      final rawStages = await stagesFuture;
      final rawNews = await newsFuture;
      final rawTypes = await typesFuture;

      if (detail != null) _bill = Bill.fromJson(detail);
      _billType = _resolveBillType(rawTypes, _bill?.billTypeId);

      final currentStageId =
          (detail?['currentStage'] as Map<String, dynamic>?)?['id'] as int?;
      _stages = rawStages
          .map((json) {
            try {
              return BillStage.fromJson(json, currentStageId: currentStageId);
            } catch (_) {
              return null;
            }
          })
          .whereType<BillStage>()
          .where((s) => s.description.isNotEmpty)
          .toList()
          .reversed // API returns chronological; show newest first.
          .toList();

      _news = rawNews
          .map((json) {
            try {
              return BillNews.fromJson(json);
            } catch (_) {
              return null;
            }
          })
          .whereType<BillNews>()
          .where((n) => n.title.isNotEmpty || n.content.isNotEmpty)
          .toList();

      if (_bill == null && _stages.isEmpty && _news.isEmpty) {
        _error = 'Could not load bill details.';
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  BillType? _resolveBillType(
    List<Map<String, dynamic>> rawTypes,
    int? billTypeId,
  ) {
    if (billTypeId == null) return null;
    for (final json in rawTypes) {
      try {
        final type = BillType.fromJson(json);
        if (type.id == billTypeId) return type;
      } catch (_) {
        // Skip malformed bill type entries.
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
