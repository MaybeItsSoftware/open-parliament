/// A named period during which a house of Parliament does not sit — a recess
/// (e.g. *"Summer recess"*), a holiday adjournment, or a dissolution — as
/// returned by the What's On API's non-sitting-days endpoint.
class RecessPeriod {
  /// Human-readable name, e.g. `"Summer recess"`. Never empty: falls back to
  /// `"Recess"` when the API omits a description.
  final String description;

  /// First non-sitting day of the period, normalised to midnight.
  final DateTime startDate;

  /// Last non-sitting day of the period (inclusive), normalised to midnight.
  final DateTime endDate;

  /// The house the period applies to (`Commons` or `Lords`); may be empty.
  final String house;

  const RecessPeriod({
    required this.description,
    required this.startDate,
    required this.endDate,
    this.house = '',
  });

  /// Whether [day] falls within the period (any time component is ignored).
  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(startDate) && !d.isAfter(endDate);
  }

  /// Parses one event object from `/calendar/events/nonsitting.json`.
  ///
  /// Tolerates both PascalCase and camelCase keys (the What's On API uses
  /// PascalCase, but be liberal in what we accept). Returns `null` when no
  /// start date can be parsed; a missing end date yields a single-day period.
  /// [fallbackHouse] is used when the payload carries no house of its own
  /// (the caller knows which house it queried for).
  static RecessPeriod? fromApiJson(
    Map<String, dynamic> json, {
    String fallbackHouse = '',
  }) {
    final start = _parseDate(json['StartDate'] ?? json['startDate']);
    if (start == null) return null;
    final end = _parseDate(json['EndDate'] ?? json['endDate']) ?? start;

    final description =
        ((json['Description'] ?? json['description']) as String?)?.trim() ??
            '';
    final house = ((json['House'] ?? json['house']) as String?)?.trim() ?? '';

    return RecessPeriod(
      description: description.isEmpty ? 'Recess' : description,
      startDate: start,
      // Guard against a malformed payload where the range is inverted.
      endDate: end.isBefore(start) ? start : end,
      house: house.isEmpty ? fallbackHouse : house,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
